#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Colors
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
divider() { echo "────────────────────────────────────────────"; }

# ─────────────────────────────────────────────
#  Banner
# ─────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║      WordPress + Docker  Setup           ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────
#  Prerequisites
# ─────────────────────────────────────────────
for cmd in docker curl unzip; do
  command -v "$cmd" &>/dev/null || error "Missing prerequisite: $cmd"
done

DOCKER_COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  error "docker compose (plugin) or docker-compose not found."
fi

# ─────────────────────────────────────────────
#  Prevent running setup in this repo
# ─────────────────────────────────────────────
if [[ -f .env ]]; then
  error "You cannot run setup in this repository"
fi

# ─────────────────────────────────────────────
#  Detection of previous setup
# ─────────────────────────────────────────────
DO_CONFIG=true
DO_WORDPRESS=true

if [[ -f .env ]]; then
  echo ""
  warn "A previous setup was detected (.env file present)."
  divider
  echo -e "  ${BOLD}What do you want to do?${RESET}"
  echo -e "  ${CYAN}1)${RESET} Start from scratch (reconfigure .env + download WordPress)"
  echo -e "  ${CYAN}2)${RESET} Reconfigure only .env (keep public_html intact)"
  echo -e "  ${CYAN}3)${RESET} Download only WordPress (keep current .env)"
  echo -e "  ${CYAN}4)${RESET} Skip configuration and download (go directly to build)"
  divider
  read -rp "$(echo -e "${YELLOW}Choice${RESET} [1/2/3/4]: ")" resume_choice

  case "${resume_choice}" in
    1)
      info "Starting from scratch..."
      DO_CONFIG=true
      DO_WORDPRESS=true
      ;;
    2)
      info "I will reconfigure only the .env file."
      DO_CONFIG=true
      DO_WORDPRESS=false
      ;;
    3)
      info "Skipping configuration, downloading only WordPress."
      DO_CONFIG=false
      DO_WORDPRESS=true
      # Load variables from existing .env for final summary
      set -a; source .env; set +a
      ;;
    4)
      info "Skipping configuration and download."
      DO_CONFIG=false
      DO_WORDPRESS=false
      set -a; source .env; set +a
      ;;
    *)
      warn "Invalid choice, starting from scratch."
      DO_CONFIG=true
      DO_WORDPRESS=true
      ;;
  esac
  echo ""
fi

# ─────────────────────────────────────────────
#  .env Configuration
# ─────────────────────────────────────────────
if [[ "$DO_CONFIG" == "true" ]]; then
  echo -e "${BOLD}Project configuration${RESET}"
  divider

  read -rp "$(echo -e "${YELLOW}Project name${RESET} [my_website]: ")" PROJECT_NAME
  PROJECT_NAME="${PROJECT_NAME:-my_website}"

  read -rp "$(echo -e "${YELLOW}Nginx port${RESET} [8001]: ")" NGINX_PORT
  NGINX_PORT="${NGINX_PORT:-8001}"

  read -rp "$(echo -e "${YELLOW}MySQL root password${RESET} [root]: ")" MYSQL_ROOT_PASSWORD
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"

  read -rp "$(echo -e "${YELLOW}Database name${RESET} [${PROJECT_NAME}]: ")" MYSQL_DATABASE
  MYSQL_DATABASE="${MYSQL_DATABASE:-$PROJECT_NAME}"

  read -rp "$(echo -e "${YELLOW}Database user${RESET} [wpuser]: ")" MYSQL_USER
  MYSQL_USER="${MYSQL_USER:-wpuser}"

  read -rp "$(echo -e "${YELLOW}Database user password${RESET} [wppassword]: ")" MYSQL_PASSWORD
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-wppassword}"

  echo ""

  if [[ ! -f .env.example ]]; then
    error "File .env.example not found in current directory."
  fi

  cp .env.example .env

  sed -i "s|^PROJECT_NAME=.*|PROJECT_NAME=${PROJECT_NAME}|"                     .env
  sed -i "s|^NGINX_PORT=.*|NGINX_PORT=${NGINX_PORT}|"                           .env
  sed -i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}|" .env
  sed -i "s|^MYSQL_DATABASE=.*|MYSQL_DATABASE=${MYSQL_DATABASE}|"               .env
  sed -i "s|^MYSQL_USER=.*|MYSQL_USER=${MYSQL_USER}|"                           .env
  sed -i "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${MYSQL_PASSWORD}|"               .env

  success "File .env generated."

  # UID/GID
  CURRENT_UID=$(id -u)
  CURRENT_GID=$(id -g)
  grep -q "^UID=" .env && sed -i "s|^UID=.*|UID=${CURRENT_UID}|" .env || echo "UID=${CURRENT_UID}" >> .env
  grep -q "^GID=" .env && sed -i "s|^GID=.*|GID=${CURRENT_GID}|" .env || echo "GID=${CURRENT_GID}" >> .env
fi

# ─────────────────────────────────────────────
#  Create necessary directories
# ─────────────────────────────────────────────
info "Creating necessary directories..."
mkdir -p public_html logs

# ─────────────────────────────────────────────
#  Download WordPress
# ─────────────────────────────────────────────
if [[ "$DO_WORDPRESS" == "true" ]]; then
  if [[ -f public_html/wp-login.php ]]; then
    warn "WordPress seems already present in public_html/."
    read -rp "$(echo -e "${YELLOW}Overwrite current content?${RESET} [y/N]: ")" reinstall
    if [[ "${reinstall,,}" == "y" ]]; then
      info "Removing content of public_html/..."
      sudo rm -rf public_html/*
    else
      info "Skipping WordPress download."
      DO_WORDPRESS=false
    fi
  fi
fi

if [[ "$DO_WORDPRESS" == "true" ]]; then
  info "Downloading the latest version of WordPress..."
  TMP_DIR=$(mktemp -d)

  # Cleanup guaranteed even in case of error
  trap 'rm -rf "${TMP_DIR}"' EXIT

  if ! curl -fsSL --retry 3 --retry-delay 5 \
      "https://wordpress.org/latest.zip" -o "${TMP_DIR}/wordpress.zip"; then
    error "WordPress download failed. Check connection and try again."
  fi

  success "Download completed."

  info "Extracting files to public_html/..."
  unzip -q "${TMP_DIR}/wordpress.zip" -d "${TMP_DIR}"
  cp -r "${TMP_DIR}/wordpress/." public_html/
  trap - EXIT
  rm -rf "${TMP_DIR}"
  success "WordPress extracted to public_html/."
fi

# ─────────────────────────────────────────────
#  Rename .gitignore-production → .gitignore
# ─────────────────────────────────────────────
if [[ -f .gitignore-production ]]; then
  mv .gitignore-production .gitignore
  success ".gitignore-production renamed to .gitignore."
else
  warn "File .gitignore-production not found, skipping rename."
fi

# ─────────────────────────────────────────────
#  Generate project README.md
# ─────────────────────────────────────────────
info "Generating README.md for project ${PROJECT_NAME}..."
cat > README.md << READMEEOF
# ${PROJECT_NAME}

Local WordPress development environment based on Docker (Nginx + PHP-FPM + MariaDB).

## Local URL

http://localhost:${NGINX_PORT}

## Requirements

- Docker with Compose plugin (v2)
- \`curl\`, \`unzip\`, \`make\`

## Available commands

\`\`\`bash
make help         # complete list of commands
make up           # start containers
make down         # stop containers
make logs         # follow logs of all services
make shell-php    # open shell in PHP container
make shell-db     # open MariaDB client
make db-backup    # perform dump of ${PROJECT_NAME} database
make db-restore FILE=${PROJECT_NAME}.sql
make env-encrypt  # Encrypt .env file with passphrase to upload to repository
make env-decrypt  # extract encrypted .env file from repository
\`\`\`


## Initial Setup for Development

- Clone this repository
- \`make env-decrypt\`
- \`make up\`
- \`make db-restore FILE=${PROJECT_NAME}.sql\`

## Environment Variables

Defined in the \`.env\` file (generated from \`.env.example\` via setup.sh).

| Variable             | Description                       |
|-----------------------|-----------------------------------|
| \`PROJECT_NAME\`        | Project name                      |
| \`NGINX_PORT\`          | Local port exposed by Nginx      |
| \`MYSQL_ROOT_PASSWORD\` | MariaDB root password             |
| \`MYSQL_DATABASE\`      | Database name                     |
| \`MYSQL_USER\`          | Database user                     |
| \`MYSQL_PASSWORD\`      | Database user password            |

## Deploy

The \`.github/workflows/deploy.yml\` file handles automatic FTP deployment on push to \`main\`. Configure in the **Settings → Secrets and variables** of the repo:

| Type     | Name                | Description                  |
|----------|---------------------|------------------------------|
| Secret   | \`FTP_SERVER\`        | FTP server hostname          |
| Secret   | \`FTP_USERNAME\`      | FTP username                 |
| Secret   | \`FTP_PASSWORD\`      | FTP password                 |
| Variable | \`WORKING_DIRECTORY\` | Local theme path             |
| Variable | \`FTP_SERVER_DIR\`    | Remote path on server        |
| Variable | \`FTP_PORT\`          | FTP port (e.g. \`21\`)         |
| Variable | \`FTP_PROTOCOL\`      | Protocol (\`ftp\` or \`ftps\`) |
READMEEOF
success "README.md generated."

# ─────────────────────────────────────────────
#  Build and start Docker
# ─────────────────────────────────────────────
echo ""
read -rp "$(echo -e "${YELLOW}Do you want to build and start the containers now?${RESET} [Y/n]: ")" start_docker

if [[ "${start_docker,,}" != "n" ]]; then
  info "Building containers..."
  $DOCKER_COMPOSE_CMD build

  info "Starting containers..."
  $DOCKER_COMPOSE_CMD up -d

  success "Containers started."
  echo ""
  echo -e "${BOLD}${GREEN}✔  Setup completed!${RESET}"
  echo -e "   Open browser at:             ${CYAN}http://localhost:${NGINX_PORT}${RESET}"
  echo -e "   Database name:               ${CYAN}${MYSQL_DATABASE}${RESET}"
  echo -e "   Database username:           ${CYAN}${MYSQL_USER}${RESET}"
  echo -e "   Database password:           ${CYAN}${MYSQL_PASSWORD}${RESET}"
  echo -e "   Database host:               ${CYAN}db${RESET}"
else
  echo ""
  success "Setup completed. To start manually:"
  echo -e "   ${CYAN}${DOCKER_COMPOSE_CMD} up -d --build${RESET}"
fi