"""熔断器管理业务规则：状态流转、字段校验与筛选口径都收在这里。"""
from __future__ import annotations

from typing import Any

from app.store import store

MODULE = "fuse"
KEY_FIELD = "熔断器编号"
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

    def import_entries(
        self, rows: list[dict[str, Any]]
    ) -> tuple[int, int, list[str]]:
        """示例数据导入：按熔断器编号覆盖，而不是按 id 追加。

        缺熔断器编号的行不允许导入（整批失败并给出行号），避免产生无法再次覆盖
        的匿名记录。返回 (新增数, 覆盖数, 缺编号行号)。
        """
        bad_rows = [
            str(pos + 1)
            for pos, row in enumerate(rows)
            if not str(row.get(KEY_FIELD) or "").strip()
        ]
        if bad_rows:
            return 0, 0, bad_rows
        created, updated = store.upsert_rows(MODULE, rows, KEY_FIELD)
        return created, updated, bad_rows
