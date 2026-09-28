"""轨道交通信号检修管理平台 后端服务入口。

启动：uvicorn app.main:app --host 127.0.0.1 --port 8000
健康检查：GET /api/health
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import ROUTERS
from app.seed_loader import SeedError
from app.services.fuse import FuseService
from app.store import store


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动即装载熔断器示例数据：本地与部署同一入口、同一数据文件，
    # 装载按熔断器编号覆盖，可重复执行。数据有问题直接启动失败，不留下缺料环境。
    FuseService().reseed()
    yield


app = FastAPI(title="轨道交通信号检修管理平台", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for module in ROUTERS:
    app.include_router(module.router)


@app.get("/api/health")
def health() -> dict[str, object]:
    """健康检查：确认服务已经监听、示例数据已经就绪。"""
    return {"ok": True, "app": settings.app_name, "modules": len(store.module_names())}


@app.get("/api/overview")
def overview() -> dict[str, object]:
    """运营概览：把各业务模块的待处理量汇总成看板卡片。"""
    return store.overview()
