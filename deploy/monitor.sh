#!/bin/bash
# =============================================
# FitLoop — 服务器健康检查
# 用法: bash deploy/monitor.sh
#       bash deploy/monitor.sh --alert  # 超过阈值时输出告警
# =============================================

set -e

cd "$(dirname "$0")/.."

ENV_FILE="${FITLOOP_ENV_FILE:-.env}"

read_env_value() {
    sed -n "s/^${1}=//p" "${ENV_FILE}" | tail -n 1 | tr -d '\r'
}

if [ -f "${ENV_FILE}" ]; then
    FITLOOP_AGENT_ENABLED="${FITLOOP_AGENT_ENABLED:-$(read_env_value FITLOOP_AGENT_ENABLED)}"
    FITLOOP_PUBLIC_BASE_URL="${FITLOOP_PUBLIC_BASE_URL:-$(read_env_value FITLOOP_PUBLIC_BASE_URL)}"
    ENV_TLS_CERT_MIN_VALID_SECONDS="$(
        read_env_value FITLOOP_TLS_CERT_MIN_VALID_SECONDS
    )"
    if [ -z "${FITLOOP_TLS_CERT_MIN_VALID_SECONDS:-}" ]; then
        FITLOOP_TLS_CERT_MIN_VALID_SECONDS="${ENV_TLS_CERT_MIN_VALID_SECONDS}"
    fi
fi

# --- 阈值 ---
CPU_THRESHOLD=80       # CPU 使用率 %
MEM_THRESHOLD=85       # 内存使用率 %
DISK_THRESHOLD=90      # 磁盘使用率 %
TLS_CERT_MIN_VALID_SECONDS="${FITLOOP_TLS_CERT_MIN_VALID_SECONDS:-1209600}"
if ! [[ "${TLS_CERT_MIN_VALID_SECONDS}" =~ ^[0-9]{1,8}$ ]] ||
   [ "${TLS_CERT_MIN_VALID_SECONDS}" -lt 1 ] ||
   [ "${TLS_CERT_MIN_VALID_SECONDS}" -gt 31536000 ]; then
    echo "[ERROR] FITLOOP_TLS_CERT_MIN_VALID_SECONDS 必须是 1 到 31536000 的整数秒数" >&2
    exit 1
fi
TLS_CERT_MIN_VALID_HOURS=$(( (TLS_CERT_MIN_VALID_SECONDS + 3599) / 3600 ))

ALERT_MODE=false
if [ "${1:-}" = "--alert" ]; then
    ALERT_MODE=true
fi

echo "═══════════════════════════════════════════"
echo "  FitLoop 服务器健康检查 - $(date)"
echo "═══════════════════════════════════════════"

# --- CPU ---
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
printf "%-20s %s%%\n" "CPU 使用率:" "${CPU_USAGE}"
if (( $(echo "${CPU_USAGE} > ${CPU_THRESHOLD}" | bc -l) )); then
    echo "  ⚠️  CPU 超过阈值 ${CPU_THRESHOLD}%"
fi

# --- 内存 ---
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_PCT=$(awk "BEGIN { printf \"%.1f\", ${MEM_USED}/${MEM_TOTAL}*100 }")
printf "%-20s %sMB / %sMB (%s%%)\n" "内存:" "${MEM_USED}" "${MEM_TOTAL}" "${MEM_PCT}"
if (( $(echo "${MEM_PCT} > ${MEM_THRESHOLD}" | bc -l) )); then
    echo "  ⚠️  内存超过阈值 ${MEM_THRESHOLD}%"
fi

# --- 磁盘 ---
DISK_INFO=$(df -h / | awk 'NR==2{print $3 " / " $2 " (" $5 ")"}')
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
printf "%-20s %s\n" "磁盘:" "${DISK_INFO}"
if [ "${DISK_PCT}" -gt "${DISK_THRESHOLD}" ]; then
    echo "  ⚠️  磁盘超过阈值 ${DISK_THRESHOLD}%"
fi

# --- Docker 容器状态 ---
echo ""
echo "--- Docker 容器 ---"
CONTAINER_ALERTS=""
EXPECTED_SERVICES=(
    fitloop-mysql
    fitloop-redis
    fitloop-backend
    fitloop-nginx
)
if [ "${FITLOOP_AGENT_ENABLED:-true}" = "true" ]; then
    EXPECTED_SERVICES+=(fitloop-agent-service)
fi

if ! command -v docker &> /dev/null; then
    CONTAINER_ALERTS="${CONTAINER_ALERTS}DOCKER:UNAVAILABLE "
    echo "  Docker 未安装"
elif ! docker ps --format "{{.Names}}" > /dev/null 2>&1; then
    CONTAINER_ALERTS="${CONTAINER_ALERTS}DOCKER:UNAVAILABLE "
    echo "  Docker 不可用"
else
    for SERVICE in "${EXPECTED_SERVICES[@]}"; do
        STATUS=$(docker ps --filter "name=${SERVICE}" --format "{{.Status}}" 2>/dev/null || true)
        if [[ "${STATUS}" == Up* ]] &&
           { [[ "${STATUS}" != *"("* ]] || [[ "${STATUS}" == *"(healthy)" ]]; }; then
            UPTIME=$(echo "${STATUS}" | sed 's/Up //')
            printf "  %-20s ✅ %s\n" "${SERVICE}:" "${UPTIME}"
        elif [[ "${STATUS}" == Up* ]]; then
            CONTAINER_ALERTS="${CONTAINER_ALERTS}CONTAINER:${SERVICE}:UNHEALTHY "
            printf "  %-20s ❌ 不健康\n" "${SERVICE}:"
        elif docker ps -a --filter "name=${SERVICE}" --format "{{.Names}}" 2>/dev/null | grep -q "${SERVICE}"; then
            CONTAINER_ALERTS="${CONTAINER_ALERTS}CONTAINER:${SERVICE}:DOWN "
            printf "  %-20s ❌ 已停止\n" "${SERVICE}:"
        else
            CONTAINER_ALERTS="${CONTAINER_ALERTS}CONTAINER:${SERVICE}:DOWN "
            printf "  %-20s ➖ 未创建\n" "${SERVICE}:"
        fi
    done
fi

# --- API 与 Agent 健康检查 ---
echo ""
echo "--- API 健康 ---"
PUBLIC_BASE_URL="${FITLOOP_PUBLIC_BASE_URL:-http://localhost}"
BACKEND_OK=false
PUBLIC_OK=false
for ENTRY in "Backend|http://localhost:8080/actuator/health" \
             "Public|${PUBLIC_BASE_URL%/}/actuator/health"; do
    NAME="${ENTRY%%|*}"
    URL="${ENTRY#*|}"
    RESP=$(curl -sf -w "%{http_code}" -o /dev/null "${URL}" 2>/dev/null || true)
    if [ "${RESP}" = "200" ]; then
        printf "  %-20s ✅ %s\n" "${NAME}:" "响应 200"
        if [ "${NAME}" = "Backend" ]; then
            BACKEND_OK=true
        else
            PUBLIC_OK=true
        fi
    else
        printf "  %-20s ❌ %s\n" "${NAME}:" "无响应 (${RESP})"
    fi
done

AGENT_READY=true
if [ "${FITLOOP_AGENT_ENABLED:-true}" = "true" ]; then
    AGENT_RESP=$(curl -sf -w "%{http_code}" -o /dev/null \
        "http://127.0.0.1:8090/ready" 2>/dev/null || true)
    if [ "${AGENT_RESP}" = "200" ]; then
        printf "  %-20s ✅ %s\n" "Agent:" "READY"
    else
        AGENT_READY=false
        printf "  %-20s ⚠️  %s\n" "Agent:" "NOT_READY (${AGENT_RESP})，核心 API 不受影响"
    fi
else
    printf "  %-20s ➖ %s\n" "Agent:" "已禁用"
fi

TLS_CERT_OK=true
if [[ "${PUBLIC_BASE_URL}" == https://* ]] && command -v openssl &> /dev/null; then
    PUBLIC_HOST="${PUBLIC_BASE_URL#https://}"
    PUBLIC_HOST="${PUBLIC_HOST%%/*}"
    PUBLIC_HOST="${PUBLIC_HOST%%:*}"
    if echo | openssl s_client -servername "${PUBLIC_HOST}" \
        -connect "${PUBLIC_HOST}:443" 2>/dev/null |
        openssl x509 -noout \
            -checkend "${TLS_CERT_MIN_VALID_SECONDS}" > /dev/null 2>&1; then
        printf "  %-20s ✅ %s\n" \
            "TLS 证书:" \
            "有效期超过 ${TLS_CERT_MIN_VALID_HOURS} 小时"
    else
        TLS_CERT_OK=false
        printf "  %-20s ❌ %s\n" \
            "TLS 证书:" \
            "连接失败或将在 ${TLS_CERT_MIN_VALID_HOURS} 小时内到期"
    fi
fi

# --- 系统负载 ---
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
CORES=$(nproc)
echo ""
printf "%-20s %s (核心数: %s)\n" "系统负载:" "${LOAD}" "${CORES}"

echo ""
echo "═══════════════════════════════════════════"

# --- 告警模式 ---
if [ "$ALERT_MODE" = true ]; then
    ALERTS=""
    if (( $(echo "${CPU_USAGE} > ${CPU_THRESHOLD}" | bc -l) )); then
        ALERTS="${ALERTS}CPU:${CPU_USAGE}% "
    fi
    if (( $(echo "${MEM_PCT} > ${MEM_THRESHOLD}" | bc -l) )); then
        ALERTS="${ALERTS}MEM:${MEM_PCT}% "
    fi
    if [ "${DISK_PCT}" -gt "${DISK_THRESHOLD}" ]; then
        ALERTS="${ALERTS}DISK:${DISK_PCT}% "
    fi
    ALERTS="${ALERTS}${CONTAINER_ALERTS}"
    if [ "${BACKEND_OK}" = false ]; then
        ALERTS="${ALERTS}BACKEND:UNHEALTHY "
    fi
    if [ "${PUBLIC_OK}" = false ]; then
        ALERTS="${ALERTS}PUBLIC:UNHEALTHY "
    fi
    if [ "${AGENT_READY}" = false ]; then
        ALERTS="${ALERTS}AGENT:NOT_READY "
    fi
    if [ "${TLS_CERT_OK}" = false ]; then
        ALERTS="${ALERTS}TLS:CERT "
    fi
    if [ -n "${ALERTS}" ]; then
        echo "[ALERT] 健康告警: ${ALERTS}"
        exit 2
    fi
fi
