#!/bin/bash
# =============================================
# FitLoop — MySQL 自动备份脚本
# 添加到 crontab:
#   0 3 * * * /root/FitLoop/deploy/backup.sh
# 每天凌晨 3:00 自动备份
# =============================================

set -euo pipefail
umask 077

# --- 配置 ---
BACKUP_DIR="${FITLOOP_BACKUP_DIR:-/root/backups/fitloop}"
RETENTION_DAYS="${FITLOOP_BACKUP_RETENTION_DAYS:-7}"
DB_HOST="${FITLOOP_DB_HOST:-localhost}"
DB_PORT="${FITLOOP_DB_PORT:-3306}"
MYSQL_CONTAINER="${FITLOOP_MYSQL_CONTAINER:-fitloop-mysql}"
ENV_FILE="${FITLOOP_ENV_FILE:-/root/FitLoop/.env}"
BACKUP_MODE="${FITLOOP_BACKUP_MODE:-docker}"

if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] FITLOOP_BACKUP_RETENTION_DAYS 必须是非负整数"
    exit 1
fi
if [ "${BACKUP_MODE}" != "docker" ] && [ "${BACKUP_MODE}" != "direct" ]; then
    echo "[ERROR] FITLOOP_BACKUP_MODE 只能是 docker 或 direct"
    exit 1
fi

# --- 从 .env 按字面读取必要数据库配置，不执行 dotenv 内容 ---
if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] .env 文件不存在: $ENV_FILE"
    exit 1
fi

read_env_value() {
    sed -n "s/^${1}=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'
}

MYSQL_USER="${MYSQL_USER:-$(read_env_value MYSQL_USER)}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(read_env_value MYSQL_PASSWORD)}"
DB_NAME="${MYSQL_DATABASE:-$(read_env_value MYSQL_DATABASE)}"
DB_NAME="${DB_NAME:-fitloop}"

if [ -z "${MYSQL_USER}" ] || [ -z "${MYSQL_PASSWORD}" ]; then
    echo "[ERROR] MYSQL_USER 和 MYSQL_PASSWORD 必须配置且不能为空"
    exit 1
fi

# --- 准备备份目录 ---
mkdir -p "$BACKUP_DIR"
BACKUP_DIR="$(cd "${BACKUP_DIR}" && pwd -P)"
if [ "${BACKUP_DIR}" = "/" ]; then
    echo "[ERROR] 备份目录不能是文件系统根目录"
    exit 1
fi
DATE_TAG=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/fitloop_${DATE_TAG}.sql.gz"
TEMP_BACKUP=""
ERROR_LOG=""
MYSQL_CLIENT_CONFIG=""

cleanup() {
    local path
    for path in "${TEMP_BACKUP}" "${ERROR_LOG}" "${MYSQL_CLIENT_CONFIG}"; do
        if [ -n "${path}" ]; then
            rm -f -- "${path}"
        fi
    done
}
trap cleanup EXIT INT TERM

TEMP_BACKUP="$(mktemp "${BACKUP_DIR}/.fitloop_${DATE_TAG}.XXXXXX.sql.gz")"
ERROR_LOG="$(mktemp "${BACKUP_DIR}/.fitloop-backup-err.XXXXXX")"
MYSQL_CLIENT_CONFIG="$(mktemp "${BACKUP_DIR}/.fitloop-mysql-client.XXXXXX.cnf")"

escape_mysql_option_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
}

{
    printf '[client]\n'
    printf 'user=%s\n' "$(escape_mysql_option_value "${MYSQL_USER}")"
    printf 'password=%s\n' "$(escape_mysql_option_value "${MYSQL_PASSWORD}")"
} > "${MYSQL_CLIENT_CONFIG}"
chmod 600 "${MYSQL_CLIENT_CONFIG}"

echo "============================================"
echo " FitLoop 数据库备份 - $(date)"
echo "============================================"

# --- 检查 Docker MySQL 是否运行 ---
USE_DOCKER=false
if [ "${BACKUP_MODE}" = "direct" ]; then
    echo "[WARN] 已显式启用直连 mysqldump 模式"
elif ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker 备份模式已启用，但找不到 docker 命令"
    exit 1
elif ! DOCKER_CONTAINERS="$(docker ps --format '{{.Names}}' 2>&1)"; then
    echo "[ERROR] 无法查询 Docker 容器，拒绝回退到可能错误的本机数据库"
    printf '%s\n' "${DOCKER_CONTAINERS}" >&2
    exit 1
elif printf '%s\n' "${DOCKER_CONTAINERS}" |
    grep -Fx "${MYSQL_CONTAINER}" >/dev/null; then
    USE_DOCKER=true
else
    echo "[ERROR] ${MYSQL_CONTAINER} 容器未运行；如确需直连，请显式设置 FITLOOP_BACKUP_MODE=direct"
    exit 1
fi

# --- 执行备份 ---
echo "[INFO] 备份数据库: ${DB_NAME}"

run_dump() {
    if [ "${USE_DOCKER}" = true ]; then
        docker exec -i "${MYSQL_CONTAINER}" sh -c '
            set -eu
            umask 077
            client_config="$(mktemp)"
            cleanup_client_config() {
                rm -f -- "${client_config}"
            }
            trap cleanup_client_config EXIT INT TERM
            cat > "${client_config}"
            mysqldump "--defaults-extra-file=${client_config}" "$@"
        ' sh \
            --databases "${DB_NAME}" \
            --no-tablespaces \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --skip-lock-tables \
            < "${MYSQL_CLIENT_CONFIG}"
    else
        mysqldump \
            "--defaults-extra-file=${MYSQL_CLIENT_CONFIG}" \
            -h"${DB_HOST}" \
            -P"${DB_PORT}" \
            --databases "${DB_NAME}" \
            --no-tablespaces \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --skip-lock-tables
    fi
}

if ! run_dump 2>"${ERROR_LOG}" | gzip > "${TEMP_BACKUP}"; then
    echo "[ERROR] mysqldump 或 gzip 执行失败，未替换现有备份"
    cat "${ERROR_LOG}" 2>/dev/null || true
    exit 1
fi

# --- 检查备份结果 ---
if [ ! -s "${TEMP_BACKUP}" ] || ! gzip -t "${TEMP_BACKUP}"; then
    echo "[ERROR] 备份文件为空或 gzip 完整性校验失败，未替换现有备份"
    exit 1
fi

UNCOMPRESSED_BYTES="$(gzip -cd "${TEMP_BACKUP}" | wc -c | tr -d '[:space:]')"
if [ "${UNCOMPRESSED_BYTES}" -eq 0 ]; then
    echo "[ERROR] 备份解压后为空，未替换现有备份"
    exit 1
fi

mv -f -- "${TEMP_BACKUP}" "${BACKUP_FILE}"
SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[OK] 备份成功: ${BACKUP_FILE} (${SIZE}, 解压后 ${UNCOMPRESSED_BYTES} 字节)"

# --- 清理旧备份 ---
echo "[INFO] 清理 ${RETENTION_DAYS} 天前的备份..."
find "${BACKUP_DIR}" -maxdepth 1 -type f \
    -name "fitloop_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete

# --- 统计 ---
TOTAL=$(find "${BACKUP_DIR}" -maxdepth 1 -type f \
    -name "fitloop_*.sql.gz" | wc -l | tr -d '[:space:]')
echo "[INFO] 当前共有 ${TOTAL} 个备份文件"
echo "[OK] 备份完成！"
