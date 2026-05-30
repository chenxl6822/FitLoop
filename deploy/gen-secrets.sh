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

# 生成管理密钥
ADMIN_KEY=$(openssl rand -hex 16)
echo "FITLOOP_ADMIN_KEY=${ADMIN_KEY}"
echo ""

echo "========================================="
echo " 复制以上值到 .env.production 文件"
echo "========================================="
