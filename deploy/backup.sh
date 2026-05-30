#!/bin/bash
# =============================================
# FitLoop — MySQL 自动备份脚本
# 添加到 crontab:
#   0 3 * * * /root/FitLoop/deploy/backup.sh
# 每天凌晨 3:00 自动备份
# =============================================

set -e

# --- 配置 ---
BACKUP_DIR="/root/backups/fitloop"
RETENTION_DAYS=7
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME="fitloop"

# --- 从 .env 读取数据库密码 ---
ENV_FILE="/root/FitLoop/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "[ERROR] .env 文件不存在: $ENV_FILE"
    exit 1
fi

# --- 准备备份目录 ---
mkdir -p "$BACKUP_DIR"
DATE_TAG=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/fitloop_${DATE_TAG}.sql.gz"

echo "============================================"
echo " FitLoop 数据库备份 - $(date)"
echo "============================================"

# --- 检查 Docker MySQL 是否运行 ---
if ! docker ps --format '{{.Names}}' | grep -q "fitloop-mysql"; then
    echo "[WARN] fitloop-mysql 容器未运行，尝试用 mysqldump 直接备份"
fi

# --- 执行备份 ---
echo "[INFO] 备份数据库: ${DB_NAME}"

# 方案 A: 通过 Docker 容器备份（优先）
if docker ps --format '{{.Names}}' | grep -q "fitloop-mysql"; then
    docker exec fitloop-mysql \
        mysqldump \
        -u"${MYSQL_USER}" \
        -p"${MYSQL_PASSWORD}" \
        --databases "${DB_NAME}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --skip-lock-tables \
        2>/tmp/fitloop-backup-err.log \
    | gzip > "${BACKUP_FILE}"
else
    # 方案 B: 直接连接
    mysqldump \
        -h"${DB_HOST}" \
        -P"${DB_PORT}" \
        -u"${MYSQL_USER}" \
        -p"${MYSQL_PASSWORD}" \
        --databases "${DB_NAME}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --skip-lock-tables \
        2>/tmp/fitloop-backup-err.log \
    | gzip > "${BACKUP_FILE}"
fi

# --- 检查备份结果 ---
if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
    SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo "[OK] 备份成功: ${BACKUP_FILE} (${SIZE})"
else
    echo "[ERROR] 备份失败！"
    cat /tmp/fitloop-backup-err.log 2>/dev/null || true
    exit 1
fi

# --- 清理旧备份 ---
echo "[INFO] 清理 ${RETENTION_DAYS} 天前的备份..."
find "${BACKUP_DIR}" -name "fitloop_*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# --- 统计 ---
TOTAL=$(find "${BACKUP_DIR}" -name "fitloop_*.sql.gz" | wc -l)
echo "[INFO] 当前共有 ${TOTAL} 个备份文件"
echo "[OK] 备份完成！"
