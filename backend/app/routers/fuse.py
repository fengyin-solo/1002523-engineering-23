"""熔断器管理接口：维护熔断器，覆盖更换熔断、补充备件、记录更换等动作。"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query

from app.schemas import ActionResult, EntryPayload, PageResult
from app.seed_loader import SeedError
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


# 固定路径必须声明在 /{entry_id} 之前，否则 entry_id 的 int 转换会拦截 export、seed 等路径
@router.get("/export")
def export_entries() -> dict[str, Any]:
    """导出熔断器管理清单：返回当前过滤条件下的全量数据。"""
    items, total = service.list_entries(page=1, size=10000)
    return {"module": "fuse", "total": total, "items": items}


@router.get("/seed/snapshot")
def seed_snapshot() -> dict[str, Any]:
    """导出熔断器种子基线快照：用于上线前后比对两份数据是否一致。"""
    items, total = service.list_entries(page=1, size=10000)
    return {"module": "fuse", "total": total, "items": items}


@router.post("/seed/reload", response_model=ActionResult)
def reload_seed() -> ActionResult:
    """重新导入熔断器示例数据。

    按熔断器编号整条覆盖（upsert），重复执行不会追加；上线前后可用它把数据
    恢复成与本地一致的基线。数据文件缺失或非法时返回 500 并说明卡在哪一环。
    """
    try:
        stats = service.reseed()
    except SeedError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return ActionResult(
        ok=True,
        message=(
            f"熔断器示例数据已导入：共 {stats['total']} 条，"
            f"新增 {stats['inserted']} 条，按编号覆盖 {stats['updated']} 条"
        ),
    )


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
