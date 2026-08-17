#!/usr/bin/env bash
# =============================================================================
# Cerbenum Panel Installer
# Supports: Ubuntu 22.04+, Debian 12+
# Modes: interactive, non-interactive, upgrade, rollback, uninstall, dry-run
# =============================================================================
set -euo pipefail
# shellcheck disable=SC2120,SC2119  # check_root called both with and without args

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly INSTALLER_VERSION="2.0.0"
readonly PRODUCT_NAME="Cerbenum Panel"
readonly PANEL_USER="veyna-panel"
readonly PANEL_GROUP="veyna-panel"
readonly INSTALL_DIR="/opt/veyna-panel"
readonly CONFIG_DIR="/etc/veyna-panel"
readonly DATA_DIR="/opt/veyna-panel/data"
readonly LOG_DIR="/var/log/veyna-panel"
readonly BACKUP_DIR_DEFAULT="/var/backups/veyna-panel"
readonly SERVICE_NAME="veyna-panel"
readonly SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
# Public GitHub Release asset is the proven, authoritative distribution path
# (Veyna.Panel ships zero source, only compiled release artifacts) — verified
# end-to-end in CI: a fresh runner with no local bundle, downloading over the
# real network and independently re-verifying the release asset contents.
readonly GITHUB_REPO="cerbenum/Veyna.Panel"
readonly MIN_DISK_MB=2048
readonly MIN_RAM_MB=1024

# ---------------------------------------------------------------------------
# Globals (set by flags / prompts)
# ---------------------------------------------------------------------------
INSTALL_MODE=""         # systemd | docker
DOMAIN=""
PORT=8080           # internal backend bind port; nginx proxies to it on 127.0.0.1
WEB_PORT=80         # nginx/admin-UI public port; change with --web-port if 80 is taken (e.g. an existing web server)
NODE_PORT=8443      # co-located VPN node listen port; change with --node-port if 8443 is taken
CERT_TYPE=""            # lets-encrypt | lets-encrypt-ip | self-signed | none
LE_EMAIL=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
ADMIN_EMAIL=""
DB_MODE=""              # local | external
DB_URL=""
DB_HOST=""
DB_PORT=5432
DB_NAME="veyna_panel"
DB_USER="veyna"
DB_PASSWORD=""
TIMEZONE="UTC"
LANGUAGE="en"
TLS_MODE="auto"         # auto | off | manual
MFA_ENABLED="false"
BACKUP_DIR="${BACKUP_DIR_DEFAULT}"
UPDATE_CHANNEL="stable"
ADMIN_URL_PATH=""
SECRET_KEY=""
REINSTALL="false"
declare -A CLI_SET=()
NON_INTERACTIVE=false
FORCE=false
SKIP_CONFIRM=false
ROLLBACK_VERSION=""
DRY_RUN=false
BUNDLE_PATH=""
ADVANCED=false
SCRIPT_DIR=""

# ---------------------------------------------------------------------------
# Colors & output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fatal()   { error "$*"; exit 1; }
# shellcheck disable=SC2015  # intentional: debug always succeeds
debug()   { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" || true; }
header()  { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}\n"; }

print_banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'BANNER'

   ██████╗███████╗██████╗ ██████╗ ███████╗███╗   ██╗██╗   ██╗███╗   ███╗
  ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝████╗  ██║██║   ██║████╗ ████║
  ██║     █████╗  ██████╔╝██████╔╝█████╗  ██╔██╗ ██║██║   ██║██╔████╔██║
  ██║     ██╔══╝  ██╔══██╗██╔══██╗██╔══╝  ██║╚██╗██║██║   ██║██║╚██╔╝██║
  ╚██████╗███████╗██████╔╝██║  ██║███████╗██║ ╚████║╚██████╔╝██║ ╚═╝ ██║
   ╚═════╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝

BANNER
    echo -e "  ${DIM}${PRODUCT_NAME} Installer v${INSTALLER_VERSION}${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------
TEMP_DIR=""
cleanup() {
    local exit_code=$?
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        error "Installation failed. Check logs above for details."
        if [[ -f "${CONFIG_DIR}/.install-backup-marker" ]]; then
            warn "A backup exists. Run with --rollback to restore previous state."
        fi
    fi
    exit "${exit_code}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------
generate_secret() {
    openssl rand -hex 32
}

generate_admin_path() {
    openssl rand -hex 16
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root. Use: sudo bash $0 $*"
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        fatal "Cannot detect OS. This installer supports Ubuntu 22.04+ and Debian 12+."
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID}" in
        ubuntu)
            local major
            major=$(echo "${VERSION_ID}" | cut -d. -f1)
            if [[ ${major} -lt 22 ]]; then
                fatal "Ubuntu ${VERSION_ID} is not supported. Requires 22.04+."
            fi
            ;;
        debian)
            local major
            major=$(echo "${VERSION_ID}" | cut -d. -f1)
            if [[ ${major} -lt 12 ]]; then
                fatal "Debian ${VERSION_ID} is not supported. Requires 12+."
            fi
            ;;
        *)
            fatal "Unsupported OS: ${ID}. This installer supports Ubuntu and Debian."
            ;;
    esac
    info "Detected OS: ${PRETTY_NAME}"
}

check_resources() {
    local ram_mb
    ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [[ ${ram_mb} -lt ${MIN_RAM_MB} ]]; then
        warn "System has ${ram_mb}MB RAM. Minimum recommended: ${MIN_RAM_MB}MB."
    fi
    local disk_mb
    disk_mb=$(df -m "${INSTALL_DIR%/*}" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    if [[ ${disk_mb} -lt ${MIN_DISK_MB} ]]; then
        warn "Less than ${MIN_DISK_MB}MB free disk space. Installation may fail."
    fi
}

# ---------------------------------------------------------------------------
# Port handling
# ---------------------------------------------------------------------------
# True when nothing is listening on the port, or when the only listener is this
# installation itself. Without the second case a reinstall always collides with
# its own running service and either aborts (--non-interactive) or pushes the
# operator onto a different port, changing the URL.
is_port_free_for_reinstall() {
    local port="$1"
    is_port_free "${port}" && return 0
    [[ "${REINSTALL}" == "true" ]] || return 1
    systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null || return 1
    return 0
}

is_port_free() {
    local port="$1"
    if ss -tln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
        return 1
    fi
    if command -v netstat &>/dev/null && netstat -tln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
        return 1
    fi
    return 0
}

find_free_port() {
    # Try the default backend port first
    if is_port_free 8080; then
        echo 8080
        return
    fi
    # Try random ports in 20000-60000
    local attempts=0
    while [[ ${attempts} -lt 100 ]]; do
        local candidate=$((RANDOM % 40001 + 20000))
        if is_port_free "${candidate}"; then
            echo "${candidate}"
            return
        fi
        attempts=$((attempts + 1))
    done
    # Last resort: try sequentially
    local port
    for port in $(seq 20000 20100); do
        if is_port_free "${port}"; then
            echo "${port}"
            return
        fi
    done
    fatal "Cannot find a free port. Specify one with --port."
}

resolve_port() {
    if [[ -z "${PORT}" || "${PORT}" == "auto" ]]; then
        PORT=$(find_free_port)
        info "Auto-selected port: ${PORT}"
    else
        if ! is_port_free_for_reinstall "${PORT}"; then
            if [[ "${NON_INTERACTIVE}" == "true" ]]; then
                fatal "Port ${PORT} is already in use."
            else
                warn "Port ${PORT} is already in use."
                local new_port
                new_port=$(find_free_port)
                read -rp "$(echo -e "${CYAN}Enter a different port [${new_port}]:${NC} ")" PORT
                PORT="${PORT:-${new_port}}"
                if ! is_port_free "${PORT}"; then
                    fatal "Port ${PORT} is still in use."
                fi
            fi
        fi
    fi
    info "Panel backend will bind internally on port: ${PORT}"

    if ! is_port_free_for_reinstall "${NODE_PORT}"; then
        warn "Port ${NODE_PORT} is already in use — the co-located VPN node will not be able to bind to it. Re-run with --node-port to pick a free one."
    fi
}

# ---------------------------------------------------------------------------
# SSL / TLS
# ---------------------------------------------------------------------------
get_public_ip() {
    curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -sf --max-time 5 https://ifconfig.me 2>/dev/null || \
    curl -sf --max-time 5 https://icanhazip.com 2>/dev/null || \
    echo ""
}

resolve_domain_ip() {
    local domain="$1"
    getent hosts "${domain}" 2>/dev/null | awk '{print $1}' | head -1
}

setup_ssl() {
    header "TLS / SSL Configuration"

    local public_ip
    public_ip=$(get_public_ip)

    if [[ -n "${DOMAIN}" ]]; then
        info "Domain: ${DOMAIN}"
        # Check if domain resolves to this server
        local domain_ip
        domain_ip=$(resolve_domain_ip "${DOMAIN}")
        if [[ -n "${domain_ip}" && -n "${public_ip}" && "${domain_ip}" != "${public_ip}" ]]; then
            warn "Domain ${DOMAIN} resolves to ${domain_ip}, but this server's public IP is ${public_ip}."
            if [[ "${NON_INTERACTIVE}" != "true" ]]; then
                if ! confirm "Continue anyway?"; then
                    fatal "Aborting. Fix DNS and retry."
                fi
            else
                warn "Proceeding anyway (non-interactive mode)."
            fi
        fi

        # Try Let's Encrypt
        info "Obtaining Let's Encrypt certificate for ${DOMAIN}..."
        ensure_certbot

        # Check if nginx is already running on port 80
        local standalone_flag="--standalone"
        if ss -tln 2>/dev/null | grep -qE "[:.]80[[:space:]]"; then
            info "Port 80 in use, trying webroot method..."
            mkdir -p /var/www/html/.well-known/acme-challenge
            standalone_flag="--webroot -w /var/www/html"
        fi

        # shellcheck disable=SC2086
        if certbot certonly ${standalone_flag} \
            -d "${DOMAIN}" \
            --non-interactive \
            --agree-tos \
            --email "${LE_EMAIL}" \
            --preferred-challenges http 2>&1; then
            CERT_TYPE="lets-encrypt"
            info "Let's Encrypt certificate obtained for ${DOMAIN}"
        else
            warn "Let's Encrypt failed for domain. Falling back to self-signed."
            generate_self_signed "${DOMAIN}"
            CERT_TYPE="self-signed"
        fi

        # Setup auto-renewal
        setup_certbot_renewal
    else
        # No domain — try LE for IP, then self-signed
        if [[ -z "${public_ip}" ]]; then
            warn "Cannot determine public IP. Generating self-signed certificate."
            generate_self_signed ""
            CERT_TYPE="self-signed"
        else
            info "No domain. Attempting Let's Encrypt for IP: ${public_ip}..."
            ensure_certbot

            # LE short-lived profile supports IP SANs (certbot >= 2.0)
            if certbot certonly --standalone \
                -d "${public_ip}" \
                --non-interactive \
                --agree-tos \
                --email "${LE_EMAIL:-noreply@cerbenum.local}" \
                --preferred-challenges http \
                --preferred-profile shortlived 2>&1; then
                CERT_TYPE="lets-encrypt-ip"
                info "Let's Encrypt IP certificate obtained."
                setup_certbot_renewal
            else
                warn "Let's Encrypt for IP failed. Generating self-signed certificate."
                generate_self_signed "${public_ip}"
                CERT_TYPE="self-signed"
            fi
        fi
    fi

    # TLS off override
    if [[ "${TLS_MODE}" == "off" ]]; then
        warn "TLS explicitly disabled (--tls off). Panel will run over plain HTTP."
        warn "This is NOT recommended for production."
        CERT_TYPE="none"
    fi
}

ensure_certbot() {
    if command -v certbot &>/dev/null; then
        return
    fi
    info "Installing certbot..."
    apt-get install -y -qq certbot 2>/dev/null || {
        # Try pip if apt version is too old
        if command -v pip3 &>/dev/null; then
            pip3 install certbot 2>/dev/null || true
        fi
    }
    if ! command -v certbot &>/dev/null; then
        fatal "Failed to install certbot. Install manually: apt install certbot"
    fi
}

generate_self_signed() {
    local cn="${1:-localhost}"
    local tls_dir="${CONFIG_DIR}/tls"
    mkdir -p "${tls_dir}"

    local san_entries="DNS:localhost,IP:127.0.0.1"
    if [[ -n "${cn}" && "${cn}" != "localhost" ]]; then
        # Check if it's an IP
        if [[ "${cn}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            san_entries="${san_entries},IP:${cn}"
        else
            san_entries="${san_entries},DNS:${cn}"
        fi
    fi

    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "${tls_dir}/privkey.pem" \
        -out "${tls_dir}/fullchain.pem" \
        -subj "/CN=${cn}" \
        -addext "subjectAltName=${san_entries}" \
        2>/dev/null

    chmod 600 "${tls_dir}/privkey.pem"
    info "Self-signed certificate generated (valid 10 years)."
    warn "Browsers will show a security warning for self-signed certificates."
}

setup_certbot_renewal() {
    # Create a deploy hook to reload nginx
    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    mkdir -p "${hook_dir}"
    cat > "${hook_dir}/reload-nginx.sh" <<'HOOK'
#!/bin/bash
systemctl reload nginx 2>/dev/null || true
HOOK
    chmod +x "${hook_dir}/reload-nginx.sh"

    # Enable systemd timer if available
    if systemctl list-unit-files certbot.timer &>/dev/null 2>&1; then
        systemctl enable --now certbot.timer 2>/dev/null || true
        info "Certbot auto-renewal timer enabled."
    fi
}

# ---------------------------------------------------------------------------
# Nginx
# ---------------------------------------------------------------------------
install_nginx() {
    if ! command -v nginx &>/dev/null; then
        info "Installing nginx..."
        apt-get install -y -qq nginx
    fi
    systemctl enable nginx
}

open_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        info "Configuring firewall (ufw)..."
        # WEB_PORT is the nginx-facing admin UI; NODE_PORT is the co-located
        # VPN node (bound 0.0.0.0, needs to be reachable by clients directly).
        # PORT is intentionally NOT opened — it's only meant to be reached via
        # nginx on 127.0.0.1, gated behind the secret admin path.
        ufw allow "${WEB_PORT}/tcp" comment "Cerbenum Panel Admin UI" 2>/dev/null || true
        ufw allow "${NODE_PORT}/tcp" comment "Cerbenum Panel Co-located Node" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------
prompt() {
    local varname="$1"
    local prompt_text="$2"
    local default="${3:-}"
    local value

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        if [[ -z "${!varname:-}" && -n "${default}" ]]; then
            declare -g "${varname}=${default}"
        fi
        return
    fi

    if [[ -n "${default}" ]]; then
        read -rp "$(echo -e "${CYAN}${prompt_text} [${default}]:${NC} ")" value
        value="${value:-${default}}"
    else
        read -rp "$(echo -e "${CYAN}${prompt_text}:${NC} ")" value
    fi
    declare -g "${varname}=${value}"
}

prompt_password() {
    local varname="$1"
    local prompt_text="$2"
    local value confirm

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        [[ -n "${!varname:-}" ]] && return
        fatal "Password for ${varname} must be provided in non-interactive mode."
    fi

    while true; do
        read -rsp "$(echo -e "${CYAN}${prompt_text}:${NC} ")" value
        echo ""
        if [[ ${#value} -lt 12 ]]; then
            error "Password must be at least 12 characters."
            continue
        fi
        read -rsp "$(echo -e "${CYAN}Confirm password:${NC} ")" confirm
        echo ""
        if [[ "${value}" == "${confirm}" ]]; then
            declare -g "${varname}=${value}"
            break
        else
            error "Passwords do not match. Try again."
        fi
    done
}

prompt_choice() {
    local varname="$1"
    local prompt_text="$2"
    shift 2
    local options=("$@")
    local choice

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        [[ -n "${!varname:-}" ]] && return
        fatal "Choice for ${varname} must be provided in non-interactive mode."
    fi

    echo -e "${CYAN}${prompt_text}:${NC}"
    select choice in "${options[@]}"; do
        if [[ -n "${choice}" ]]; then
            declare -g "${varname}=${choice}"
            break
        else
            error "Invalid selection. Try again."
        fi
    done
}

confirm() {
    local prompt_text="${1:-Continue?}"
    if [[ "${SKIP_CONFIRM}" == "true" ]]; then
        return 0
    fi
    read -rp "$(echo -e "${YELLOW}${prompt_text} [y/N]:${NC} ")" response
    [[ "${response}" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Reinstall / upgrade detection
# ---------------------------------------------------------------------------
detect_existing() {
    if [[ -f "${CONFIG_DIR}/config.env" ]]; then
        info "Existing installation detected."
        # shellcheck source=/dev/null
        source "${CONFIG_DIR}/config.env" 2>/dev/null || true
        restore_existing_config
        return 0
    fi
    return 1
}

# Maps a previous install's config.env back onto the variables this script
# actually reads.
#
# config.env writes every value under a `PANEL_`/`VEYNA_PANEL_` name because
# that is what the binary and veyna-panelctl consume, but the installer's own
# logic uses the bare names. Sourcing the file therefore restored nothing, and
# write_config's `[[ -z "${VAR}" ]] && VAR=$(generate...)` guards saw empty
# variables on every re-run — so reinstalling minted a new admin path (the
# panel URL changed), a new encryption key, and a new database password, none
# of which the operator asked for.
#
# Each assignment is guarded on the target being empty, so an explicit flag
# (parse_args runs first) still wins over the persisted value.
# True when the operator did not pass the given flag on the command line.
cli_unset() {
    [[ -z "${CLI_SET[$1]:-}" ]]
}

restore_existing_config() {
    local prior_node_port prior_host_port

    # Identity: changing either of these breaks a working install outright.
    [[ -z "${ADMIN_URL_PATH}" && -n "${PANEL_ADMIN_URL_PATH:-}" ]] &&
        ADMIN_URL_PATH="${PANEL_ADMIN_URL_PATH}"
    [[ -z "${SECRET_KEY}" && -n "${VEYNA_PANEL_ENCRYPTION_KEY:-}" ]] &&
        SECRET_KEY="${VEYNA_PANEL_ENCRYPTION_KEY}"

    # Carries the generated database password; regenerating it orphans the
    # existing PostgreSQL role.
    [[ -z "${DB_URL}" && -n "${VEYNA_PANEL_DATABASE_URL:-}" ]] &&
        DB_URL="${VEYNA_PANEL_DATABASE_URL}"
    [[ -n "${DB_URL}" && -z "${DB_MODE}" ]] && DB_MODE="local"

    # Addressing: these decide the URL the operator has already shared.
    [[ -z "${PORT}" && -n "${PANEL_PORT:-}" ]] && PORT="${PANEL_PORT}"
    prior_node_port="${VEYNA_PANEL_CORE_ADAPTER_URL##*:}"
    [[ -n "${prior_node_port}" && "${prior_node_port}" =~ ^[0-9]+$ ]] &&
        NODE_PORT="${prior_node_port}"
    if [[ -n "${PANEL_BASE_URL:-}" ]]; then
        local hostport="${PANEL_BASE_URL#*://}"
        hostport="${hostport%%/*}"
        prior_host_port="${hostport##*:}"
        if [[ "${prior_host_port}" != "${hostport}" && "${prior_host_port}" =~ ^[0-9]+$ ]]; then
            WEB_PORT="${prior_host_port}"
        else
            WEB_PORT="80"
        fi
        [[ -z "${DOMAIN}" ]] && DOMAIN="${hostport%%:*}"
    fi

    # Preferences the operator set once and should not have to re-answer.
    # These have non-empty defaults, so the guard is "was a flag passed?"
    # rather than "is it empty?". TLS_MODE in particular decides http vs https
    # in the advertised URL, so losing it changes the link too.
    cli_unset --tls && [[ -n "${PANEL_TLS_MODE:-}" ]] && TLS_MODE="${PANEL_TLS_MODE}"
    cli_unset --mfa && [[ -n "${PANEL_MFA_ENABLED:-}" ]] && MFA_ENABLED="${PANEL_MFA_ENABLED}"
    cli_unset --backup-dir && [[ -n "${PANEL_BACKUP_DIR:-}" ]] && BACKUP_DIR="${PANEL_BACKUP_DIR}"
    cli_unset --channel && [[ -n "${PANEL_UPDATE_CHANNEL:-}" ]] && UPDATE_CHANNEL="${PANEL_UPDATE_CHANNEL}"
    cli_unset --language && [[ -n "${VEYNA_PANEL_DEFAULT_LANGUAGE:-}" ]] &&
        LANGUAGE="${VEYNA_PANEL_DEFAULT_LANGUAGE}"
    cli_unset --timezone && [[ -n "${TZ:-}" ]] && TIMEZONE="${TZ}"

    REINSTALL="true"
    if [[ -n "${ADMIN_URL_PATH}" ]]; then
        info "Preserving existing admin URL path and encryption key."
    fi
    return 0
}

detect_mode() {
    if [[ -f "${SYSTEMD_UNIT}" ]]; then
        INSTALL_MODE="systemd"
    elif [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] || \
         (command -v docker &>/dev/null && docker compose -f "${INSTALL_DIR}/docker-compose.yml" ps &>/dev/null 2>&1); then
        INSTALL_MODE="docker"
    fi
}

# ---------------------------------------------------------------------------
# Package installation
# ---------------------------------------------------------------------------
install_packages() {
    header "Installing system packages"
    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        gnupg \
        ca-certificates \
        lsb-release \
        openssl \
        jq \
        tar \
        gzip \
        coreutils \
        procps \
        net-tools \
        postgresql-client \
        nginx \
        2>/dev/null

    if [[ "${INSTALL_MODE}" == "systemd" ]]; then
        info "Installing PostgreSQL..."
        apt-get install -y -qq postgresql postgresql-contrib
    fi

    if [[ "${INSTALL_MODE}" == "docker" ]]; then
        if ! command -v docker &>/dev/null; then
            info "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker
            systemctl start docker
        fi
        if ! docker compose version &>/dev/null 2>&1; then
            info "Installing Docker Compose plugin..."
            apt-get install -y -qq docker-compose-plugin
        fi
    fi
}

# ---------------------------------------------------------------------------
# PostgreSQL setup
# ---------------------------------------------------------------------------
setup_postgresql_local() {
    header "Setting up PostgreSQL"

    systemctl enable postgresql
    systemctl start postgresql

    if [[ -z "${DB_PASSWORD}" ]]; then
        DB_PASSWORD=$(generate_secret)
    fi

    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

    DB_URL="postgres://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"
    info "PostgreSQL configured: ${DB_NAME}"
}

setup_postgresql_external() {
    header "Connecting to external PostgreSQL"
    if [[ -z "${DB_URL}" ]]; then
        prompt DB_HOST "Database host" "localhost"
        prompt DB_PORT "Database port" "5432"
        prompt DB_NAME "Database name" "veyna_panel"
        prompt DB_USER "Database user" "veyna"
        prompt_password DB_PASSWORD "Database password"
        DB_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi

    info "Testing database connection..."
    if ! PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" &>/dev/null; then
        fatal "Cannot connect to database. Check connection details."
    fi
    info "Database connection successful."
}

# ---------------------------------------------------------------------------
# System user
# ---------------------------------------------------------------------------
create_system_user() {
    header "Creating system user"
    if id "${PANEL_USER}" &>/dev/null; then
        info "User '${PANEL_USER}' already exists."
    else
        useradd --system --shell /usr/sbin/nologin --home-dir "${INSTALL_DIR}" \
            --create-home --comment "${PRODUCT_NAME} Service" "${PANEL_USER}"
        info "Created system user '${PANEL_USER}'."
    fi
}

# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------
create_directories() {
    header "Creating directory structure"
    local dirs=(
        "${INSTALL_DIR}"
        "${INSTALL_DIR}/bin"
        "${INSTALL_DIR}/data"
        "${INSTALL_DIR}/migrations"
        "${INSTALL_DIR}/docs"
        "${CONFIG_DIR}"
        "${LOG_DIR}"
        "${BACKUP_DIR}"
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done

    chown -R "${PANEL_USER}:${PANEL_GROUP}" "${INSTALL_DIR}"
    chown -R "${PANEL_USER}:${PANEL_GROUP}" "${LOG_DIR}"
    chown -R "${PANEL_USER}:${PANEL_GROUP}" "${BACKUP_DIR}"
    chmod 750 "${INSTALL_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${BACKUP_DIR}"
}

# ---------------------------------------------------------------------------
# Download & install binaries
#
# Primary path is the public GitHub Release asset (Veyna.Panel ships zero
# source, only compiled artifacts built by .github/workflows/release.yml from
# the private Veyna.Core + this repo) — proven end-to-end in CI: a fresh
# runner with no local bundle, downloading over the real network and
# independently re-verifying the release asset contents.
#
# --bundle and an extracted-bundle-next-to-this-script are supported as
# offline/air-gapped fallbacks; both stage the same file layout into
# TEMP_DIR that the primary path produces:
#   veyna-panel, veyna-server, veyna-panelctl, migrations/, frontend-dist/
# veyna-server is the co-located default VPN node (see colocated_node.rs) —
# it must land next to veyna-panel in the same bin dir, since that's where
# the panel looks for it at startup.
# ---------------------------------------------------------------------------
detect_bundle_dir() {
    # If we're running from inside an extracted bundle, set SCRIPT_DIR
    if [[ -z "${SCRIPT_DIR}" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    # Check if bundle files exist next to the installer
    if [[ -f "${SCRIPT_DIR}/veyna-panel" && -d "${SCRIPT_DIR}/migrations" ]]; then
        return 0
    fi
    return 1
}

download_panel() {
    header "Downloading ${PRODUCT_NAME}"

    # Case 1: --bundle flag — explicit local tarball (offline/air-gapped installs)
    if [[ -n "${BUNDLE_PATH}" ]]; then
        if [[ ! -f "${BUNDLE_PATH}" ]]; then
            fatal "Bundle file not found: ${BUNDLE_PATH}"
        fi
        TEMP_DIR=$(mktemp -d)
        info "Extracting bundle: ${BUNDLE_PATH}"
        tar xzf "${BUNDLE_PATH}" -C "${TEMP_DIR}"
        # Bundle may extract into a nested directory — flatten if so.
        local nested
        nested=$(find "${TEMP_DIR}" -mindepth 1 -maxdepth 1 -type d -name "*veyna-panel*" -print -quit 2>/dev/null || true)
        [[ -n "${nested}" ]] && TEMP_DIR="${nested}"
        if [[ ! -f "${TEMP_DIR}/veyna-panel" ]]; then
            fatal "Bundle does not contain veyna-panel binary."
        fi

    # Case 2: running from an extracted bundle directory (e.g.
    # `tar xzf cerbenum-panel-linux-x86_64.tar.gz && sudo bash cerbenum-panel/install.sh`)
    elif detect_bundle_dir; then
        info "Detected local bundle in ${SCRIPT_DIR}"
        TEMP_DIR="${SCRIPT_DIR}"

    # Case 3 (default/primary): public GitHub Release asset.
    else
        TEMP_DIR=$(mktemp -d)

        local arch
        arch=$(uname -m)
        case "${arch}" in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *)       fatal "Unsupported architecture: ${arch}" ;;
        esac

        local os="linux"
        local version
        version=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | jq -r '.tag_name' || echo "latest")

        local url
        if [[ "${version}" == "latest" || "${version}" == "null" || -z "${version}" ]]; then
            version="latest"
            url="https://github.com/${GITHUB_REPO}/releases/latest/download/veyna-panel-${os}-${arch}.tar.gz"
        else
            url="https://github.com/${GITHUB_REPO}/releases/download/${version}/veyna-panel-${os}-${arch}.tar.gz"
        fi

        info "Downloading version: ${version}"
        if ! curl -fsSL -o "${TEMP_DIR}/veyna-panel.tar.gz" "${url}"; then
            # Fallback: use local binaries staged next to this script (used by
            # our own from-source / CI test runs; not the public download path).
            if [[ -f "./veyna-panel" ]]; then
                info "Using local binaries."
                TEMP_DIR="."
            else
                fatal "Download failed. Check network connection and URL: ${url}
Options:
  1. Use --bundle /path/to/cerbenum-panel-linux-x86_64.tar.gz for an offline install
  2. Extract a release bundle and run install.sh from inside it:
     tar xzf cerbenum-panel-linux-x86_64.tar.gz && sudo bash cerbenum-panel/install.sh"
            fi
        else
            tar -xzf "${TEMP_DIR}/veyna-panel.tar.gz" -C "${TEMP_DIR}"
        fi
    fi

    cp "${TEMP_DIR}/veyna-panel" "${INSTALL_DIR}/bin/veyna-panel"
    chmod 755 "${INSTALL_DIR}/bin/veyna-panel"
    info "Binary installed to ${INSTALL_DIR}/bin/veyna-panel"

    if [[ -f "${TEMP_DIR}/veyna-server" ]]; then
        cp "${TEMP_DIR}/veyna-server" "${INSTALL_DIR}/bin/veyna-server"
        chmod 755 "${INSTALL_DIR}/bin/veyna-server"
        info "Co-located node binary installed to ${INSTALL_DIR}/bin/veyna-server"
    else
        warn "veyna-server not found in release archive — panel will start without a default node."
    fi
}

# ---------------------------------------------------------------------------
# Install veyna-panelctl management CLI
# ---------------------------------------------------------------------------
install_panelctl() {
    header "Installing veyna-panelctl"
    if [[ -f "${TEMP_DIR}/veyna-panelctl" ]]; then
        cp "${TEMP_DIR}/veyna-panelctl" /usr/local/bin/veyna-panelctl
        chmod 755 /usr/local/bin/veyna-panelctl
        info "veyna-panelctl installed to /usr/local/bin/veyna-panelctl"
    else
        warn "veyna-panelctl not found in release archive — skipping."
    fi
}

# ---------------------------------------------------------------------------
# Frontend: stage the built React app and put nginx in front of it + the API
# ---------------------------------------------------------------------------
install_frontend() {
    header "Installing frontend + nginx reverse proxy"

    if [[ ! -d "${TEMP_DIR}/frontend-dist" ]]; then
        warn "frontend-dist not found in release archive — admin UI will not be served."
        return
    fi

    local www_dir="${INSTALL_DIR}/www"
    mkdir -p "${www_dir}"
    cp -r "${TEMP_DIR}/frontend-dist/." "${www_dir}/"
    chown -R "${PANEL_USER}:${PANEL_GROUP}" "${www_dir}"
    # INSTALL_DIR is 750 (create_directories) so only PANEL_USER can read
    # DATA_DIR/etc — but nginx (www-data) still needs to *traverse* into it
    # to reach www/. Grant execute-only to others: lets nginx reach a known
    # subpath without being able to list or read anything else inside.
    chmod o+x "${INSTALL_DIR}"

    if ss -tln 2>/dev/null | grep -q ":${WEB_PORT} "; then
        warn "Port ${WEB_PORT} is already in use (another web server?) — the admin UI may not be reachable on it."
    fi

    local listen_block ssl_block=""
    if [[ -n "${CERT_TYPE}" && "${CERT_TYPE}" != "none" ]]; then
        local tls_cert tls_key
        if [[ "${CERT_TYPE}" == "lets-encrypt" || "${CERT_TYPE}" == "lets-encrypt-ip" ]]; then
            tls_cert="/etc/letsencrypt/live/${DOMAIN:-$(get_public_ip)}/fullchain.pem"
            tls_key="/etc/letsencrypt/live/${DOMAIN:-$(get_public_ip)}/privkey.pem"
        else
            tls_cert="${CONFIG_DIR}/tls/fullchain.pem"
            tls_key="${CONFIG_DIR}/tls/privkey.pem"
        fi
        listen_block="listen ${WEB_PORT} ssl http2;
    listen [::]:${WEB_PORT} ssl http2;"
        ssl_block="
    ssl_certificate ${tls_cert};
    ssl_certificate_key ${tls_key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;"
    else
        listen_block="listen ${WEB_PORT};
    listen [::]:${WEB_PORT};"
    fi

    cat > "/etc/nginx/sites-available/veyna-panel" <<EOF
upstream veyna_panel_backend {
    server 127.0.0.1:${PORT};
    keepalive 32;
}

server {
    ${listen_block}
    server_name ${DOMAIN:-_};
${ssl_block}

    client_max_body_size 50m;

    # Nothing meaningful responds at the bare root or any unrecognized
    # path — an anonymous port scan / directory guess finds no login page,
    # only whoever has the secret admin path below can reach the panel.
    location = / {
        return 404;
    }

    location = /${ADMIN_URL_PATH} {
        return 301 /${ADMIN_URL_PATH}/;
    }

    # Exact match wins over the prefix proxy block further down: a GET on
    # the secret path itself serves the SPA shell; requests nested under
    # it (the SPA's own API calls, e.g. .../auth/login) fall through to
    # the backend proxy instead.
    location = /${ADMIN_URL_PATH}/ {
        root ${www_dir};
        try_files /index.html =404;
    }

    location ~ ^/(assets/|vite\.svg) {
        root ${www_dir};
    }

    location /api/ {
        proxy_pass http://veyna_panel_backend/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }

    location /${ADMIN_URL_PATH}/ {
        proxy_pass http://veyna_panel_backend/${ADMIN_URL_PATH}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }

    location /healthz {
        proxy_pass http://veyna_panel_backend/healthz;
        access_log off;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/veyna-panel /etc/nginx/sites-enabled/veyna-panel
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx || systemctl restart nginx
    info "nginx configured — frontend served on port ${WEB_PORT}, API/admin proxied to 127.0.0.1:${PORT}"
}

# ---------------------------------------------------------------------------
# Copy migrations
# ---------------------------------------------------------------------------
install_migrations() {
    if [[ -d "${TEMP_DIR}/migrations" ]]; then
        cp -r "${TEMP_DIR}/migrations/"* "${INSTALL_DIR}/migrations/"
        info "Migrations installed."
    elif [[ -d "./migrations" ]]; then
        cp -r ./migrations/* "${INSTALL_DIR}/migrations/"
        info "Migrations installed."
    fi
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
write_config() {
    header "Writing configuration"

    [[ -z "${SECRET_KEY}" ]] && SECRET_KEY=$(generate_secret)
    [[ -z "${ADMIN_URL_PATH}" ]] && ADMIN_URL_PATH=$(generate_admin_path)

    # The binary (panel/backend/src/config/mod.rs, `PanelConfig::load`) reads
    # ONLY `VEYNA_PANEL_*`-prefixed env vars (via figment) — it never reads a
    # `config.env`/`PANEL_*` file directly, so those are the vars that matter
    # for `EnvironmentFile=` in the systemd unit. The unprefixed `PANEL_*`
    # vars below are kept for `veyna-panelctl`'s own bookkeeping (status,
    # health-check port, backup dir) — the binary ignores them.
    local scheme="https"
    [[ -z "${CERT_TYPE}" || "${CERT_TYPE}" == "none" ]] && scheme="http"
    local base_host="${DOMAIN}"
    if [[ -z "${base_host}" ]]; then
        base_host=$(get_public_ip)
        [[ -z "${base_host}" ]] && fatal "Cannot determine a public host. Specify one with --domain."
    fi
    local web_suffix=""
    [[ "${WEB_PORT}" != "80" ]] && web_suffix=":${WEB_PORT}"
    local base_url="${scheme}://${base_host}${web_suffix}"

    cat > "${CONFIG_DIR}/config.env" <<EOF
# ${PRODUCT_NAME} Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Mode: ${INSTALL_MODE}

# --- Read by the veyna-panel binary (figment, VEYNA_PANEL_ prefix) ---
VEYNA_PANEL_DATABASE_URL=${DB_URL}
VEYNA_PANEL_BIND_ADDRESS=0.0.0.0:${PORT}
VEYNA_PANEL_ADMIN_BASE_PATH=/${ADMIN_URL_PATH}
VEYNA_PANEL_LOG_LEVEL=info
VEYNA_PANEL_LOG_DIR=${LOG_DIR}
VEYNA_PANEL_BACKUP_DIR=${BACKUP_DIR}
VEYNA_PANEL_DEFAULT_LANGUAGE=${LANGUAGE}
VEYNA_PANEL_ENCRYPTION_KEY=${SECRET_KEY}
VEYNA_PANEL_ENABLE_COLOCATED_NODE=true
VEYNA_PANEL_CORE_ADAPTER_URL=0.0.0.0:${NODE_PORT}
VEYNA_PANEL_NODE_PUBLIC_HOST=${base_host}
VEYNA_PANEL_COOKIE_SECURE=$([[ "${TLS_MODE}" == "off" ]] && echo false || echo true)

# --- Read only by veyna-panelctl (not the binary) ---
PANEL_PORT=${PORT}
PANEL_ADMIN_URL_PATH=${ADMIN_URL_PATH}
PANEL_BASE_URL=${base_url}
PANEL_MFA_ENABLED=${MFA_ENABLED}
PANEL_TLS_MODE=${TLS_MODE}
PANEL_BACKUP_DIR=${BACKUP_DIR}
PANEL_BACKUP_RETENTION_DAYS=30
PANEL_UPDATE_CHANNEL=${UPDATE_CHANNEL}
TZ=${TIMEZONE}
EOF

    chmod 600 "${CONFIG_DIR}/config.env"
    chown "${PANEL_USER}:${PANEL_GROUP}" "${CONFIG_DIR}/config.env"
    info "Configuration written to ${CONFIG_DIR}/config.env"
}

# ---------------------------------------------------------------------------
# Admin bootstrap
# ---------------------------------------------------------------------------
bootstrap_admin() {
    header "Bootstrapping admin user"
    [[ -z "${ADMIN_USERNAME}" ]] && ADMIN_USERNAME="admin"
    [[ -z "${ADMIN_PASSWORD}" ]] && prompt_password ADMIN_PASSWORD "Set admin password"
    [[ -z "${ADMIN_EMAIL}" ]] && prompt ADMIN_EMAIL "Admin email" "admin@$(hostname -f 2>/dev/null || echo localhost)"

    # Plaintext, deliberately: the panel binary hashes this itself with the
    # exact Argon2id build it later verifies against, so the two can never
    # disagree on format. A shell-generated hash can't make that guarantee
    # (there is no `argon2` CLI package installed by this script, so it
    # silently fell back to a PBKDF2 blob the Rust side could never parse —
    # every bootstrap admin created this way was permanently unable to log
    # in). File is 600, owned by the panel user, and the panel deletes it
    # immediately after consuming it on first start.
    jq -n \
        --arg username "${ADMIN_USERNAME}" \
        --arg password "${ADMIN_PASSWORD}" \
        --arg email "${ADMIN_EMAIL}" \
        --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{username: $username, password: $password, email: $email, created_at: $created_at}' \
        > "${CONFIG_DIR}/bootstrap.json"

    chmod 600 "${CONFIG_DIR}/bootstrap.json"
    chown "${PANEL_USER}:${PANEL_GROUP}" "${CONFIG_DIR}/bootstrap.json"
    info "Admin user '${ADMIN_USERNAME}' configured."
}

# ---------------------------------------------------------------------------
# systemd service
# ---------------------------------------------------------------------------
install_systemd_service() {
    header "Installing systemd service"

    cat > "${SYSTEMD_UNIT}" <<UNIT
[Unit]
Description=${PRODUCT_NAME} Backend Service
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target postgresql.service
Wants=network-online.target
ConditionPathExists=${INSTALL_DIR}/bin/veyna-panel
ConditionPathExists=${CONFIG_DIR}/config.env
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=${PANEL_USER}
Group=${PANEL_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/veyna-panel
ExecReload=/bin/kill -HUP \$MAINPID
EnvironmentFile=-${CONFIG_DIR}/config.env

Restart=on-failure
RestartSec=5

TimeoutStartSec=30
TimeoutStopSec=30

NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
SystemCallArchitectures=native
ReadWritePaths=${INSTALL_DIR}/data ${LOG_DIR} ${BACKUP_DIR}

StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    info "systemd service installed and enabled."
}

# ---------------------------------------------------------------------------
# Run migrations
# ---------------------------------------------------------------------------
run_migrations() {
    header "Running database migrations"
    sudo -u "${PANEL_USER}" "${INSTALL_DIR}/bin/veyna-panel" --migrate-only 2>&1 || {
        warn "Migration command not supported. Migrations will run on first start."
    }
}

# ---------------------------------------------------------------------------
# Start service
# ---------------------------------------------------------------------------
start_service() {
    header "Starting ${PRODUCT_NAME}"
    systemctl start "${SERVICE_NAME}"
    sleep 3

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Service started successfully."
    else
        error "Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
        systemctl status "${SERVICE_NAME}" --no-pager || true
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
health_check() {
    header "Running health checks"
    local max_attempts=30
    local attempt=0
    local url="http://127.0.0.1:${PORT}/healthz"

    info "Waiting for service to be ready..."
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if curl -sf -o /dev/null --max-time 5 "${url}" 2>/dev/null; then
            info "Health check passed."
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    warn "Health check did not pass within ${max_attempts} attempts."
    warn "Check logs: journalctl -u ${SERVICE_NAME} -n 50"
    return 1
}

# ---------------------------------------------------------------------------
# Backup / rollback (preserved from original)
# ---------------------------------------------------------------------------
backup_current() {
    header "Backing up current installation"
    local backup_path
    backup_path="${BACKUP_DIR}/pre-upgrade-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_path}"

    cp -a "${CONFIG_DIR}" "${backup_path}/config" 2>/dev/null || true
    [[ -f "${INSTALL_DIR}/bin/veyna-panel" ]] && cp "${INSTALL_DIR}/bin/veyna-panel" "${backup_path}/"
    if [[ -n "${DB_URL:-}" ]]; then
        pg_dump "${DB_URL}" > "${backup_path}/database.sql" 2>/dev/null || warn "Database backup failed."
    fi

    touch "${CONFIG_DIR}/.install-backup-marker"
    echo "${backup_path}" > "${CONFIG_DIR}/.last-backup-path"
    info "Backup created: ${backup_path}"
}

do_rollback() {
    header "Rolling back installation"
    local backup_path

    if [[ -n "${ROLLBACK_VERSION}" ]]; then
        backup_path="${ROLLBACK_VERSION}"
    elif [[ -f "${CONFIG_DIR}/.last-backup-path" ]]; then
        backup_path=$(cat "${CONFIG_DIR}/.last-backup-path")
    else
        fatal "No backup found to rollback to."
    fi

    if [[ ! -d "${backup_path}" ]]; then
        fatal "Backup directory not found: ${backup_path}"
    fi

    info "Rolling back to: ${backup_path}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

    if [[ -f "${backup_path}/veyna-panel" ]]; then
        cp "${backup_path}/veyna-panel" "${INSTALL_DIR}/bin/veyna-panel"
        chmod 755 "${INSTALL_DIR}/bin/veyna-panel"
    fi

    if [[ -d "${backup_path}/config" ]]; then
        cp -a "${backup_path}/config/"* "${CONFIG_DIR}/"
    fi

    if [[ -f "${backup_path}/database.sql" && -n "${DB_URL:-}" ]]; then
        info "Restoring database..."
        psql "${DB_URL}" < "${backup_path}/database.sql" 2>/dev/null || warn "Database restore failed."
    fi

    systemctl start "${SERVICE_NAME}"
    info "Rollback complete."
}

do_upgrade() {
    header "Upgrading ${PRODUCT_NAME}"
    if ! detect_existing; then
        fatal "No existing installation found. Use install mode instead."
    fi
    detect_mode

    backup_current
    download_panel
    install_migrations
    run_migrations
    systemctl restart "${SERVICE_NAME}"
    health_check
    info "Upgrade complete!"
}

do_uninstall() {
    header "Uninstalling ${PRODUCT_NAME}"
    if ! confirm "This will remove ${PRODUCT_NAME} and ALL data. Are you sure?"; then
        info "Uninstall cancelled."
        exit 0
    fi

    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "${SYSTEMD_UNIT}"

    # Remove nginx config
    rm -f "/etc/nginx/sites-available/${SERVICE_NAME}"
    rm -f "/etc/nginx/sites-enabled/${SERVICE_NAME}"
    # shellcheck disable=SC2015
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

    systemctl daemon-reload

    if confirm "Remove data directory (${DATA_DIR})?"; then
        rm -rf "${DATA_DIR}"
    fi
    rm -rf "${INSTALL_DIR:?}/bin" "${INSTALL_DIR:?}/migrations"
    rm -rf "${CONFIG_DIR}"

    if id "${PANEL_USER}" &>/dev/null; then
        userdel "${PANEL_USER}" 2>/dev/null || true
    fi

    if confirm "Remove PostgreSQL database and user?"; then
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
        sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};" 2>/dev/null || true
    fi

    info "Uninstall complete."
    if [[ -d "${BACKUP_DIR}" ]]; then
        info "Backups preserved in: ${BACKUP_DIR}"
    fi
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------
gather_input() {
    header "${PRODUCT_NAME} Installation"

    INSTALL_MODE="systemd"
    info "Installation mode: systemd (docker mode is not ready yet in this installer version)"

    # On a reinstall these already hold the previous install's values (see
    # restore_existing_config); offering them as the defaults means pressing
    # Enter keeps the URL the operator has already handed out, instead of
    # blanking the domain and picking a brand-new port.
    prompt DOMAIN "Domain pointing to this server (leave empty if none)" "${DOMAIN}"

    local default_port="${PORT}"
    [[ -z "${default_port}" ]] && default_port=$(find_free_port)
    prompt PORT "Panel port (internal, behind nginx) [auto]" "${default_port}"
    prompt WEB_PORT "Admin UI port (nginx, public)" "${WEB_PORT}"
    prompt NODE_PORT "Co-located VPN node port" "${NODE_PORT}"

    prompt ADMIN_USERNAME "Admin username" "admin"
    prompt_password ADMIN_PASSWORD "Set admin password"
    prompt ADMIN_EMAIL "Admin email" "admin@$(hostname -f 2>/dev/null || echo localhost)"

    if [[ -n "${DOMAIN}" ]]; then
        prompt LE_EMAIL "Email for Let's Encrypt certificate" ""
    fi

    prompt DB_MODE "Database mode (local/external)" "local"
    if [[ "${DB_MODE}" == "external" ]]; then
        prompt DB_HOST "Database host" "localhost"
        prompt DB_PORT "Database port" "5432"
        prompt DB_NAME "Database name" "veyna_panel"
        prompt DB_USER "Database user" "veyna"
        prompt_password DB_PASSWORD "Database password"
        DB_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi

    prompt_choice TLS_MODE "TLS mode" "auto" "off" "manual"

    if [[ "${ADVANCED}" == "true" ]]; then
        prompt TIMEZONE "System timezone" "$(timedatectl show -p Timezone --value 2>/dev/null || echo 'UTC')"
        prompt LANGUAGE "Language (en/fa/...)" "en"
        prompt_choice MFA_ENABLED "Enable MFA (TOTP)?" "false" "true"
        prompt BACKUP_DIR "Backup directory" "${BACKUP_DIR_DEFAULT}"
        prompt UPDATE_CHANNEL "Update channel (stable/beta/nightly)" "stable"
    fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    # NOTE: this must NOT be `local` and must NOT be invoked via `$(...)` —
    # every flag below (NON_INTERACTIVE, INSTALL_MODE, ADMIN_PASSWORD, ...)
    # is a global this function sets as a side effect. A command-substitution
    # call (`x=$(parse_args ...)`) runs the whole function in a subshell,
    # silently discarding every one of those side effects and leaving only
    # the mode string behind — which used to make every flag (including -y)
    # a no-op and send a non-interactive install straight into `read` with
    # no TTY attached.
    ACTION_MODE="install"
    while [[ $# -gt 0 ]]; do
        # Recorded so restore_existing_config can tell an explicitly passed
        # flag from a variable still sitting at its compile-time default —
        # several defaults here are non-empty, so emptiness alone cannot
        # distinguish the two.
        CLI_SET["$1"]=1
        case "$1" in
            --mode)
                INSTALL_MODE="$2"; shift 2 ;;
            --domain)
                DOMAIN="$2"; shift 2 ;;
            --port)
                PORT="$2"; shift 2 ;;
            --web-port)
                WEB_PORT="$2"; shift 2 ;;
            --node-port)
                NODE_PORT="$2"; shift 2 ;;
            --le-email)
                LE_EMAIL="$2"; shift 2 ;;
            --admin-user)
                ADMIN_USERNAME="$2"; shift 2 ;;
            --admin-pass)
                ADMIN_PASSWORD="$2"; shift 2 ;;
            --admin-email)
                ADMIN_EMAIL="$2"; shift 2 ;;
            --db-mode)
                DB_MODE="$2"; shift 2 ;;
            --db-url)
                DB_URL="$2"; shift 2 ;;
            --db-host)
                DB_HOST="$2"; shift 2 ;;
            --db-port)
                DB_PORT="$2"; shift 2 ;;
            --db-name)
                DB_NAME="$2"; shift 2 ;;
            --db-user)
                DB_USER="$2"; shift 2 ;;
            --db-pass)
                DB_PASSWORD="$2"; shift 2 ;;
            --timezone)
                TIMEZONE="$2"; shift 2 ;;
            --language)
                LANGUAGE="$2"; shift 2 ;;
            --tls)
                TLS_MODE="$2"; shift 2 ;;
            --mfa)
                MFA_ENABLED="$2"; shift 2 ;;
            --backup-dir)
                BACKUP_DIR="$2"; shift 2 ;;
            --channel)
                UPDATE_CHANNEL="$2"; shift 2 ;;
            --secret-key)
                SECRET_KEY="$2"; shift 2 ;;
            --admin-url-path)
                ADMIN_URL_PATH="$2"; shift 2 ;;
            --bundle)
                BUNDLE_PATH="$2"; shift 2 ;;
            --advanced)
                ADVANCED=true; shift ;;
            --non-interactive|-y)
                NON_INTERACTIVE=true; shift ;;
            --force|-f)
                FORCE=true; shift ;;
            --skip-confirm)
                SKIP_CONFIRM=true; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            --rollback)
                ACTION_MODE="rollback"; shift
                if [[ "${1:-}" =~ ^-- ]]; then
                    :
                elif [[ -n "${1:-}" && ! "${1:-}" =~ ^- ]]; then
                    ROLLBACK_VERSION="$1"; shift
                fi
                ;;
            --upgrade)
                ACTION_MODE="upgrade"; shift ;;
            --uninstall)
                ACTION_MODE="uninstall"; shift ;;
            --version|-v)
                echo "${PRODUCT_NAME} Installer v${INSTALLER_VERSION}"; exit 0 ;;
            --help|-h)
                usage; exit 0 ;;
            *)
                fatal "Unknown option: $1. Use --help for usage." ;;
        esac
    done
}

usage() {
    cat <<EOF
${PRODUCT_NAME} Installer v${INSTALLER_VERSION}

Usage: sudo bash install.sh [OPTIONS]

Modes:
  (default)           Fresh installation
  --upgrade           Upgrade existing installation
  --rollback [DIR]    Rollback to previous version
  --uninstall         Remove ${PRODUCT_NAME}

Options:
  --mode MODE         Installation mode: systemd (docker not yet supported)
  --domain HOST       Domain or IP address
  --port PORT         Panel port, internal/behind nginx (default: 8080)
  --web-port PORT     Admin UI (nginx) port (default: 80; use if 80 is taken)
  --node-port PORT    Co-located VPN node port (default: 8443; use if taken)
  --le-email EMAIL    Email for Let's Encrypt (used when domain is set and TLS is not off)
  --admin-user USER   Admin username
  --admin-pass PASS   Admin password
  --admin-email EMAIL Admin email
  --db-mode MODE      Database mode: local, external
  --db-url URL        Full database URL
  --db-host HOST      Database host
  --db-port PORT      Database port
  --db-name NAME      Database name
  --db-user USER      Database user
  --db-pass PASS      Database password
  --timezone TZ       System timezone
  --language LANG     Language code
  --tls MODE          TLS mode: auto (default), off, manual
  --mfa BOOL          Enable MFA: true, false
  --backup-dir DIR    Backup directory
  --channel CHAN      Update channel: stable, beta, nightly
  --secret-key KEY    Application secret key
  --admin-url-path P  Admin URL path
  --bundle PATH       Path to a cerbenum-panel-*.tar.gz bundle (offline install)
  --advanced          Show advanced prompts (timezone, language, backup dir, etc.)
  --non-interactive   Non-interactive mode (use with flags)
  -y                  Same as --non-interactive
  --force, -f         Force operation even if checks fail
  --skip-confirm      Skip confirmation prompts
  --dry-run           Show what would be done without doing it
  --version, -v       Show version
  --help, -h          Show this help

Examples:
  # Interactive installation (downloads the latest public release)
  sudo bash install.sh

  # Non-interactive systemd installation
  sudo bash install.sh -y \\
    --mode systemd \\
    --domain panel.example.com \\
    --le-email admin@example.com \\
    --admin-user admin \\
    --admin-pass 'SecurePass123!' \\
    --admin-email admin@example.com \\
    --db-mode local

  # Offline install from a downloaded bundle
  tar xzf cerbenum-panel-linux-x86_64.tar.gz
  sudo bash cerbenum-panel/install.sh

  # Upgrade existing installation
  sudo bash install.sh --upgrade

  # Rollback to specific backup
  sudo bash install.sh --rollback /var/backups/veyna-panel/pre-upgrade-20240101_120000

  # Uninstall
  sudo bash install.sh --uninstall
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    print_banner
    check_root
    check_os

    case "${ACTION_MODE}" in
        install)
            if detect_existing && [[ "${FORCE}" != "true" ]]; then
                warn "Existing installation detected."
                if ! confirm "Proceed with reinstall/upgrade?"; then
                    exit 0
                fi
            fi

            check_resources

            if [[ "${NON_INTERACTIVE}" != "true" ]]; then
                gather_input
            fi

            # Defaults
            [[ -z "${INSTALL_MODE}" ]] && INSTALL_MODE="systemd"
            [[ -z "${DB_MODE}" ]] && DB_MODE="local"
            [[ -z "${ADMIN_PASSWORD}" && "${NON_INTERACTIVE}" == "true" ]] && fatal "Admin password is required (--admin-pass)"

            resolve_port

            if [[ "${DRY_RUN}" == "true" ]]; then
                header "Dry Run - Actions that would be taken"
                echo "  Mode: ${INSTALL_MODE}"
                echo "  Domain: ${DOMAIN:-<none>}"
                echo "  Port (internal): ${PORT}"
                echo "  Web port: ${WEB_PORT}"
                echo "  Node port: ${NODE_PORT}"
                echo "  Admin: ${ADMIN_USERNAME:-admin}"
                echo "  DB Mode: ${DB_MODE:-local}"
                echo "  TLS: ${TLS_MODE}"
                exit 0
            fi

            # shellcheck disable=SC2015
            [[ "${SKIP_CONFIRM}" != "true" && "${NON_INTERACTIVE}" != "true" ]] && confirm "Begin installation?" || true

            install_packages
            create_system_user
            create_directories

            if [[ "${DB_MODE}" == "external" ]]; then
                setup_postgresql_external
            else
                setup_postgresql_local
            fi

            download_panel
            install_migrations
            install_panelctl
            write_config
            bootstrap_admin

            if [[ "${INSTALL_MODE}" == "systemd" ]]; then
                install_systemd_service
                run_migrations
                start_service
                health_check
            else
                fatal "Docker mode is not ready yet in this installer version — rerun with --mode systemd."
            fi

            # TLS + Nginx
            if [[ "${TLS_MODE}" != "off" ]]; then
                setup_ssl
            else
                CERT_TYPE="none"
            fi
            install_nginx
            install_frontend
            open_firewall

            header "Installation Complete!"
            echo ""
            local web_suffix=""
            [[ "${WEB_PORT}" != "80" ]] && web_suffix=":${WEB_PORT}"
            local scheme="http"
            [[ -n "${CERT_TYPE}" && "${CERT_TYPE}" != "none" ]] && scheme="https"
            info "Panel URL:      ${scheme}://${DOMAIN:-localhost}${web_suffix}/"
            info "Admin URL:      ${scheme}://${DOMAIN:-localhost}${web_suffix}/${ADMIN_URL_PATH}/"
            info "Admin User:     ${ADMIN_USERNAME}"
            info "Config:         ${CONFIG_DIR}/config.env"
            info "Data:           ${DATA_DIR}"
            info "Logs:           ${LOG_DIR}"
            info "Backups:        ${BACKUP_DIR}"
            echo ""
            info "Management CLI: veyna-panelctl (installed to /usr/local/bin/)"
            echo ""
            warn "Save your admin URL path! It's the only way to access the admin panel."
            warn "Admin URL path: ${ADMIN_URL_PATH}"
            echo ""
            ;;

        upgrade)
            do_upgrade
            ;;

        rollback)
            do_rollback
            ;;

        uninstall)
            do_uninstall
            ;;

        *)
            fatal "Unknown mode: ${ACTION_MODE}"
            ;;
    esac
}

main "$@"
