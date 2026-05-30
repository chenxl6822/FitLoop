#!/bin/bash
# =============================================
# FitLoop — 服务器健康检查
# 用法: bash deploy/monitor.sh
#       bash deploy/monitor.sh --alert  # 超过阈值时输出告警
# =============================================

set -e

cd "$(dirname "$0")/.."

# --- 阈值 ---
CPU_THRESHOLD=80       # CPU 使用率 %
MEM_THRESHOLD=85       # 内存使用率 %
DISK_THRESHOLD=90      # 磁盘使用率 %

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
if command -v docker &> /dev/null; then
    for SERVICE in fitloop-mysql fitloop-redis fitloop-backend fitloop-nginx; do
        STATUS=$(docker ps --filter "name=${SERVICE}" --format "{{.Status}}" 2>/dev/null || echo "未运行")
        if echo "${STATUS}" | grep -q "Up"; then
            UPTIME=$(echo "${STATUS}" | sed 's/Up //')
            printf "  %-20s ✅ %s\n" "${SERVICE}:" "${UPTIME}"
        else
            if docker ps -a --filter "name=${SERVICE}" --format "{{.Names}}" 2>/dev/null | grep -q "${SERVICE}"; then
                printf "  %-20s ❌ 已停止\n" "${SERVICE}:"
            else
                printf "  %-20s ➖ 未创建\n" "${SERVICE}:"
            fi
        fi
    done
else
    echo "  Docker 未安装"
fi

# --- API 健康检查 ---
echo ""
echo "--- API 健康 ---"
for PORT in 8080 80; do
    RESP=$(curl -sf -w "%{http_code}" -o /dev/null "http://localhost:${PORT}/actuator/health" 2>/dev/null || true)
    if [ "${RESP}" = "200" ]; then
        printf "  %-20s ✅ %s\n" "端口 ${PORT}:" "响应 200"
    else
        printf "  %-20s ❌ %s\n" "端口 ${PORT}:" "无响应 (${RESP})"
    fi
done

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
    if [ -n "${ALERTS}" ]; then
        echo "[ALERT] 资源告警: ${ALERTS}"
        exit 2
    fi
fi
