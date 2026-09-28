"""运行配置：端口、跨域、运行环境。

本地脚本（scripts/）与 docker-compose 部署都从同一份 .env（模板为 .env.example）
注入环境变量，本模块只负责读取，避免配置两处维护。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value not in (None, "") else default


def _env_int(name: str, default: int) -> int:
    raw = _env(name, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    app_name: str = "轨道交通信号检修管理平台"
    env: str = field(default_factory=lambda: _env("APP_ENV", "local"))
    host: str = field(default_factory=lambda: _env("BACKEND_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: _env_int("BACKEND_PORT", 8000))
    fuse_seed_file: str = field(
        default_factory=lambda: _env("FUSE_SEED_FILE", "data/fuse-seed.json")
    )
    allowed_origins: list[str] = field(
        default_factory=lambda: [
            "http://127.0.0.1:5173",
            "http://localhost:5173",
        ]
    )
    page_size_default: int = 20
    page_size_max: int = 200


settings = Settings()
