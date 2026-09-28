#!/usr/bin/env bash
# 后端本地启动：依赖未就绪时不自行摸索，直接指出该跑哪一步。
# 端口/监听地址来自统一配置（.env.example 为模板），可由环境变量覆盖。
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -x .venv/bin/python ]; then
  echo "[后端] 虚拟环境不存在或已损坏（比如从别的机器拷来的 .venv），请先在项目根目录执行：make setup" >&2
  exit 1
fi

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"
exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT"
