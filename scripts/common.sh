#!/usr/bin/env bash
# 本地脚本与部署脚本共用的工具库：
#  - 统一配置来源：仓库根目录的 .env（首次自动由 .env.example 复制），
#    已存在的进程环境变量优先级最高，便于临时覆盖（如 BACKEND_PORT=18000）；
#  - 分阶段日志：每一步都打印当前在干什么，失败时能直接看出卡在哪一环。
# 本文件只被 source，不直接执行。

set -euo pipefail

log() { printf '\n\033[36m[%s]\033[0m %s\n' "$1" "$2"; }
fail() { printf '\n\033[31m[失败·%s]\033[0m %s\n' "$1" "$2" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
ENV_TEMPLATE="$REPO_ROOT/.env.example"

if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_TEMPLATE" "$ENV_FILE"
  log 配置 "未找到 .env，已按模板 .env.example 生成：$ENV_FILE"
fi

# 简单 KEY=VALUE 解析：导出未在环境中设置过的变量，不覆盖已有环境变量。
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|\#*) continue ;;
  esac
  key="${line%%=*}"
  value="${line#*=}"
  key="$(printf '%s' "$key" | tr -d '[:space:]')"
  [ -z "$key" ] && continue
  if [ -z "${!key:-}" ]; then
    export "$key=$value"
  fi
done < "$ENV_FILE"

: "${BACKEND_HOST:=127.0.0.1}"
: "${BACKEND_PORT:=8000}"
: "${FRONTEND_HOST:=127.0.0.1}"
: "${FRONTEND_PORT:=5173}"
: "${FUSE_SEED_FILE:=data/fuse-seed.json}"

BACKEND_URL="${BACKEND_URL:-http://${BACKEND_HOST}:${BACKEND_PORT}}"
# 0.0.0.0 只是监听占位，本机探测要走 127.0.0.1
case "$BACKEND_URL" in
  http://0.0.0.0:*|https://0.0.0.0:*)
    BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}"
    ;;
esac
FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:${FRONTEND_PORT}}"

# wait_for_url <地址> <最多尝试次数> <每次间隔秒>
wait_for_url() {
  local url="$1" tries="${2:-60}" interval="${3:-1}" n=1
  while [ "$n" -le "$tries" ]; do
    if curl -fsS --noproxy '*' -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep "$interval"
    n=$((n + 1))
  done
  return 1
}
