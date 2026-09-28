#!/usr/bin/env bash
# 仅启动后端的手动入口（make backend）；一键本地环境请用 scripts/dev.sh。
# 同样加载共享配置 config/settings.env，避免与标准流程跑出不同端口/数据。
set -euo pipefail
cd "$(dirname "$0")"

if [ -f ../config/settings.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ../config/settings.env
  set +a
fi

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install -r requirements.txt
touch .venv/.install-ok
exec .venv/bin/uvicorn app.main:app --host "127.0.0.1" --port "${BACKEND_PORT:-8000}"
