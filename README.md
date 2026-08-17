<div align="center">

<img src="logo.png" alt="VEYNA" width="110">

# VEYNA Panel

**One command. Your server. Your users.**

[![English](https://img.shields.io/badge/English-5B5BD6?style=for-the-badge&labelColor=1a1a1a)](README.md)
[![فارسی](https://img.shields.io/badge/%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-2a2a2a?style=for-the-badge&labelColor=1a1a1a)](README.fa.md)

</div>

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh | sudo bash
```

Database, web server, certificates and the VPN node are all set up for you.

| Requirement | |
|---|---|
| <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white&labelColor=1a1a1a" height="22"> | 22.04 or newer |
| <img src="https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white&labelColor=1a1a1a" height="22"> | 12 or newer |
| <img src="https://img.shields.io/badge/Arch-2a2a2a?style=flat-square&logo=linux&logoColor=white&labelColor=1a1a1a" height="22"> | x86_64 |

---

## After install

The installer prints your panel address and admin path. Open it and sign in.

```bash
sudo veyna-panelctl info      # your panel URL
sudo veyna-panelctl status    # is it running
sudo veyna-panelctl health    # is it healthy
```

## Non-interactive

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh -o install.sh
sudo bash install.sh -y \
  --domain panel.example.com \
  --admin-user admin \
  --admin-pass 'ChangeThis123!'
```

`sudo bash install.sh --help` lists every option.

## Updating

Re-run the installer. Your admin path, encryption key and database password stay exactly as they were.

---

<div align="center">

<sub>Client app</sub>

[![VEYNA App](https://img.shields.io/badge/VEYNA-App-5B5BD6?style=for-the-badge&labelColor=1a1a1a)](https://github.com/cerbenum/Veyna.App)

<br>

<sub>Proprietary — see [LICENSE](LICENSE). This repository ships the installer only; the source is closed.</sub>

<br>

**Cerbenum**

</div>
