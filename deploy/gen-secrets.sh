#!/bin/bash
# FitLoop — 生成生产环境密钥
# 用法: bash deploy/gen-secrets.sh
#
# 输出可直接复制到 .env.production

echo "========================================="
echo " FitLoop 密钥生成器"
echo "========================================="
echo ""

# 生成 JWT Secret (64字节 base64)
JWT_SECRET=$(openssl rand -base64 64)
echo "FITLOOP_JWT_SECRET=${JWT_SECRET}"
echo ""

# 生成数据库密码 (32字节随机)
DB_PASS=$(openssl rand -base64 32 | tr -d '=' | tr '/+' '_-')
echo "MYSQL_PASSWORD=${DB_PASS}"
echo "MYSQL_ROOT_PASSWORD=${DB_PASS}-root"
echo ""

# Java Backend 与 Agent Service 间使用两把独立密钥
AGENT_SERVICE_KEY=$(openssl rand -base64 48)
AGENT_DELEGATION_SECRET=$(openssl rand -base64 48)
echo "FITLOOP_AGENT_SERVICE_KEY=${AGENT_SERVICE_KEY}"
echo "FITLOOP_AGENT_DELEGATION_SECRET=${AGENT_DELEGATION_SECRET}"
echo "FITLOOP_ADMIN_BOOTSTRAP_ACCOUNT="
echo "FITLOOP_ADMIN_BOOTSTRAP_NICKNAME="
echo ""

echo "========================================="
echo " 复制以上值到 .env.production 文件"
echo "========================================="
