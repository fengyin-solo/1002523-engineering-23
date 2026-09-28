#!/usr/bin/env bash
# scripts/smoke.sh：冒烟检查，自动确认熔断器接口可用。
#
# 检查三项：
#   1. GET /api/health 服务存活；
#   2. GET /api/fuse 能返回熔断器列表，且示例数据覆盖
#      正常 / 已熔断 / 备件不足 三种情形；
#   3. POST /api/fuse/import 再查一次：按熔断器编号覆盖，记录总数不变，
#      确认重复导入不会追加。
#
# 可独立跑（make smoke），也被 dev.sh / deploy.sh 复用。
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_config
trap on_error ERR

BASE="http://${BACKEND_HOST}:${BACKEND_PORT}"
CURRENT_STEP="冒烟检查：等待后端就绪"

# 能直接调后端就优先用后端 venv 里的 python，否则退回系统 python3
PY=python3
if [ -x "$ROOT/backend/.venv/bin/python" ]; then
  PY="$ROOT/backend/.venv/bin/python"
fi
command -v "$PY" >/dev/null 2>&1 || {
  echo "✗ 冒烟检查需要 Python 解析接口返回的 JSON，但未找到可用的 python3" >&2
  exit 127
}

# 服务可能还没起来，给 30 秒
wait_for_url "$BACKEND_HOST" "$BACKEND_PORT" "/api/health" 30
ok "健康检查通过：GET /api/health"

CURRENT_STEP="冒烟检查：熔断器列表与三种状态"
"$PY" - "$BASE" <<'PYEOF'
import json
import sys
import urllib.error
import urllib.request

base = sys.argv[1]
EXPECTED_STATUSES = {"正常", "已熔断", "备件不足"}
EXPECTED_CODES = {"FUSE-0001", "FUSE-0002", "FUSE-0003"}


def get(path):
    with urllib.request.urlopen(base + path, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))


def post(path):
    req = urllib.request.Request(base + path, data=b"", method="POST")
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))


try:
    page = get("/api/fuse?page=1&size=200")
except urllib.error.URLError as exc:
    print(f"冒烟失败：GET /api/fuse 请求不到后端（{exc}）", file=sys.stderr)
    sys.exit(1)

items = page.get("items")
assert isinstance(items, list), f"/api/fuse 返回缺少 items 列表：{page!r}"
assert page.get("total") == len(items), f"total({page.get('total')}) 与 items 条数({len(items)}) 不一致"

codes = {row.get("熔断器编号") for row in items}
statuses = {row.get("status") for row in items}
missing_codes = EXPECTED_CODES - codes
missing_statuses = EXPECTED_STATUSES - statuses
assert not missing_codes, f"熔断器列表缺少编号 {sorted(missing_codes)}，当前：{sorted(codes)}"
assert not missing_statuses, (
    f"示例数据未覆盖三种情形，缺少状态 {sorted(missing_statuses)}，当前状态：{sorted(statuses)}"
)

before = page["total"]
result = post("/api/fuse/import")
assert result.get("ok") is True, f"导入接口返回失败：{result}"
after = get("/api/fuse?page=1&size=200")["total"]
assert after == before, (
    f"重复导入追加了记录：导入前 {before} 条，导入后 {after} 条（应当按熔断器编号覆盖）"
)

print(f"  ✓ GET /api/fuse 返回 {before} 条熔断器，三种状态齐全")
print(f"  ✓ 重复导入按编号覆盖（新增 {result.get('created', 0)} 条，"
      f"覆盖 {result.get('updated', 0)} 条），总数仍为 {after}")
PYEOF

echo "冒烟检查全部通过 ✓"
