# Moblin OBS Relay Manager

`Moblin OBS Relay Manager` is a convenience installer and management layer for these two upstream projects on Debian and Ubuntu:

- `moblin-remote-control-relay`
- `obs-remote-control-relay`

It does not replace the upstream repositories. It simplifies installing and operating them together behind one nginx and Let's Encrypt setup.

## Upstream Projects

This project is a convenience layer around these upstream repositories:

- [moblin-remote-control-relay](https://github.com/eerimoq/moblin-remote-control-relay)
- [obs-remote-control-relay](https://github.com/eerimoq/obs-remote-control-relay)

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
- Optional installation of either upstream relay project or both together
- Management mode for existing installations
- Uninstall flow with optional self-removal

## Versioning

This project uses semantic versioning. The current release is stored in `VERSION`, and user-facing release notes live in `CHANGELOG.md`.

## Quick Start

1. Use a fresh Debian or Ubuntu server whenever possible.
2. Make sure your DNS name already points to the server.
3. Make sure ports `80/tcp` and `443/tcp` are reachable from the public internet.
4. Run the installer:

```bash
sudo bash install-relays.sh
```

5. Follow the interactive prompts for:

- which upstream relay projects should be installed
- hostname
- Let's Encrypt email address
- Moblin endpoint
- OBS endpoint

After the initial installation, the manager is available system-wide as:

```bash
sudo moblin-obs-relay-manager
```

## Known Risks

- This script is intended primarily for fresh systems.
- It can modify or replace existing nginx configuration, TLS setup, firewall rules, installed packages, and managed services.
- Running it on a server that already hosts production workloads can break existing websites or other networked applications.
- The firewall configuration is opinionated and intentionally restrictive.
- The uninstall flow purges managed packages such as `nginx`, `certbot`, `git`, `golang-go`, `nftables`, and `python3-certbot-nginx`.
