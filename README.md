# ATC — Advanced Target Control

**Made by Pakun & iinze0**

Hydra-class Kali menu. `sudo ATC` after one apt install.

## Install

```bash
wget -O /tmp/atc.deb https://github.com/brazyqueso/ATC/releases/download/v1.0.2/atc_1.0.2_all.deb
sudo apt install --reinstall /tmp/atc.deb
sudo ATC
```

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
sudo apt install ./apt/atc_1.0.2_all.deb
sudo ATC
```

or register a local apt source then `sudo apt install atc`:

```bash
git clone https://github.com/brazyqueso/ATC.git
cd ATC
sudo bash install.sh
sudo ATC
```

```
github.com/brazyqueso
github.com/brazyqueso/ATC
```

Authorized lab / pentest use only.
