# ATC — Advanced Target Control

**Made by Pakun & iinze0**

Hydra-class Kali menu. `sudo ATC` after one install.

## Install (use this)

`apt install /tmp/atc.deb` often fails on Kali (`_apt` cannot read `/tmp`). Use **dpkg**:

```bash
wget -O /tmp/atc.deb https://github.com/brazyqueso/ATC/releases/download/v1.0.2/atc_1.0.2_all.deb
sudo dpkg -i /tmp/atc.deb
sudo ATC
```

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/brazyqueso/ATC/main/install-atc.sh | sudo bash
sudo ATC
```

Check version after install:

```bash
dpkg -s atc | grep Version
```

Should say `1.0.2`.

Uninstall:

```bash
sudo apt remove atc
sudo apt purge atc
```

## Launch

```bash
sudo ATC
```

Also: **Applications → ATC**

Pick the interface with **(default route)** — not `wlan0mon` — then option **1** to scan.

## Other install paths

From a clone:

```bash
git clone https://github.com/brazyqueso/ATC.git
cd ATC
sudo dpkg -i ./apt/atc_1.0.2_all.deb
sudo ATC
```

```
github.com/brazyqueso
github.com/brazyqueso/ATC
```

Authorized lab / pentest use only.
