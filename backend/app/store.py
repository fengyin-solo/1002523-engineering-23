"""内存数据仓库：给每个业务模块准备一份可筛选、可流转的示例数据。

真实项目里这里会换成数据库访问层；当前实现只依赖标准库，保证克隆下来就能起。
"""
from __future__ import annotations

from typing import Any

from app.seed import SEED_ROWS


class Store:
    def __init__(self) -> None:
        self._tables: dict[str, list[dict[str, Any]]] = {
            name: [dict(row) for row in rows] for name, rows in SEED_ROWS.items()
        }

    def module_names(self) -> list[str]:
        return sorted(self._tables)

    def rows(self, module: str) -> list[dict[str, Any]]:
        return self._tables.setdefault(module, [])

    def find(self, module: str, entry_id: int) -> dict[str, Any] | None:
        for row in self.rows(module):
            if int(row.get("id", 0)) == entry_id:
                return row
        return None

    def upsert_rows(
        self,
        module: str,
        rows: list[dict[str, Any]],
        key: str,
    ) -> tuple[int, int]:
        """按业务编号覆盖导入：已存在编号整行替换，新编号追加。

        返回 (新增条数, 覆盖条数)。重复导入同一个文件的结果是幂等的，
        不会把同一个编号追加出多份记录。
        """
        table = self.rows(module)
        index: dict[str, int] = {
            str(existing.get(key, "")): pos for pos, existing in enumerate(table)
        }
        created = updated = 0
        for incoming in rows:
            marker = str(incoming.get(key, ""))
            if marker and marker in index:
                table[index[marker]] = dict(incoming)
                updated += 1
            else:
                table.append(dict(incoming))
                if marker:
                    index[marker] = len(table) - 1
                created += 1
        return created, updated

    def overview(self) -> dict[str, object]:
        modules: list[dict[str, object]] = []
        for name in self.module_names():
            rows = self.rows(name)
            modules.append({
                "name": name,
                "created": len(rows),
                "pending": sum(1 for row in rows if row.get("pending")),
                "abnormal": sum(1 for row in rows if row.get("abnormal")),
            })
        cards = [
            {"label": "业务模块", "value": len(modules)},
            {"label": "今日新增", "value": sum(int(item["created"]) for item in modules)},
            {"label": "待处理", "value": sum(int(item["pending"]) for item in modules)},
            {"label": "异常量", "value": sum(int(item["abnormal"]) for item in modules)},
        ]
        return {"cards": cards, "modules": modules}


store = Store()
