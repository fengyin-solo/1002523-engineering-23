#!/usr/bin/env bash
# scripts/dev.sh：一键本地环境。
#
# 一条命令完成：前置检查 → 装后端依赖 → 装前端依赖 → 起后端并确认
# 三种状态的示例数据就位 → 冒烟检查 → 起前端，前后台都留驻，Ctrl+C 一起退出。
# 任何一步失败都会指出卡在哪一环；装到一半的依赖目录会被判为半成品清掉，
# 不会留下半套环境。
#
# 用法：./scripts/dev.sh   或   make dev
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_config
trap on_error ERR

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

# 运行中服务的 PID，退出时（正常退出或失败）一起收掉
PIDS=()
kill_children() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap kill_children EXIT

echo "本地开发环境（配置来源：config/settings.env，APP_ENV=${APP_ENV}）"

# ── 步骤 1：前置命令检查 ─────────────────────────────────────────────
step "1/6" "前置检查（python3 / node / npm / curl）"
require_command python3 "后端依赖 Python 3.10+ 建虚拟环境，请先安装 Python 3"
require_command node "前端依赖 Node 18+，请先安装 Node.js（建议 20 LTS）"
require_command npm "随 Node.js 一起安装，缺失请重装 Node.js"
require_command curl "冒烟检查依赖 curl 访问本地接口，请先安装"
ok "python3 $(python3 --version 2>&1)、node $(node --version)、npm $(npm --version)、curl 均可用"

# ── 步骤 2：后端依赖（venv + pip），半成品 venv 直接重建 ─────────────
step "2/6" "安装后端依赖（backend/.venv）"
BACKEND_DIR="$ROOT/backend"
VENV="$BACKEND_DIR/.venv"
MARKER="$VENV/.install-ok"
if [ -d "$VENV" ] && [ ! -f "$MARKER" ]; then
  echo "  .venv 存在但没有安装完成标记，判为半成品，删除后重建"
  rm -rf "$VENV"
fi
if [ ! -d "$VENV" ]; then
  # 建环境前确认 venv/ensurepip 可用（Debian 把 ensurepip 拆在 python3-venv 包里）
  python3 -c 'import venv, ensurepip' 2>/dev/null || {
    echo "✗ 当前 python3 不能创建虚拟环境（缺 venv/ensurepip 模块）。" >&2
    echo "  Debian/Ubuntu 请先安装：sudo apt install python3-venv（或 python3.$(python3 -c 'import sys;print(sys.version_info[1])')-venv）" >&2
    exit 1
  }
  # 建到一半（如缺 ensurepip）会留下残缺目录：当场清掉，避免半成品残留
  if ! python3 -m venv "$VENV"; then
    rm -rf "$VENV"
    echo "✗ 创建虚拟环境失败，已删除残缺目录 $VENV；按上方提示补齐系统包后重跑" >&2
    exit 1
  fi
fi
# pip 失败时 .venv 就是半套环境：清掉，下次重跑从零开始；成功时不刷屏
if ! "$VENV/bin/pip" install -q -r "$BACKEND_DIR/requirements.txt"; then
  echo "  pip 安装失败，删除未装完的 $VENV，避免留下半套环境" >&2
  rm -rf "$VENV"
  exit 1
fi
touch "$MARKER"
ok "后端依赖已安装，完成标记：$MARKER"

# ── 步骤 3：前端依赖（npm install），半成品 node_modules 重新安装 ────
step "3/6" "安装前端依赖（frontend/node_modules）"
FRONTEND_DIR="$ROOT/frontend"
NODE_MODULES="$FRONTEND_DIR/node_modules"
FRONT_MARKER="$NODE_MODULES/.install-ok"
if [ -d "$NODE_MODULES" ] && [ ! -f "$FRONT_MARKER" ]; then
  echo "  node_modules 存在但没有安装完成标记，判为半成品，删除后重装"
  rm -rf "$NODE_MODULES"
fi
# npm 失败时 node_modules 就是半套环境：清掉，下次重跑从零安装
if ! ( cd "$FRONTEND_DIR" && npm install ); then
  echo "  npm install 失败，删除未装完的 $NODE_MODULES，避免留下半套环境" >&2
  rm -rf "$NODE_MODULES"
  exit 1
fi
touch "$FRONT_MARKER"
ok "前端依赖已安装，完成标记：$FRONT_MARKER"

# ── 步骤 4：起后端，启动时自动加载 data/fuse.json（三种状态）────────
step "4/6" "启动后端（http://${BACKEND_HOST}:${BACKEND_PORT}）"
if [ ! -f "$BACKEND_DIR/${FUSE_SEED_FILE}" ]; then
  echo "✗ 熔断器示例数据缺失：backend/${FUSE_SEED_FILE}" >&2
  exit 1
fi
ensure_port_free "$BACKEND_PORT" "后端"
(
  cd "$BACKEND_DIR"
  BACKEND_PORT="$BACKEND_PORT" FUSE_SEED_FILE="$FUSE_SEED_FILE" APP_ENV="$APP_ENV" \
    "$VENV/bin/uvicorn" app.main:app --host "$BACKEND_HOST" --port "$BACKEND_PORT"
) >"$LOG_DIR/backend.log" 2>&1 &
PIDS+=("$!")
wait_for_url "$BACKEND_HOST" "$BACKEND_PORT" "/api/health" 30 "$LOG_DIR/backend.log"
ok "后端已就绪，示例数据在启动时按 data/fuse.json 加载"

# ── 步骤 5：冒烟检查（熔断器列表 + 重复导入覆盖不追加）──────────────
step "5/6" "冒烟检查（熔断器接口）"
"$ROOT/scripts/smoke.sh"

# ── 步骤 6：起前端 dev server ───────────────────────────────────────
step "6/6" "启动前端（http://${FRONTEND_HOST}:${FRONTEND_PORT}）"
ensure_port_free "$FRONTEND_PORT" "前端 dev server"
(
  cd "$FRONTEND_DIR"
  VITE_PROXY_TARGET="http://${BACKEND_HOST}:${BACKEND_PORT}" \
    ./node_modules/vite/bin/vite.js --host "$FRONTEND_HOST" --port "$FRONTEND_PORT"
) >"$LOG_DIR/frontend.log" 2>&1 &
PIDS+=("$!")
wait_for_url "$FRONTEND_HOST" "$FRONTEND_PORT" "/" 30 "$LOG_DIR/frontend.log"
CURRENT_STEP="本地环境运行中"
ok "前端已就绪"

echo ""
echo "==============================================================="
echo " 本地环境已全部就绪（数据来源与部署一致：backend/${FUSE_SEED_FILE}）"
echo "  前端：http://${FRONTEND_HOST}:${FRONTEND_PORT}/  （熔断器页：/fuse）"
echo "  后端：http://${BACKEND_HOST}:${BACKEND_PORT}/api/health"
echo "  日志：$LOG_DIR/backend.log、$LOG_DIR/frontend.log"
echo "  按 Ctrl+C 停止前后端全部服务"
echo "==============================================================="
wait
