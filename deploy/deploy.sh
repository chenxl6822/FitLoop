#!/bin/bash
# =============================================
# FitLoop — 一键部署脚本
# 使用: bash deploy/deploy.sh
# 第一次部署和后续更新都执行这个脚本
# =============================================

set -euo pipefail

cd "$(dirname "$0")/.."
echo "📍 工作目录: $(pwd)"

# --- 颜色输出 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 检查必要文件 ---
ENV_FILE="${FITLOOP_ENV_FILE:-.env}"
if [ ! -f "$ENV_FILE" ]; then
    if [ "$ENV_FILE" = ".env" ] && [ -f "deploy/.env.production" ]; then
        log_warn ".env 不存在，从 deploy/.env.production 复制"
        cp deploy/.env.production "$ENV_FILE"
        log_error "请先编辑 .env 文件，填入真实的密码和密钥！"
        log_error "  执行: nano .env"
        exit 1
    else
        log_error "找不到环境文件: $ENV_FILE"
        log_error "请先创建: cp deploy/.env.example .env"
        exit 1
    fi
fi

# Read only the values needed by this script. Do not source .env: passwords can
# contain shell metacharacters and a dotenv file is not an executable script.
read_env_value() {
    sed -n "s/^${1}=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'
}

FITLOOP_TLS_ENABLED="${FITLOOP_TLS_ENABLED:-$(read_env_value FITLOOP_TLS_ENABLED)}"
FITLOOP_HTTP_COMPAT_ENABLED="${FITLOOP_HTTP_COMPAT_ENABLED:-$(read_env_value FITLOOP_HTTP_COMPAT_ENABLED)}"
FITLOOP_TLS_CERT_FILE="${FITLOOP_TLS_CERT_FILE:-$(read_env_value FITLOOP_TLS_CERT_FILE)}"
FITLOOP_TLS_KEY_FILE="${FITLOOP_TLS_KEY_FILE:-$(read_env_value FITLOOP_TLS_KEY_FILE)}"
FITLOOP_PUBLIC_BASE_URL="${FITLOOP_PUBLIC_BASE_URL:-$(read_env_value FITLOOP_PUBLIC_BASE_URL)}"
FITLOOP_AGENT_ENABLED="${FITLOOP_AGENT_ENABLED:-$(read_env_value FITLOOP_AGENT_ENABLED)}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-$(read_env_value DEEPSEEK_API_KEY)}"
FITLOOP_AGENT_SERVICE_KEY="${FITLOOP_AGENT_SERVICE_KEY:-$(read_env_value FITLOOP_AGENT_SERVICE_KEY)}"

# --- 检查 Docker ---
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装！请先安装 Docker"
    log_info "   curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# --- 检查 Docker Compose ---
COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null; then
    if docker-compose --version &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_error "Docker Compose 未安装！"
        exit 1
    fi
fi

log_info "Docker: $(docker --version)"
log_info "Compose: $($COMPOSE_CMD version)"

# --- 选择 Compose 文件 ---
ENV="${1:-cn}"

case "$ENV" in
    cn|china)
        COMPOSE_ARGS="-f deploy/docker-compose.yml -f deploy/docker-compose.cn.yml"
        log_info "使用国内镜像加速 (docker-compose.yml + docker-compose.cn.yml)"
        ;;
    prebuilt)
        COMPOSE_ARGS="-f deploy/docker-compose.yml -f deploy/docker-compose.prebuilt.yml"
        log_info "使用预构建 JAR（需先 mvn package）"
        ;;
    host)
        COMPOSE_ARGS="-f deploy/docker-compose.host.yml"
        log_info "使用 Docker Desktop 本地模式"
        ;;
    *)
        COMPOSE_ARGS="-f deploy/docker-compose.yml"
        log_info "使用默认配置"
        ;;
esac

if [ "${FITLOOP_TLS_ENABLED:-false}" = "true" ]; then
    if [ -z "${FITLOOP_TLS_CERT_FILE:-}" ] || [ ! -f "${FITLOOP_TLS_CERT_FILE}" ]; then
        log_error "FITLOOP_TLS_CERT_FILE 不存在或不是文件"
        exit 1
    fi
    if [ -z "${FITLOOP_TLS_KEY_FILE:-}" ] || [ ! -f "${FITLOOP_TLS_KEY_FILE}" ]; then
        log_error "FITLOOP_TLS_KEY_FILE 不存在或不是文件"
        exit 1
    fi
    if [[ "${FITLOOP_PUBLIC_BASE_URL:-}" != https://* ]]; then
        log_error "启用 TLS 时 FITLOOP_PUBLIC_BASE_URL 必须使用 https://"
        exit 1
    fi
    COMPOSE_ARGS="$COMPOSE_ARGS -f deploy/docker-compose.tls.yml"
    log_info "启用 HTTPS Compose 覆盖配置"

    if [ "${FITLOOP_HTTP_COMPAT_ENABLED:-true}" = "false" ]; then
        COMPOSE_ARGS="$COMPOSE_ARGS -f deploy/docker-compose.https-only.yml"
        log_warn "HTTP API 兼容窗口已关闭；明文 /api/ 将返回 426"
    else
        log_warn "HTTP API 兼容窗口仍开启；确认旧客户端退出后再关闭"
    fi
elif [ "${FITLOOP_HTTP_COMPAT_ENABLED:-true}" = "false" ]; then
    log_error "关闭 HTTP API 兼容窗口前必须先启用 TLS"
    exit 1
fi

if [ "${FITLOOP_AGENT_ENABLED:-true}" = "true" ]; then
    if [ -z "${DEEPSEEK_API_KEY:-}" ] || [[ "${DEEPSEEK_API_KEY}" == replace-with-* ]]; then
        log_error "Agent 已启用，但 DEEPSEEK_API_KEY 尚未配置"
        exit 1
    fi
    if [ -z "${FITLOOP_AGENT_SERVICE_KEY:-}" ] ||
       [[ "${FITLOOP_AGENT_SERVICE_KEY}" == replace-with-* ]]; then
        log_error "Agent 已启用，但 FITLOOP_AGENT_SERVICE_KEY 尚未配置"
        exit 1
    fi
else
    log_warn "Agent worker 已禁用；核心 API 和下载站仍会正常启动"
fi

# --- 构建并启动 ---
log_info "正在构建和启动服务..."
$COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" up -d --build

# --- 等待后端就绪 ---
BACKEND_HEALTH_URL="${FITLOOP_BACKEND_HEALTH_URL:-http://localhost:8080/actuator/health}"
HEALTH_ATTEMPTS="${FITLOOP_DEPLOY_HEALTH_ATTEMPTS:-30}"
HEALTH_INTERVAL_SECONDS="${FITLOOP_DEPLOY_HEALTH_INTERVAL_SECONDS:-2}"

if ! [[ "${HEALTH_ATTEMPTS}" =~ ^[1-9][0-9]*$ ]]; then
    log_error "FITLOOP_DEPLOY_HEALTH_ATTEMPTS 必须是正整数"
    exit 1
fi
if ! [[ "${HEALTH_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]]; then
    log_error "FITLOOP_DEPLOY_HEALTH_INTERVAL_SECONDS 必须是非负整数"
    exit 1
fi

log_info "等待后端启动..."
BACKEND_READY=false
for i in $(seq 1 "${HEALTH_ATTEMPTS}"); do
    if curl -sf "${BACKEND_HEALTH_URL}" > /dev/null 2>&1; then
        echo ""
        log_info "✅ 后端启动成功！"
        BACKEND_READY=true
        break
    fi
    echo -n "."
    if [ "${HEALTH_INTERVAL_SECONDS}" -gt 0 ]; then
        sleep "${HEALTH_INTERVAL_SECONDS}"
    fi
done

if [ "${BACKEND_READY}" = false ]; then
    echo ""
    log_error "后端未在健康检查窗口内就绪，部署判定失败"
    $COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" ps || true
    $COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" \
        logs --tail=100 backend || true
    exit 1
fi

# --- 等待公网入口就绪 ---
PUBLIC_BASE_URL="${FITLOOP_PUBLIC_BASE_URL:-http://localhost}"
PUBLIC_HEALTH_URL="${FITLOOP_PUBLIC_HEALTH_URL:-${PUBLIC_BASE_URL%/}/actuator/health}"

log_info "等待公网入口启动..."
PUBLIC_READY=false
for i in $(seq 1 "${HEALTH_ATTEMPTS}"); do
    if curl -sf "${PUBLIC_HEALTH_URL}" > /dev/null 2>&1; then
        echo ""
        log_info "✅ 公网入口启动成功！"
        PUBLIC_READY=true
        break
    fi
    echo -n "."
    if [ "${HEALTH_INTERVAL_SECONDS}" -gt 0 ]; then
        sleep "${HEALTH_INTERVAL_SECONDS}"
    fi
done

if [ "${PUBLIC_READY}" = false ]; then
    echo ""
    log_error "公网入口未在健康检查窗口内就绪，部署判定失败"
    $COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" ps || true
    $COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" \
        logs --tail=100 nginx || true
    exit 1
fi

# --- 清理旧镜像 ---
log_info "清理未使用的 Docker 镜像..."
docker image prune -f 2>/dev/null || true

# --- 输出状态 ---
echo ""
log_info "📊 服务状态:"
$COMPOSE_CMD $COMPOSE_ARGS --env-file "$ENV_FILE" ps

echo ""
log_info "📝 查看日志: $COMPOSE_CMD $COMPOSE_ARGS --env-file $ENV_FILE logs -f"
log_info "🌐 API 地址: http://localhost:8080/api/"
log_info "🏥 健康检查: http://localhost:8080/actuator/health"
if [ "${FITLOOP_TLS_ENABLED:-false}" = "true" ]; then
    log_info "🔒 公网地址: ${FITLOOP_PUBLIC_BASE_URL}"
fi
if [ "${FITLOOP_AGENT_ENABLED:-true}" = "true" ]; then
    if curl -sf http://127.0.0.1:8090/ready > /dev/null 2>&1; then
        log_info "🤖 Agent readiness: READY"
    else
        log_warn "🤖 Agent 未就绪，但不影响核心 API；请检查 agent-service 日志"
    fi
fi
log_info "✅ 部署完成！"
