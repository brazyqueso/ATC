# ATC — Advanced Target Control

**Made by Pakun & iinze0**

## Install (use dpkg — apt /tmp will fail)

```bash
wget -O /tmp/atc.deb https://github.com/brazyqueso/ATC/releases/download/v1.0.4/atc_1.0.4_all.deb
sudo dpkg -i /tmp/atc.deb
sudo ATC
```

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/brazyqueso/ATC/main/install-atc.sh | sudo bash
sudo ATC
```

You should see **v1.0.4**, a snake with a top hat, and **Made by Pakun & iinze0**.

```bash
dpkg -s atc | grep Version
```

Uninstall: `sudo apt purge atc`

## Launch

```bash
sudo ATC
```

Also: **Applications → ATC**

Pick the interface with **(default route)** — not `wlan0mon` — then option **1** to scan.

```
github.com/brazyqueso
github.com/brazyqueso/ATC
```

Authorized lab / pentest use only.
