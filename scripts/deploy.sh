#!/usr/bin/env bash
# 一条命令完成部署并验证：make deploy
#   构建镜像 → 滚动启动 → 等待健康 → 与本地同一套冒烟 → 熔断器快照一致性比对
# 与本地脚本共用 scripts/common.sh、scripts/smoke.py 和同一份 .env 配置。
set -euo pipefail

source "$(dirname "$0")/common.sh"

SNAPSHOT_FILE="${SNAPSHOT_FILE:-$REPO_ROOT/backend/data/fuse-snapshot.json}"

STAGE="部署前置检查"
command -v docker >/dev/null 2>&1 || fail "$STAGE" "缺少 docker，请先安装 Docker 后重试。"
if ! docker compose version >/dev/null 2>&1; then
  fail "$STAGE" "缺少 docker compose 子命令，请升级到 Docker Compose v2。"
fi
log "$STAGE" "docker $(docker --version 2>/dev/null | sed 's/Docker version //')"

# 选择 compose 调用形式：--env-file 显式指定统一配置，避免依赖调用目录约定
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$REPO_ROOT/docker-compose.yml")

STAGE="镜像构建"
log "$STAGE" "构建 backend / frontend 镜像（失败请看上方构建日志，不会改动正在运行的容器）"
if ! "${COMPOSE[@]}" build; then
  fail "$STAGE" "镜像构建失败，现有运行环境未被改动。请根据上方日志定位是 Dockerfile、requirements.txt 还是 package.json 环节。"
fi

STAGE="启动服务"
log "$STAGE" "启动容器（compose up -d）"
if ! "${COMPOSE[@]}" up -d; then
  fail "$STAGE" "容器启动失败，请执行：docker compose logs 查看原因。"
fi

STAGE="健康检查"
log "$STAGE" "等待后端 /api/health 就绪（最多 90 秒）"
if ! wait_for_url "$BACKEND_URL/api/health" 90 1; then
  fail "$STAGE" "部署后后端未通过健康检查。请查看：docker compose logs backend"
fi
log "$STAGE" "后端健康检查通过：$BACKEND_URL/api/health"

STAGE="冒烟检查"
log "$STAGE" "执行与本地完全相同的熔断器冒烟检查，并比对基线快照 $SNAPSHOT_FILE"
if [ ! -f "$SNAPSHOT_FILE" ]; then
  fail "$STAGE" "缺少熔断器基线快照 $SNAPSHOT_FILE。请先在本地执行 make seed-snapshot 生成并提交，保证上线前后比对的是同一份数据。"
fi
if ! python3 "$REPO_ROOT/scripts/smoke.py" --base-url "$BACKEND_URL" --snapshot "$SNAPSHOT_FILE"; then
  fail "$STAGE" "线上冒烟/数据比对未通过，容器保持运行以便排查（docker compose logs）。脚本不会自动回滚：如需回退请重新部署上一版本镜像。"
fi

log 部署完成 "服务地址：前端 $FRONTEND_URL / 后端 $BACKEND_URL"
