#!/bin/bash
# =============================================
# FitLoop — 一键部署脚本
# 使用: bash deploy/deploy.sh
# 第一次部署和后续更新都执行这个脚本
# =============================================

set -e

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
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "deploy/.env.production" ]; then
        log_warn ".env 不存在，从 deploy/.env.production 复制"
        cp deploy/.env.production .env
        log_error "请先编辑 .env 文件，填入真实的密码和密钥！"
        log_error "  执行: nano .env"
        exit 1
    else
        log_error "找不到 .env 文件！"
        log_error "请先创建: cp deploy/.env.example .env"
        exit 1
    fi
fi

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

# --- 拉取最新代码（如果有 git） ---
if [ -d ".git" ]; then
    log_info "拉取最新代码..."
    git pull --rebase 2>/dev/null || log_warn "git pull 失败，跳过（可能无网络或无远程）"
fi

# --- 构建并启动 ---
log_info "正在构建和启动服务..."
$COMPOSE_CMD $COMPOSE_ARGS --env-file .env up -d --build

# --- 等待后端就绪 ---
log_info "等待后端启动..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; then
        echo ""
        log_info "✅ 后端启动成功！"
        break
    fi
    echo -n "."
    sleep 2
done

if ! curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo ""
    log_warn "⚠️  后端未在 60 秒内就绪，请检查日志："
    log_info "  $COMPOSE_CMD $COMPOSE_ARGS --env-file $ENV_FILE logs -f backend"
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
log_info "✅ 部署完成！"
