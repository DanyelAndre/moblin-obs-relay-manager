# Moblin OBS Relay Manager

`Moblin OBS Relay Manager` is a convenience installer and management layer for these two upstream projects on Debian and Ubuntu:

- `moblin-remote-control-relay`
- `obs-remote-control-relay`

It does not replace the upstream repositories. It simplifies installing and operating them together behind one nginx setup, either with public HTTPS and Let's Encrypt or in a LAN-only HTTPS deployment using a Cloudflare DNS challenge.

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
- Optional public HTTPS mode with Let's Encrypt certificate issuance and renewal
- Optional LAN HTTPS mode using a Cloudflare DNS challenge for non-publicly reachable servers
- IPv4 and IPv6 firewall rules via `nftables`
- Optional installation of either upstream relay project or both together
- Management mode for existing installations
- Update workflow for installed upstream relay projects
- Uninstall flow with optional self-removal

## Versioning

This project uses semantic versioning. The current release is stored in `VERSION`, and user-facing release notes live in `CHANGELOG.md`.

## Quick Start

1. Use a fresh Debian or Ubuntu server whenever possible.
2. Decide whether you want:
   - `public HTTPS mode` with DNS and Let's Encrypt
   - `LAN HTTPS mode` with Cloudflare DNS and a certificate for a LAN-only server
3. If you choose `public HTTPS mode`, make sure your DNS name already points to the server and ports `80/tcp` and `443/tcp` are reachable from the public internet.
4. If you choose `LAN HTTPS mode`, make sure the server is reachable on port `443/tcp` from the private network where it will be used and that you control the hostname's DNS zone in Cloudflare.
5. Download and run the installer:

```bash
curl -fsSL -o /tmp/install-relays.sh https://raw.githubusercontent.com/DanyelAndre/moblin-obs-relay-manager/main/install-relays.sh && sudo bash /tmp/install-relays.sh
```

6. Follow the interactive prompts for:

- installation mode
- which upstream relay projects should be installed
- hostname and Let's Encrypt email address
- Cloudflare DNS setup and API token in `LAN HTTPS mode`
- the current server LAN IPv4 as the default value for the LAN DNS record step
- Moblin endpoint
- OBS endpoint

After the initial installation, the manager is available system-wide as:

```bash
sudo moblin-obs-relay-manager
```

From the management menu, you can also update the installed upstream relay projects to their latest repository state.

In `LAN HTTPS mode`, the manager still uses a full hostname and TLS certificate, but obtains the certificate through a Cloudflare DNS challenge instead of requiring public reachability on the server itself.
Hostname changes and manual certificate renewal remain available in both HTTPS modes.

## Troubleshooting

If the manager script or saved state file is missing, but the relay services are still running, you can bootstrap the manager again with:

```bash
curl -fsSL -o /tmp/install-relays.sh https://raw.githubusercontent.com/DanyelAndre/moblin-obs-relay-manager/main/install-relays.sh && sudo bash /tmp/install-relays.sh
```

The manager will try to recover the existing installation from the current systemd units and nginx configuration.

## Known Risks

- This script is intended primarily for fresh systems.
- It can modify or replace existing nginx configuration, TLS setup, firewall rules, installed packages, and managed services.
- LAN HTTPS mode requires the chosen hostname to exist in a Cloudflare-managed DNS zone and to resolve to the server's LAN IPv4 address via a DNS-only A record.
- Running it on a server that already hosts production workloads can break existing websites or other networked applications.
- The firewall configuration is opinionated and intentionally restrictive.
- The uninstall flow purges managed packages such as `nginx`, `certbot`, `git`, `golang-go`, `nftables`, `python3-certbot-nginx`, and `python3-certbot-dns-cloudflare`.
