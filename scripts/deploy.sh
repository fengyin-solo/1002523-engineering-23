#!/usr/bin/env bash
# scripts/deploy.sh：部署流程（docker compose）。
#
# 与本地开发共用同一份配置来源 config/settings.env（端口、环境标识、
# 种子数据路径）和同一份种子数据 backend/data/fuse.json，镜像构建时把
# 数据文件原样打进镜像，启动时由后端同一段加载/导入逻辑处理，因此
# 上线前后跑出来的熔断器数据与本地一致。
#
# 流程：前置检查 → 构建镜像 → 起容器 → 冒烟检查。任一步失败立即停在
# 该环并打印原始错误；构建失败不会动到正在运行的旧容器。
#
# 用法：./scripts/deploy.sh   或   make deploy
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_config
trap on_error ERR

export APP_ENV BACKEND_HOST BACKEND_PORT FRONTEND_HOST FRONTEND_PORT FUSE_SEED_FILE

step "1/3" "前置检查（docker / docker compose）"
if ! command -v docker >/dev/null 2>&1; then
  echo "✗ 缺少 docker 命令，部署机需要先安装 Docker Engine。" >&2
  exit 127
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "✗ 缺少 docker compose 子命令（需要 Docker Compose v2）。" >&2
  exit 127
fi
ok "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,)，compose v2"

step "2/3" "构建镜像并启动容器（配置来源：config/settings.env，APP_ENV=${APP_ENV}）"
[ -f "$ROOT/backend/${FUSE_SEED_FILE}" ] || {
  echo "✗ 熔断器示例数据缺失：backend/${FUSE_SEED_FILE}，无法保证部署数据与本地一致" >&2
  exit 1
}
# build 失败时不会有容器被替换，旧环境继续跑，不存在半套环境
docker compose -f "$ROOT/docker-compose.yml" --project-directory "$ROOT" build
docker compose -f "$ROOT/docker-compose.yml" --project-directory "$ROOT" up -d
ok "容器已启动：后端映射端口 ${BACKEND_PORT}，前端映射端口 ${FRONTEND_PORT}"

step "3/3" "部署后冒烟检查（与本地同一条 smoke 流程）"
"$ROOT/scripts/smoke.sh"

echo ""
echo "==============================================================="
echo " 部署完成：前端 http://${BACKEND_HOST}:${FRONTEND_PORT}/"
echo "          后端 http://${BACKEND_HOST}:${BACKEND_PORT}/api/health"
echo " 查看日志：docker compose -f docker-compose.yml logs -f"
echo " 停止服务：docker compose -f docker-compose.yml down"
echo "==============================================================="
