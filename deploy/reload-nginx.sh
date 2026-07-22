#!/bin/bash
# Recreate only Nginx after certificate renewal.
# Usage: bash deploy/reload-nginx.sh [cn|default]

set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE=".env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "Missing ${ENV_FILE}" >&2
    exit 1
fi

read_env_value() {
    sed -n "s/^${1}=//p" "${ENV_FILE}" | tail -n 1 | tr -d '\r'
}

TLS_ENABLED="$(read_env_value FITLOOP_TLS_ENABLED)"
HTTP_COMPAT_ENABLED="$(read_env_value FITLOOP_HTTP_COMPAT_ENABLED)"
TLS_CERT_FILE="$(read_env_value FITLOOP_TLS_CERT_FILE)"
TLS_KEY_FILE="$(read_env_value FITLOOP_TLS_KEY_FILE)"

if [ "${TLS_ENABLED}" != "true" ]; then
    echo "FITLOOP_TLS_ENABLED must be true before reloading TLS Nginx" >&2
    exit 1
fi
if [ ! -f "${TLS_CERT_FILE}" ] || [ ! -f "${TLS_KEY_FILE}" ]; then
    echo "TLS certificate or key file is missing" >&2
    exit 1
fi

COMPOSE_FILES=(-f deploy/docker-compose.yml)
case "${1:-cn}" in
    cn|china)
        COMPOSE_FILES+=(-f deploy/docker-compose.cn.yml)
        ;;
    default)
        ;;
    *)
        echo "Usage: $0 [cn|default]" >&2
        exit 2
        ;;
esac

COMPOSE_FILES+=(-f deploy/docker-compose.tls.yml)
if [ "${HTTP_COMPAT_ENABLED:-true}" = "false" ]; then
    COMPOSE_FILES+=(-f deploy/docker-compose.https-only.yml)
fi

docker compose "${COMPOSE_FILES[@]}" --env-file "${ENV_FILE}" config --quiet
docker compose "${COMPOSE_FILES[@]}" --env-file "${ENV_FILE}" \
    up -d --no-deps --force-recreate nginx

echo "Nginx recreated with the renewed certificate."
