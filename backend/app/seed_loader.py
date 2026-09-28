"""熔断器示例数据装载器。

唯一数据来源是 backend/data/fuse-seed.json（路径可由 FUSE_SEED_FILE 覆盖）。
本地启动与部署启动都走 :func:`load_rows`，重复导入按「熔断器编号」upsert
覆盖，而不是追加：编号已存在就整条替换，不存在才插入，编号缺失的行一律拒绝。
这样同一套流程在本地和上线环境跑出来的熔断器数据保持一致。
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parent.parent

BUSINESS_KEY = "熔断器编号"
REQUIRED_FIELDS = [BUSINESS_KEY, "额定电流", "安装位置"]


class SeedError(RuntimeError):
    """种子数据缺失或内容非法时抛出，fail fast，避免起一套缺料的环境。"""


def resolve_seed_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if not path.is_absolute():
        path = BACKEND_ROOT / path
    return path


def read_seed_rows(seed_file: str) -> list[dict[str, Any]]:
    """读取并校验熔断器种子文件；任何问题都给出卡在哪一环的明确说明。"""
    path = resolve_seed_path(seed_file)
    if not path.exists():
        raise SeedError(f"熔断器示例数据文件不存在：{path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SeedError(f"熔断器示例数据不是合法 JSON（{path}）：第 {exc.lineno} 行第 {exc.colno} 列：{exc.msg}") from exc
    if not isinstance(data, list) or not data:
        raise SeedError(f"熔断器示例数据内容为空或格式不是列表：{path}")

    rows: list[dict[str, Any]] = []
    for index, row in enumerate(data, start=1):
        if not isinstance(row, dict):
            raise SeedError(f"熔断器示例数据第 {index} 条不是对象：{path}")
        missing = [field_name for field_name in REQUIRED_FIELDS if not str(row.get(field_name) or "").strip()]
        if missing:
            raise SeedError(
                f"熔断器示例数据第 {index} 条缺少必填字段：{'、'.join(missing)}（{path}）"
            )
        if not str(row.get("status") or "").strip():
            raise SeedError(f"熔断器示例数据第 {index} 条缺少 status（{path}）")
        rows.append(dict(row))

    keys = [str(row[BUSINESS_KEY]) for row in rows]
    dupes = sorted({key for key in keys if keys.count(key) > 1})
    if dupes:
        raise SeedError(f"熔断器示例数据存在重复编号：{'、'.join(dupes)}（{path}）")
    return rows


def upsert_rows(
    existing: list[dict[str, Any]], seed_rows: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """按熔断器编号把种子数据合并进现有列表（覆盖，不追加）。

    - 编号已存在：整条替换为种子数据，保留原 id；
    - 编号不存在：按种子数据的 id 插入（若 id 已被占用则顺延分配）；
    - 非种子里的旧编号不会被删除，保证手工登记的数据不丢。
    """
    rows = [dict(row) for row in existing]
    index_by_key = {str(row.get(BUSINESS_KEY)): i for i, row in enumerate(rows)}
    updated = inserted = 0

    for seed in seed_rows:
        key = str(seed[BUSINESS_KEY])
        incoming = dict(seed)
        if key in index_by_key:
            target = rows[index_by_key[key]]
            incoming["id"] = target.get("id")
            rows[index_by_key[key]] = incoming
            updated += 1
            continue

        wanted_id = incoming.get("id")
        used_ids = {int(row.get("id", 0)) for row in rows if str(row.get("id", "")).isdigit()}
        if not isinstance(wanted_id, int) or wanted_id in used_ids:
            incoming["id"] = max(used_ids, default=0) + 1
        rows.append(incoming)
        index_by_key[key] = len(rows) - 1
        inserted += 1

    return rows, {"inserted": inserted, "updated": updated}
