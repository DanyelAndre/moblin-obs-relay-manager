# Changelog

## 1.1.0

- Added a pre-install selection so users can install only `moblin-remote-control-relay`, only `obs-remote-control-relay`, or both.
- Updated the installer, saved state, nginx configuration, and managed services to respect the selected upstream projects.
- Updated the README to document the optional relay selection during installation.

## 1.0.0

- Initial public release.
- Installs and manages `moblin-remote-control-relay` and `obs-remote-control-relay` together on Debian and Ubuntu.
- Configures nginx reverse proxying, Let's Encrypt certificates, and `nftables`.
- Supports a management mode for viewing configuration, changing the hostname, renewing certificates, updating endpoints, and uninstalling the managed setup.
- Installs a system-wide management command at `/usr/local/sbin/moblin-obs-relay-manager`.
