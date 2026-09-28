"""熔断器管理业务规则：状态流转、字段校验与筛选口径都收在这里。"""
from __future__ import annotations

from typing import Any

from app.config import settings
from app.seed_loader import SeedError, read_seed_rows, upsert_rows
from app.store import store

MODULE = "fuse"
REQUIRED_FIELDS = ["熔断器编号", "额定电流", "安装位置"]
STATUS_ORDER = ["正常", "已熔断", "备件不足", "已更换"]
ACTION_RULES = {"更换熔断": "已熔断", "补充备件": "正常", "记录更换": "已更换"}
NEGATIVE_ACTIONS = []


class FuseService:
    def list_entries(
        self,
        *,
        keyword: str | None = None,
        status: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict[str, Any]], int]:
        rows = store.rows(MODULE)
        if keyword:
            rows = [row for row in rows if keyword in str(row.get("熔断器编号", ""))]
        if status:
            rows = [row for row in rows if row.get("status") == status]
        total = len(rows)
        start = max(page - 1, 0) * size
        return rows[start:start + size], total

    def get_entry(self, entry_id: int) -> dict[str, Any] | None:
        return store.find(MODULE, entry_id)

    def create_entry(self, values: dict[str, Any]) -> tuple[dict[str, Any] | None, list[str]]:
        missing = [field for field in REQUIRED_FIELDS if not str(values.get(field) or "").strip()]
        if missing:
            return None, missing
        rows = store.rows(MODULE)
        entry = {"id": max((int(row.get("id", 0)) for row in rows), default=0) + 1}
        entry.update({field: values.get(field) for field in REQUIRED_FIELDS})
        entry["status"] = STATUS_ORDER[0]
        entry["pending"] = True
        entry["abnormal"] = False
        rows.append(entry)
        return entry, []

    def run_action(self, entry_id: int, action: str) -> tuple[dict[str, Any] | None, str]:
        entry = store.find(MODULE, entry_id)
        if entry is None:
            return None, f"熔断器 {entry_id} 不存在或已归档"
        if action not in ACTION_RULES:
            return None, f"动作「{action}」不属于熔断器管理可执行范围"
        target = ACTION_RULES[action]
        if target not in STATUS_ORDER:
            return None, f"目标状态「{target}」不在允许的状态序列里"
        entry["status"] = target
        entry["pending"] = target != STATUS_ORDER[-1]
        entry["abnormal"] = action in NEGATIVE_ACTIONS
        return entry, f"熔断器已{action}"

    def reseed(self, seed_file: str | None = None) -> dict[str, Any]:
        """重新导入熔断器示例数据：按熔断器编号覆盖，不追加。

        启动时和上线后调用的是同一个方法，保证两边数据口径一致。
        """
        seed_rows = read_seed_rows(seed_file or settings.fuse_seed_file)
        rows, stats = upsert_rows(store.rows(MODULE), seed_rows)
        store.replace_rows(MODULE, rows)
        return {"total": len(rows), **stats}
