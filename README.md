# Moblin OBS Relay Manager

`Moblin OBS Relay Manager` is a convenience installer and management layer for these two upstream projects on Debian and Ubuntu:

- `moblin-remote-control-relay`
- `obs-remote-control-relay`

It does not replace the upstream repositories. It simplifies installing and operating them together behind one nginx and Let's Encrypt setup.

The project currently consists of a single installer and management script:

- `install-relays.sh`
- `VERSION`
- `CHANGELOG.md`

On the target host, the script installs itself system-wide as:

- `/usr/local/sbin/moblin-obs-relay-manager`

## Features

- Non-interactive package installation on Debian and Ubuntu
- Initial system update and upgrade
- Nginx reverse proxy for both relay services
- Let's Encrypt certificate issuance and renewal
- IPv4 and IPv6 firewall rules via `nftables`
- Management mode for existing installations
- Uninstall flow with optional self-removal

## Versioning

This project uses semantic versioning. The current release is stored in `VERSION`, and user-facing release notes live in `CHANGELOG.md`.

## Usage

Run the script directly:

```bash
sudo bash install-relays.sh
```

After installation, it is available system-wide as:

```bash
sudo moblin-obs-relay-manager
```
