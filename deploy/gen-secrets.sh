#!/bin/bash
# Generate a new production dotenv file without printing secrets to stdout.
# Usage: bash deploy/gen-secrets.sh [output-file]

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_FILE="${1:-deploy/.env.production}"
if [ -e "${OUTPUT_FILE}" ]; then
    echo "Refusing to overwrite existing secret file: ${OUTPUT_FILE}" >&2
    exit 1
fi

umask 077
mkdir -p "$(dirname "${OUTPUT_FILE}")"

JWT_SECRET="$(openssl rand -hex 64)"
OTP_HASH_SECRET="$(openssl rand -hex 64)"
DB_PASSWORD="$(openssl rand -hex 24)"
DB_ROOT_PASSWORD="$(openssl rand -hex 24)"
AGENT_SERVICE_KEY="$(openssl rand -hex 48)"
AGENT_DELEGATION_SECRET="$(openssl rand -hex 48)"

cat > "${OUTPUT_FILE}" <<EOF
MYSQL_DATABASE=fitloop
MYSQL_USER=fitloop
MYSQL_PASSWORD=${DB_PASSWORD}
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
FITLOOP_JWT_SECRET=${JWT_SECRET}
FITLOOP_OTP_HASH_SECRET=${OTP_HASH_SECRET}
FITLOOP_AGENT_SERVICE_KEY=${AGENT_SERVICE_KEY}
FITLOOP_AGENT_DELEGATION_SECRET=${AGENT_DELEGATION_SECRET}
FITLOOP_AGENT_ENABLED=false
FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT=
FITLOOP_ADMIN_BOOTSTRAP_NICKNAME=
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_COACH_MODEL=deepseek-v4-flash
DEEPSEEK_APPEAL_MODEL=deepseek-v4-pro
FITLOOP_OTP_DEBUG_RETURN=false
FITLOOP_MAIL_HOST=smtp.qq.com
FITLOOP_MAIL_PORT=465
FITLOOP_MAIL_USERNAME=
FITLOOP_MAIL_PASSWORD=
FITLOOP_MAIL_FROM=
FITLOOP_TLS_ENABLED=false
FITLOOP_HTTP_COMPAT_ENABLED=true
FITLOOP_TLS_CERT_FILE=
FITLOOP_TLS_KEY_FILE=
FITLOOP_PUBLIC_BASE_URL=
SERVER_PORT=8080
EOF

chmod 600 "${OUTPUT_FILE}"
echo "Created ${OUTPUT_FILE} with mode 600."
echo "Edit the empty mail, Agent, TLS, and public URL values before deployment."
