# ATC — Advanced Target Control

**Made by Pakun**

Hydra-class Kali menu. Private repo.

## Install (`apt`)

```bash
git clone git@github.com:brazyqueso/ATC.git
cd ATC
sudo bash install.sh
```

`install.sh` copies the package into a local apt repo and then runs:

```bash
sudo apt install atc
```

After that, on **that same machine**, you can also:

```bash
sudo apt install atc
sudo apt remove atc
sudo apt purge atc
```

Or skip the helper and install the `.deb` directly:

```bash
sudo apt install ./apt/atc_1.0.1_all.deb
```

GitHub CLI:

```bash
gh repo clone brazyqueso/ATC
cd ATC
sudo apt install ./apt/atc_1.0.1_all.deb
```

## Launch

```bash
sudo ATC
```

Also: **Applications → ATC**

```
github.com/brazyqueso
github.com/brazyqueso/ATC
```

Authorized lab / pentest use only.
