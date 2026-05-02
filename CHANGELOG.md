# Changelog

## 1.2.0

- Added a management option to update installed upstream relay projects.
- The manager can now pull the latest changes for installed relay repositories, rebuild the binaries, and restart the managed services.

## 1.1.1

- Improved recovery of existing installations when the saved state file is missing.
- Added nginx configuration fallback detection via `sites-enabled` and `nginx -T` when the expected file in `sites-available` is no longer present.

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
