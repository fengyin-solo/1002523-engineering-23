#!/usr/bin/env bash
# scripts/seed.sh：把熔断器示例数据重复导入到「正在运行」的后端。
#
# 语义：按熔断器编号覆盖（upsert），不是追加。改了 backend/data/fuse.json
# 后不想重启服务，就跑这个脚本；连跑任意次数，熔断器列表都不会出现重复编号。
#
# 用法：./scripts/seed.sh   或   make seed
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_config
trap on_error ERR

SEED_FILE="$ROOT/backend/${FUSE_SEED_FILE}"
CURRENT_STEP="校验熔断器示例数据文件"

[ -f "$SEED_FILE" ] || {
  echo "✗ 示例数据文件不存在：$SEED_FILE" >&2
  exit 1
}

CURRENT_STEP="检查后端是否在运行"
if ! curl -fsS --max-time 3 "http://${BACKEND_HOST}:${BACKEND_PORT}/api/health" >/dev/null; then
  echo "✗ 后端没有在 http://${BACKEND_HOST}:${BACKEND_PORT} 运行，导入无从落库。" >&2
  echo "  先执行 ./scripts/dev.sh（或 make dev）起本地环境，再重新导入。" >&2
  exit 1
fi

CURRENT_STEP="调用 POST /api/fuse/import 按编号覆盖导入"
RESULT_JSON="$(mktemp -t fuse-import.XXXXXX.json)"
trap 'rm -f "$RESULT_JSON"' EXIT
HTTP_CODE=$(
  curl -sS -o "$RESULT_JSON" -w "%{http_code}" \
    -X POST "http://${BACKEND_HOST}:${BACKEND_PORT}/api/fuse/import"
)
if [ "$HTTP_CODE" != "200" ]; then
  echo "✗ 导入接口返回 HTTP ${HTTP_CODE}，响应内容：" >&2
  cat "$RESULT_JSON" >&2 || true
  echo "" >&2
  exit 1
fi

PY=python3
[ -x "$ROOT/backend/.venv/bin/python" ] && PY="$ROOT/backend/.venv/bin/python"
"$PY" - "$RESULT_JSON" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    result = json.load(fh)
print(f"✓ {result.get('message', '导入完成')}，当前熔断器共 {result.get('total')} 条")
PYEOF
