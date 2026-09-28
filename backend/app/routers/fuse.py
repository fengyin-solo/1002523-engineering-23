"""熔断器管理接口：维护熔断器，覆盖更换熔断、补充备件、记录更换等动作。"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query

from app.schemas import ActionResult, EntryPayload, PageResult
from app.seed import load_fuse_seed_rows
from app.services.fuse import FuseService

router = APIRouter(prefix="/api/fuse", tags=["熔断器管理"])

service = FuseService()

LIST_FIELDS = ["熔断器编号", "额定电流", "安装位置", "保护范围", "熔断记录", "更换日期", "备件存量", "熔断器状态"]
STATUSES = ["正常", "已熔断", "备件不足", "已更换"]


@router.get("", response_model=PageResult[dict])
def list_entries(
    keyword: str | None = Query(default=None, description="按熔断器编号检索"),
    status: str | None = Query(default=None, description="正常、已熔断、备件不足、已更换"),
    page: int = 1,
    size: int = 20,
) -> PageResult[dict]:
    """按熔断器编号与状态过滤熔断器管理列表；没有数据时返回空页，不报错。"""
    if size > 200:
        raise HTTPException(status_code=400, detail="每页最多 200 条，请缩小分页范围")
    items, total = service.list_entries(keyword=keyword, status=status, page=page, size=size)
    return PageResult(items=items, total=total, page=page, size=size)


@router.get("/{entry_id}", response_model=dict)
def get_entry(entry_id: int) -> dict:
    """读取单条熔断器明细；不存在时给出可读的错误说明。"""
    entry = service.get_entry(entry_id)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"熔断器 {entry_id} 不存在或已归档")
    return entry


@router.post("", response_model=ActionResult)
def create_entry(payload: EntryPayload) -> ActionResult:
    """登记一条熔断器，缺字段时说明原因而不是静默丢弃。"""
    entry, missing = service.create_entry(payload.values)
    if missing:
        return ActionResult(ok=False, message=f"缺少必填字段：{'、'.join(missing)}")
    return ActionResult(ok=True, message="熔断器已登记", entry=entry)


@router.post("/{entry_id}/actions", response_model=ActionResult)
def run_action(entry_id: int, payload: EntryPayload) -> ActionResult:
    """对单条熔断器执行更换熔断、补充备件、记录更换；不允许的动作会被拦下并说明原因。"""
    action = str(payload.values.get("action") or "").strip()
    entry, message = service.run_action(entry_id, action)
    if entry is None:
        return ActionResult(ok=False, message=message)
    return ActionResult(ok=True, message=message, entry=entry)


@router.get("/export")
def export_entries() -> dict[str, Any]:
    """导出熔断器管理清单：返回当前过滤条件下的全量数据。"""
    items, total = service.list_entries(page=1, size=10000)
    return {"module": "fuse", "total": total, "items": items}


@router.post("/import")
def import_entries() -> dict[str, Any]:
    """从服务器端种子文件（FUSE_SEED_FILE）重新导入熔断器示例数据。

    按熔断器编号整行覆盖，重复导入不会追加重复记录；文件缺失/格式错误会
    直接 500 并说明卡在哪，不返回一份看似成功的空结果。
    """
    try:
        rows = load_fuse_seed_rows()
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    created, updated, bad_rows = service.import_entries(rows)
    if bad_rows:
        raise HTTPException(
            status_code=400,
            detail=f"种子文件第 {'、'.join(bad_rows)} 行缺少熔断器编号，已整批放弃导入",
        )
    total = service.list_entries(page=1, size=10000)[1]
    return {
        "ok": True,
        "message": f"熔断器示例数据已按编号覆盖导入（新增 {created} 条，覆盖 {updated} 条）",
        "created": created,
        "updated": updated,
        "total": total,
    }
