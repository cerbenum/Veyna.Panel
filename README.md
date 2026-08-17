# Veyna Panel

Self-hosted management panel for Veyna. Install it on your own Ubuntu/Debian server.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh | sudo bash
```

Non-interactive:

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh -o install.sh
sudo bash install.sh -y --mode systemd --domain panel.example.com \
  --admin-user admin --admin-pass 'YourSecurePassword123!'
```

Run `sudo bash install.sh --help` for all options.

## Management

```bash
sudo veyna-panelctl status
sudo veyna-panelctl health
sudo veyna-panelctl logs -f
```

## License

Proprietary — see [LICENSE](LICENSE). This repository ships only the installer and compiled
release binaries; the source is closed.
