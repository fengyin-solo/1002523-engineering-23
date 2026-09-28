#!/usr/bin/env bash
# 根据熔断器种子文件生成基线快照（供上线后比对），不需要启动服务。
# 快照逻辑与冒烟脚本、服务启动装载走的是同一份 app.seed_loader。
set -euo pipefail
source "$(dirname "$0")/common.sh"

SNAPSHOT_FILE="${SNAPSHOT_FILE:-$REPO_ROOT/backend/data/fuse-snapshot.json}"

cd "$REPO_ROOT/backend"
FUSE_SEED_FILE="$FUSE_SEED_FILE" .venv/bin/python - "$SNAPSHOT_FILE" <<'PY'
import json
import sys

from app.seed_loader import read_seed_rows
from app.config import settings

snapshot_path = sys.argv[1]
rows = read_seed_rows(settings.fuse_seed_file)
fields = [
    "熔断器编号", "status", "额定电流", "安装位置", "保护范围",
    "熔断记录", "更换日期", "备件存量", "熔断器状态",
]
snapshot = sorted(
    ({key: row.get(key) for key in fields} for row in rows),
    key=lambda row: str(row["熔断器编号"]),
)
with open(snapshot_path, "w", encoding="utf-8") as fh:
    json.dump(snapshot, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print(f"已生成熔断器基线快照：{snapshot_path}（{len(snapshot)} 条）")
PY
