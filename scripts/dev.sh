#!/usr/bin/env bash
# 一条命令起本地开发环境：make dev
#   装依赖（原子、幂等）→ 起后端 → 等健康检查 → 起前端 → 冒烟确认熔断器接口
# 任一环节失败都会指出卡点并退出；Ctrl-C / 收到退出信号会整组带走前后端进程，
# 不留下孤儿 uvicorn / vite。
set -euo pipefail
# 开作业控制：让每个后台服务跑在独立进程组，退出时可以按进程组整组回收
set -m

source "$(dirname "$0")/common.sh"

LOG_DIR="$REPO_ROOT/.run-logs"
mkdir -p "$LOG_DIR"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"

# 依赖没装好先装，装好则 setup 内部自行跳过
bash "$REPO_ROOT/scripts/setup.sh"

SERVICE_PIDS=()
stop_services() {
  # 负 PID 表示向整个进程组发信号，确保 npm/vite、uvicorn 等子孙进程一起退出
  for pid in "${SERVICE_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill -TERM "-$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${SERVICE_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill -KILL "-$pid" 2>/dev/null || true
  done
}
cleanup() {
  log dev "停止前后端进程（整组回收）"
  stop_services
}
trap cleanup EXIT INT TERM

# ---------- 后端 ----------
STAGE="后端启动"
log "$STAGE" "启动 FastAPI（日志：$BACKEND_LOG）"
(
  cd "$REPO_ROOT/backend"
  BACKEND_HOST="$BACKEND_HOST" BACKEND_PORT="$BACKEND_PORT" \
  FUSE_SEED_FILE="$FUSE_SEED_FILE" \
  ./run.sh >"$BACKEND_LOG" 2>&1
) &
BACKEND_PID=$!
SERVICE_PIDS+=("$BACKEND_PID")

log "$STAGE" "等待 $BACKEND_URL/api/health 就绪（最多 60 秒）"
if ! wait_for_url "$BACKEND_URL/api/health" 60 1; then
  fail "$STAGE" "后端 60 秒内未就绪，日志最后 20 行如下（完整日志：$BACKEND_LOG）：
$(tail -n 20 "$BACKEND_LOG" 2>/dev/null)"
fi
log "$STAGE" "后端已就绪：$BACKEND_URL"

# ---------- 前端 ----------
STAGE="前端启动"
log "$STAGE" "启动 Vite dev server（日志：$FRONTEND_LOG）"
(
  cd "$REPO_ROOT/frontend"
  FRONTEND_HOST="$FRONTEND_HOST" FRONTEND_PORT="$FRONTEND_PORT" \
  VITE_PROXY_TARGET="$VITE_PROXY_TARGET" \
  npm run dev >"$FRONTEND_LOG" 2>&1
) &
FRONTEND_PID=$!
SERVICE_PIDS+=("$FRONTEND_PID")

# Vite 起得来就会监听端口；探不到时把日志带出来
if ! wait_for_url "$FRONTEND_URL" 60 1; then
  fail "$STAGE" "前端 60 秒内未就绪，日志最后 20 行如下（完整日志：$FRONTEND_LOG）：
$(tail -n 20 "$FRONTEND_LOG" 2>/dev/null)"
fi
log "$STAGE" "前端已就绪：$FRONTEND_URL"

# ---------- 冒烟 ----------
log 冒烟 "自动确认熔断器列表接口可用、三种情形齐全、重复导入按编号覆盖"
if ! python3 "$REPO_ROOT/scripts/smoke.py" --base-url "$BACKEND_URL"; then
  fail 冒烟 "冒烟未通过，将停止服务，日志保留在 $LOG_DIR/{backend,frontend}.log 便于排查"
fi

cat <<EOF

$(printf '=%.0s' {1..64})
 本地环境已启动
   前端页面：$FRONTEND_URL
   后端接口：$BACKEND_URL/api/health
   熔断器列表：$BACKEND_URL/api/fuse
 日志：$LOG_DIR/{backend,frontend}.log
 Ctrl-C 停止全部服务
$(printf '=%.0s' {1..64})
EOF

wait
