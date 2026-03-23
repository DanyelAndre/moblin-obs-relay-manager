#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly DEFAULT_MOBLIN_ENDPOINT="/moblin-remote-control-relay/"
readonly DEFAULT_OBS_ENDPOINT="/obs-remote-control-relay/"
readonly SCRIPT_NAME="Moblin OBS Relay Manager"
readonly SCRIPT_VERSION="1.1.0"
readonly RELAY_USER="obsrelay"
readonly INSTALL_ROOT="/opt/remote-control-relays"
readonly MOBLIN_REPO_URL="https://github.com/eerimoq/moblin-remote-control-relay.git"
readonly OBS_REPO_URL="https://github.com/eerimoq/obs-remote-control-relay.git"
readonly MOBLIN_DIR="${INSTALL_ROOT}/moblin-remote-control-relay"
readonly OBS_DIR="${INSTALL_ROOT}/obs-remote-control-relay"
readonly MOBLIN_PORT="9998"
readonly OBS_PORT="9999"
readonly MOBLIN_SERVICE_NAME="moblin-remote-control-relay"
readonly OBS_SERVICE_NAME="obs-remote-control-relay"
readonly MOBLIN_SERVICE_FILE="/etc/systemd/system/${MOBLIN_SERVICE_NAME}.service"
readonly OBS_SERVICE_FILE="/etc/systemd/system/${OBS_SERVICE_NAME}.service"
readonly NGINX_SITE_NAME="remote-control-relays"
readonly NGINX_SITE_FILE="/etc/nginx/sites-available/${NGINX_SITE_NAME}"
readonly NGINX_SITE_LINK="/etc/nginx/sites-enabled/${NGINX_SITE_NAME}"
readonly STATE_FILE="/etc/remote-control-relays.conf"
readonly SELF_INSTALL_PATH="/usr/local/sbin/moblin-obs-relay-manager"
readonly -a MANAGED_PACKAGES=(
  certbot
  git
  golang-go
  nginx
  nftables
  python3-certbot-nginx
)

DOMAIN=""
CERTBOT_EMAIL=""
INSTALL_MOBLIN="yes"
INSTALL_OBS="yes"
MOBLIN_ENDPOINT="${DEFAULT_MOBLIN_ENDPOINT}"
OBS_ENDPOINT="${DEFAULT_OBS_ENDPOINT}"
MOBLIN_PROXY_BASE="$(printf '%s' "${DEFAULT_MOBLIN_ENDPOINT%/}")"
OBS_PROXY_BASE="$(printf '%s' "${DEFAULT_OBS_ENDPOINT%/}")"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_yes() {
  [[ "$1" == "yes" ]]
}

prompt_yes_default() {
  local prompt_text="$1"
  local answer

  read -r -p "${prompt_text} [Y/n]: " answer
  case "${answer}" in
    n|N|no|NO)
      printf 'no'
      ;;
    *)
      printf 'yes'
      ;;
  esac
}

clear_screen() {
  if [[ -t 1 ]] && command_exists clear; then
    clear
  fi
}

print_banner() {
  printf '%s v%s\n\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
}

pause() {
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to continue." _
  fi
}

script_source_path() {
  if [[ "$0" == */* ]]; then
    printf '%s/%s\n' "$(cd "$(dirname "$0")" && pwd -P)" "$(basename "$0")"
    return
  fi

  command -v -- "$0"
}

require_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return
  fi

  if command_exists sudo; then
    exec sudo -E bash "$0" "$@"
  fi

  fail "This script requires root privileges. If sudo is not installed yet, run it once directly as root."
}

check_os() {
  [[ -r /etc/os-release ]] || fail "/etc/os-release is missing. Only Debian and Ubuntu are supported."

  # shellcheck disable=SC1091
  source /etc/os-release

  case "${ID:-}" in
    debian|ubuntu)
      ;;
    *)
      if [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        return
      fi
      fail "Unsupported operating system: ${PRETTY_NAME:-${ID:-unknown}}. Expected Debian or Ubuntu."
      ;;
  esac

  command_exists apt-get || fail "apt-get was not found."
  command_exists systemctl || fail "systemctl was not found."
}

confirm_destructive_warning() {
  cat <<'EOF'
WARNING:

This installer is intended for fresh Debian or Ubuntu systems only.
It may overwrite or alter existing configuration, firewall rules, web server setup,
TLS configuration, and system services. If you run it on a system that already hosts
websites or other production workloads, those services may stop working or become
unusable afterwards.
Use this script entirely at your own risk. The author accepts no liability for any
damage, downtime, data loss, misconfiguration, or other consequences resulting from
its use.

EOF

  local answer
  read -r -p "Do you want to continue anyway? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      fail "Installation aborted."
      ;;
  esac
}

confirm_prerequisites() {
  cat <<'EOF'
Before installation, the following requirements must already be met:

1. The DNS name for this installation already points to this server.
2. Ports 80/tcp and 443/tcp are reachable from the public internet.
3. The firewall will later allow new incoming connections only on ports 22/tcp, 80/tcp, and 443/tcp.
4. If IPv6 DNS records are present, IPv6 connectivity to this server must also be working.
5. SSH remains reachable on port 22/tcp after the installation.

EOF

  local answer
  read -r -p "Are these requirements satisfied, and should the installation continue? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      fail "Installation aborted."
      ;;
  esac
}

confirm_uninstall() {
  cat <<'EOF'
WARNING:

This will stop and remove the managed relay services, delete the nginx and certificate
configuration created by this script, remove the checked-out relay repositories, and
purge the managed packages installed for this setup.

EOF

  local answer
  read -r -p "Do you really want to uninstall everything? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      fail "Uninstallation aborted."
      ;;
  esac
}

apt_update_once() {
  if [[ -n "${APT_UPDATED:-}" ]]; then
    return
  fi

  log "Updating package lists."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  APT_UPDATED=1
}

upgrade_system_once() {
  if [[ -n "${SYSTEM_UPGRADED:-}" ]]; then
    return
  fi

  apt_update_once
  log "Upgrading installed packages."
  apt-get upgrade -y
  SYSTEM_UPGRADED=1
}

install_self_copy() {
  local source_path

  source_path="$(script_source_path)"
  [[ -f "${source_path}" ]] || {
    warn "Could not determine the current script location. Skipping installation to ${SELF_INSTALL_PATH}."
    return
  }

  if [[ "${source_path}" == "${SELF_INSTALL_PATH}" ]]; then
    return
  fi

  mkdir -p "$(dirname "${SELF_INSTALL_PATH}")"

  if cmp -s "${source_path}" "${SELF_INSTALL_PATH}" 2>/dev/null; then
    return
  fi

  log "Installing this script to ${SELF_INSTALL_PATH}."
  install -m 0755 "${source_path}" "${SELF_INSTALL_PATH}"
}

ensure_commands() {
  local missing_packages=()
  local spec
  local command_name
  local package_name

  for spec in "$@"; do
    IFS=':' read -r command_name package_name <<<"${spec}"
    if ! command_exists "${command_name}"; then
      missing_packages+=("${package_name}")
    fi
  done

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    return
  fi

  apt_update_once
  log "Installing missing base tools: ${missing_packages[*]}"
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
}

ensure_packages() {
  local missing_packages=()
  local package_name

  for package_name in "$@"; do
    if ! dpkg -s "${package_name}" >/dev/null 2>&1; then
      missing_packages+=("${package_name}")
    fi
  done

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    return
  fi

  apt_update_once
  log "Installing packages: ${missing_packages[*]}"
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
}

prompt_required() {
  local prompt_text="$1"
  local value=""

  while [[ -z "${value}" ]]; do
    read -r -p "${prompt_text}" value
  done

  printf '%s' "${value}"
}

normalize_endpoint() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ -n "${value}" ]] || fail "An endpoint must not be empty."

  if [[ "${value}" != /* ]]; then
    value="/${value}"
  fi

  while [[ "${value}" == *"//"* ]]; do
    value="${value//\/\//\/}"
  done

  if [[ "${value}" != */ ]]; then
    value="${value}/"
  fi

  [[ "${value}" != "/" ]] || fail "An endpoint must not consist of only /."
  [[ "${value}" != *" "* ]] || fail "An endpoint must not contain spaces."

  printf '%s' "${value}"
}

strip_trailing_slash() {
  local value="$1"

  value="${value%/}"
  [[ -n "${value}" ]] || fail "Invalid endpoint."
  printf '%s' "${value}"
}

validate_distinct_endpoints() {
  if is_yes "${INSTALL_MOBLIN}" && is_yes "${INSTALL_OBS}"; then
    [[ "${MOBLIN_ENDPOINT}" != "${OBS_ENDPOINT}" ]] || fail "The Moblin and OBS endpoints must be different."
  fi
}

sync_proxy_bases() {
  if is_yes "${INSTALL_MOBLIN}"; then
    MOBLIN_PROXY_BASE="$(strip_trailing_slash "${MOBLIN_ENDPOINT}")"
  fi

  if is_yes "${INSTALL_OBS}"; then
    OBS_PROXY_BASE="$(strip_trailing_slash "${OBS_ENDPOINT}")"
  fi
}

validate_selected_projects() {
  if ! is_yes "${INSTALL_MOBLIN}" && ! is_yes "${INSTALL_OBS}"; then
    fail "At least one upstream relay project must be selected for installation."
  fi
}

certificate_files_exist() {
  [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]] && [[ -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]]
}

save_state() {
  umask 077
  cat >"${STATE_FILE}" <<EOF
DOMAIN=$(printf '%q' "${DOMAIN}")
CERTBOT_EMAIL=$(printf '%q' "${CERTBOT_EMAIL}")
INSTALL_MOBLIN=$(printf '%q' "${INSTALL_MOBLIN}")
INSTALL_OBS=$(printf '%q' "${INSTALL_OBS}")
MOBLIN_ENDPOINT=$(printf '%q' "${MOBLIN_ENDPOINT}")
OBS_ENDPOINT=$(printf '%q' "${OBS_ENDPOINT}")
EOF
}

extract_domain_from_nginx() {
  awk '
    $1 == "server_name" {
      gsub(/;/, "", $2)
      print $2
      exit
    }
  ' "${NGINX_SITE_FILE}"
}

extract_proxy_base_from_unit() {
  local unit_file="$1"

  awk '
    $1 ~ /^ExecStart=/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "-reverse_proxy_base") {
          print $(i + 1)
          exit
        }
      }
    }
  ' "${unit_file}"
}

extract_certbot_email() {
  local domain_name="$1"
  local renewal_file="/etc/letsencrypt/renewal/${domain_name}.conf"

  if [[ ! -f "${renewal_file}" ]]; then
    return
  fi

  awk -F'=' '
    $1 ~ /^[[:space:]]*email[[:space:]]*$/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "${renewal_file}"
}

infer_current_configuration() {
  [[ -f "${NGINX_SITE_FILE}" ]] || fail "Cannot infer the current configuration because ${NGINX_SITE_FILE} is missing."

  DOMAIN="$(extract_domain_from_nginx)"
  [[ -n "${DOMAIN}" ]] || fail "Could not determine the configured hostname from ${NGINX_SITE_FILE}."

  INSTALL_MOBLIN="no"
  INSTALL_OBS="no"

  if [[ -f "${MOBLIN_SERVICE_FILE}" ]]; then
    INSTALL_MOBLIN="yes"
    MOBLIN_PROXY_BASE="$(extract_proxy_base_from_unit "${MOBLIN_SERVICE_FILE}")"
    [[ -n "${MOBLIN_PROXY_BASE}" ]] || fail "Could not determine the configured Moblin endpoint from ${MOBLIN_SERVICE_FILE}."
    MOBLIN_ENDPOINT="$(normalize_endpoint "${MOBLIN_PROXY_BASE}")"
  else
    MOBLIN_ENDPOINT="${DEFAULT_MOBLIN_ENDPOINT}"
  fi

  if [[ -f "${OBS_SERVICE_FILE}" ]]; then
    INSTALL_OBS="yes"
    OBS_PROXY_BASE="$(extract_proxy_base_from_unit "${OBS_SERVICE_FILE}")"
    [[ -n "${OBS_PROXY_BASE}" ]] || fail "Could not determine the configured OBS endpoint from ${OBS_SERVICE_FILE}."
    OBS_ENDPOINT="$(normalize_endpoint "${OBS_PROXY_BASE}")"
  else
    OBS_ENDPOINT="${DEFAULT_OBS_ENDPOINT}"
  fi

  validate_selected_projects
  CERTBOT_EMAIL="$(extract_certbot_email "${DOMAIN}")"
  validate_distinct_endpoints
  sync_proxy_bases
}

load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    DOMAIN="${DOMAIN:-}"
    CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
    INSTALL_MOBLIN="${INSTALL_MOBLIN:-}"
    INSTALL_OBS="${INSTALL_OBS:-}"
    if [[ -z "${INSTALL_MOBLIN}" ]]; then
      if [[ -f "${MOBLIN_SERVICE_FILE}" ]]; then
        INSTALL_MOBLIN="yes"
      else
        INSTALL_MOBLIN="no"
      fi
    fi
    if [[ -z "${INSTALL_OBS}" ]]; then
      if [[ -f "${OBS_SERVICE_FILE}" ]]; then
        INSTALL_OBS="yes"
      else
        INSTALL_OBS="no"
      fi
    fi
    MOBLIN_ENDPOINT="$(normalize_endpoint "${MOBLIN_ENDPOINT:-${DEFAULT_MOBLIN_ENDPOINT}}")"
    OBS_ENDPOINT="$(normalize_endpoint "${OBS_ENDPOINT:-${DEFAULT_OBS_ENDPOINT}}")"
    validate_selected_projects
    validate_distinct_endpoints
    sync_proxy_bases
    return
  fi

  log "No saved state file was found. Reading the current configuration from system files."
  infer_current_configuration
  save_state
}

existing_installation_detected() {
  [[ -f "${STATE_FILE}" ]] || [[ -f "${MOBLIN_SERVICE_FILE}" ]] || [[ -f "${OBS_SERVICE_FILE}" ]] || [[ -f "${NGINX_SITE_FILE}" ]]
}

collect_install_configuration() {
  DOMAIN="$(prompt_required 'DNS name (for example relay.example.com): ')"
  CERTBOT_EMAIL=""
  read -r -p "Email address for Let's Encrypt (leave empty to register without email): " CERTBOT_EMAIL

  local moblin_input
  local obs_input

  INSTALL_MOBLIN="$(prompt_yes_default 'Install moblin-remote-control-relay?')"
  INSTALL_OBS="$(prompt_yes_default 'Install obs-remote-control-relay?')"
  validate_selected_projects

  if is_yes "${INSTALL_MOBLIN}"; then
    read -r -p "The original Moblin endpoint is ${DEFAULT_MOBLIN_ENDPOINT}. Press Enter to keep it, or enter a custom endpoint: " moblin_input
    MOBLIN_ENDPOINT="$(normalize_endpoint "${moblin_input:-${DEFAULT_MOBLIN_ENDPOINT}}")"
  else
    MOBLIN_ENDPOINT="${DEFAULT_MOBLIN_ENDPOINT}"
  fi

  if is_yes "${INSTALL_OBS}"; then
    read -r -p "The original OBS endpoint is ${DEFAULT_OBS_ENDPOINT}. Press Enter to keep it, or enter a custom endpoint: " obs_input
    OBS_ENDPOINT="$(normalize_endpoint "${obs_input:-${DEFAULT_OBS_ENDPOINT}}")"
  else
    OBS_ENDPOINT="${DEFAULT_OBS_ENDPOINT}"
  fi

  validate_distinct_endpoints
  sync_proxy_bases
}

install_dependencies() {
  ensure_commands "curl:curl" "sudo:sudo"
  ensure_packages \
    ca-certificates \
    git \
    golang-go \
    nginx \
    certbot \
    python3-certbot-nginx \
    nftables
}

ensure_service_user() {
  if id -u "${RELAY_USER}" >/dev/null 2>&1; then
    return
  fi

  log "Creating system user ${RELAY_USER}."
  useradd \
    --system \
    --user-group \
    --home-dir "${INSTALL_ROOT}" \
    --shell /usr/sbin/nologin \
    "${RELAY_USER}"
}

clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    log "Updating repository: ${target_dir}"
    git -C "${target_dir}" pull --ff-only
    return
  fi

  if [[ -e "${target_dir}" ]]; then
    fail "${target_dir} already exists, but it is not a Git repository."
  fi

  log "Cloning repository: ${repo_url}"
  git clone --depth 1 "${repo_url}" "${target_dir}"
}

build_backend() {
  local backend_dir="$1"
  local binary_name="$2"

  log "Building Go binary: ${binary_name}"
  (
    cd "${backend_dir}"
    GOWORK=off go build -o "${binary_name}" .
  )
}

write_systemd_unit() {
  local service_name="$1"
  local description="$2"
  local working_dir="$3"
  local binary_name="$4"
  local port="$5"
  local proxy_base="$6"
  local unit_file="/etc/systemd/system/${service_name}.service"

  cat >"${unit_file}" <<EOF
[Unit]
Description=${description}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RELAY_USER}
Group=${RELAY_USER}
WorkingDirectory=${working_dir}
ExecStart=${working_dir}/${binary_name} -address 127.0.0.1:${port} -reverse_proxy_base ${proxy_base}
Restart=always
RestartSec=1
KillSignal=SIGINT
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

write_systemd_units() {
  if is_yes "${INSTALL_MOBLIN}"; then
    write_systemd_unit \
      "${MOBLIN_SERVICE_NAME}" \
      "Moblin Remote Control Relay" \
      "${MOBLIN_DIR}/backend" \
      "${MOBLIN_SERVICE_NAME}" \
      "${MOBLIN_PORT}" \
      "${MOBLIN_PROXY_BASE}"
  else
    rm -f "${MOBLIN_SERVICE_FILE}"
  fi

  if is_yes "${INSTALL_OBS}"; then
    write_systemd_unit \
      "${OBS_SERVICE_NAME}" \
      "OBS Remote Control Relay" \
      "${OBS_DIR}/backend" \
      "${OBS_SERVICE_NAME}" \
      "${OBS_PORT}" \
      "${OBS_PROXY_BASE}"
  else
    rm -f "${OBS_SERVICE_FILE}"
  fi
}

configure_nginx() {
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

  cat >"${NGINX_SITE_FILE}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root /var/www/html;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

  if certificate_files_exist; then
    cat >>"${NGINX_SITE_FILE}" <<EOF

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN};
    root /var/www/html;
    index index.nginx-debian.html index.html;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
EOF

    if is_yes "${INSTALL_MOBLIN}"; then
      cat >>"${NGINX_SITE_FILE}" <<EOF

    location ${MOBLIN_ENDPOINT} {
        proxy_pass http://127.0.0.1:${MOBLIN_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
EOF
    fi

    if is_yes "${INSTALL_OBS}"; then
      cat >>"${NGINX_SITE_FILE}" <<EOF

    location ${OBS_ENDPOINT} {
        proxy_pass http://127.0.0.1:${OBS_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
EOF
    fi

    cat >>"${NGINX_SITE_FILE}" <<EOF
}
EOF
  fi

  ln -sfn "${NGINX_SITE_FILE}" "${NGINX_SITE_LINK}"

  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
}

configure_firewall() {
  cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;

        ct state established,related accept
        iif "lo" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 icmpv6 type {
            destination-unreachable,
            packet-too-big,
            time-exceeded,
            parameter-problem,
            echo-request,
            nd-router-solicit,
            nd-router-advert,
            nd-neighbor-solicit,
            nd-neighbor-advert
        } accept
        tcp dport { 22, 80, 443 } ct state new accept
    }

    chain forward {
        type filter hook forward priority 0;
        policy drop;
    }

    chain output {
        type filter hook output priority 0;
        policy accept;
    }
}
EOF

  nft -f /etc/nftables.conf
  systemctl enable --now nftables
}

request_certificate() {
  local certbot_args=(
    certbot
    certonly
    --webroot
    -w
    /var/www/html
    --non-interactive
    --agree-tos
    --cert-name "${DOMAIN}"
    -d "${DOMAIN}"
  )

  if [[ -n "${CERTBOT_EMAIL}" ]]; then
    certbot_args+=(-m "${CERTBOT_EMAIL}")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi

  log "Requesting Let's Encrypt certificate."
  "${certbot_args[@]}"

  if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    systemctl enable --now certbot.timer
  fi
}

restart_managed_services() {
  systemctl daemon-reload

  if is_yes "${INSTALL_MOBLIN}"; then
    systemctl enable "${MOBLIN_SERVICE_NAME}.service"
    if systemctl is-active --quiet "${MOBLIN_SERVICE_NAME}.service"; then
      systemctl restart "${MOBLIN_SERVICE_NAME}.service"
    else
      systemctl start "${MOBLIN_SERVICE_NAME}.service"
    fi
  else
    stop_and_disable_unit "${MOBLIN_SERVICE_NAME}.service"
  fi

  if is_yes "${INSTALL_OBS}"; then
    systemctl enable "${OBS_SERVICE_NAME}.service"
    if systemctl is-active --quiet "${OBS_SERVICE_NAME}.service"; then
      systemctl restart "${OBS_SERVICE_NAME}.service"
    else
      systemctl start "${OBS_SERVICE_NAME}.service"
    fi
  else
    stop_and_disable_unit "${OBS_SERVICE_NAME}.service"
  fi
}

show_urls() {
  if is_yes "${INSTALL_MOBLIN}"; then
    printf 'Moblin: https://%s%s\n' "${DOMAIN}" "${MOBLIN_ENDPOINT}"
  fi

  if is_yes "${INSTALL_OBS}"; then
    printf 'OBS:    https://%s%s\n' "${DOMAIN}" "${OBS_ENDPOINT}"
  fi
}

apply_runtime_configuration() {
  local request_new_certificate="$1"

  validate_distinct_endpoints
  sync_proxy_bases
  write_systemd_units
  restart_managed_services
  configure_nginx

  if [[ "${request_new_certificate}" == "yes" ]]; then
    request_certificate
    configure_nginx
  fi

  save_state
}

service_state() {
  local unit_name="$1"

  if ! systemctl list-unit-files "${unit_name}" >/dev/null 2>&1; then
    printf 'not installed'
    return
  fi

  systemctl is-active "${unit_name}" 2>/dev/null || printf 'unknown'
}

show_current_configuration() {
  load_state

  printf '\nCurrent configuration\n'
  printf 'Hostname:        %s\n' "${DOMAIN}"
  printf 'Moblin installed: %s\n' "${INSTALL_MOBLIN}"
  if is_yes "${INSTALL_MOBLIN}"; then
    printf 'Moblin endpoint:  %s\n' "${MOBLIN_ENDPOINT}"
    printf 'Moblin service:   %s\n' "$(service_state "${MOBLIN_SERVICE_NAME}.service")"
  fi
  printf 'OBS installed:    %s\n' "${INSTALL_OBS}"
  if is_yes "${INSTALL_OBS}"; then
    printf 'OBS endpoint:     %s\n' "${OBS_ENDPOINT}"
    printf 'OBS service:      %s\n' "$(service_state "${OBS_SERVICE_NAME}.service")"
  fi
  if [[ -n "${CERTBOT_EMAIL}" ]]; then
    printf 'Certbot email:   %s\n' "${CERTBOT_EMAIL}"
  else
    printf 'Certbot email:   not stored\n'
  fi
  printf '\n'
  show_urls
  printf '\n'
}

change_hostname() {
  load_state

  local domain_input
  local email_input
  local original_domain="${DOMAIN}"
  local original_email="${CERTBOT_EMAIL}"

  read -r -p "The current hostname is ${DOMAIN}. Press Enter to keep it, or enter a new hostname: " domain_input
  read -r -p "The current Let's Encrypt email is ${CERTBOT_EMAIL:-not set}. Press Enter to keep it, or enter a new email (empty keeps the current value): " email_input

  DOMAIN="${domain_input:-${DOMAIN}}"
  if [[ -n "${email_input}" ]]; then
    CERTBOT_EMAIL="${email_input}"
  fi

  if [[ "${DOMAIN}" == "${original_domain}" && "${CERTBOT_EMAIL}" == "${original_email}" ]]; then
    log "No hostname-related changes were requested."
    return
  fi

  apply_runtime_configuration "yes"
  log "Hostname configuration updated."
  show_urls
}

renew_certificate_manually() {
  log "Renewing certificates manually."
  certbot renew --non-interactive

  if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    systemctl enable --now certbot.timer
  fi

  log "Manual certificate renewal finished."
}

change_endpoint() {
  local target="$1"
  local endpoint_input
  local original_endpoint

  load_state

  case "${target}" in
    moblin)
      if ! is_yes "${INSTALL_MOBLIN}"; then
        fail "Moblin relay is not installed on this system."
      fi
      original_endpoint="${MOBLIN_ENDPOINT}"
      read -r -p "The current Moblin endpoint is ${MOBLIN_ENDPOINT}. Press Enter to keep it, or enter a new endpoint: " endpoint_input
      MOBLIN_ENDPOINT="$(normalize_endpoint "${endpoint_input:-${MOBLIN_ENDPOINT}}")"
      if [[ "${MOBLIN_ENDPOINT}" == "${original_endpoint}" ]]; then
        log "The Moblin endpoint was left unchanged."
        return
      fi
      ;;
    obs)
      if ! is_yes "${INSTALL_OBS}"; then
        fail "OBS relay is not installed on this system."
      fi
      original_endpoint="${OBS_ENDPOINT}"
      read -r -p "The current OBS endpoint is ${OBS_ENDPOINT}. Press Enter to keep it, or enter a new endpoint: " endpoint_input
      OBS_ENDPOINT="$(normalize_endpoint "${endpoint_input:-${OBS_ENDPOINT}}")"
      if [[ "${OBS_ENDPOINT}" == "${original_endpoint}" ]]; then
        log "The OBS endpoint was left unchanged."
        return
      fi
      ;;
    *)
      fail "Unknown endpoint target: ${target}"
      ;;
  esac

  validate_distinct_endpoints
  apply_runtime_configuration "no"
  log "Endpoint configuration updated."
  show_urls
}

stop_and_disable_unit() {
  local unit_name="$1"

  if systemctl list-unit-files "${unit_name}" >/dev/null 2>&1; then
    systemctl disable --now "${unit_name}" >/dev/null 2>&1 || true
  fi
}

uninstall_everything() {
  if [[ -z "${DOMAIN}" ]] && existing_installation_detected; then
    load_state || true
  fi

  confirm_uninstall

  stop_and_disable_unit "${MOBLIN_SERVICE_NAME}.service"
  stop_and_disable_unit "${OBS_SERVICE_NAME}.service"
  stop_and_disable_unit "certbot.timer"
  stop_and_disable_unit "nftables.service"

  rm -f "${MOBLIN_SERVICE_FILE}" "${OBS_SERVICE_FILE}"
  systemctl daemon-reload

  if command_exists certbot && [[ -n "${DOMAIN}" ]]; then
    certbot delete --non-interactive --cert-name "${DOMAIN}" >/dev/null 2>&1 || true
  fi

  rm -f "${NGINX_SITE_LINK}" "${NGINX_SITE_FILE}" "${STATE_FILE}"
  rm -rf "${INSTALL_ROOT}"

  if id -u "${RELAY_USER}" >/dev/null 2>&1; then
    userdel "${RELAY_USER}" >/dev/null 2>&1 || true
  fi

  if command_exists nft; then
    nft flush ruleset >/dev/null 2>&1 || true
  fi
  rm -f /etc/nftables.conf

  export DEBIAN_FRONTEND=noninteractive
  apt-get purge -y "${MANAGED_PACKAGES[@]}" >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true

  if [[ -f "${SELF_INSTALL_PATH}" ]]; then
    local remove_script_answer
    read -r -p "Do you also want to remove the installed script at ${SELF_INSTALL_PATH}? [y/N]: " remove_script_answer
    case "${remove_script_answer}" in
      y|Y|yes|YES)
        rm -f "${SELF_INSTALL_PATH}"
        log "Removed ${SELF_INSTALL_PATH}."
        ;;
      *)
        log "Keeping ${SELF_INSTALL_PATH}."
        ;;
    esac
  fi

  log "Uninstallation completed."
}

run_initial_installation() {
  confirm_destructive_warning
  confirm_prerequisites
  collect_install_configuration
  upgrade_system_once
  install_dependencies

  mkdir -p "${INSTALL_ROOT}"
  ensure_service_user

  if is_yes "${INSTALL_MOBLIN}"; then
    clone_or_update_repo "${MOBLIN_REPO_URL}" "${MOBLIN_DIR}"
    build_backend "${MOBLIN_DIR}/backend" "${MOBLIN_SERVICE_NAME}"
  fi

  if is_yes "${INSTALL_OBS}"; then
    clone_or_update_repo "${OBS_REPO_URL}" "${OBS_DIR}"
    build_backend "${OBS_DIR}/backend" "${OBS_SERVICE_NAME}"
  fi

  chown -R root:root "${INSTALL_ROOT}"
  chmod -R a+rX "${INSTALL_ROOT}"

  apply_runtime_configuration "yes"
  configure_firewall

  log "Installation completed."
  printf '\n'
  show_urls
}

management_menu() {
  local selection

  load_state

  while true; do
    clear_screen
    print_banner
    printf 'Existing installation detected for %s\n\n' "${DOMAIN}"
    cat <<'EOF'
1. View current configuration
2. Change hostname (and request a new certificate)
3. Renew the certificate manually
4. Change the Moblin endpoint
5. Change the OBS endpoint
6. Uninstall everything
0. Exit

EOF

    read -r -p "Select an option: " selection

    case "${selection}" in
      1)
        clear_screen
        show_current_configuration
        pause
        ;;
      2)
        change_hostname
        pause
        ;;
      3)
        renew_certificate_manually
        pause
        ;;
      4)
        change_endpoint "moblin"
        pause
        ;;
      5)
        change_endpoint "obs"
        pause
        ;;
      6)
        uninstall_everything
        break
        ;;
      0|"")
        break
        ;;
      *)
        warn "Invalid selection."
        pause
        ;;
    esac
  done
}

main() {
  case "${1:-}" in
    --version|-v)
      printf '%s v%s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
      return
      ;;
  esac

  clear_screen
  print_banner
  require_root "$@"
  check_os
  install_self_copy

  if existing_installation_detected; then
    management_menu
    return
  fi

  run_initial_installation
}

main "$@"
