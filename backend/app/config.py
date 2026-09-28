"""运行配置：端口、跨域、运行环境。

取值来源只有一处：仓库根目录的 config/settings.env（本地脚本与部署脚本都会加载它），
再以环境变量的形式传到这里。直接改代码里的默认值只会影响「没走标准流程」的启动方式。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent


def _env(key: str, default: str) -> str:
    value = os.environ.get(key, "").strip()
    return value or default


@dataclass(frozen=True)
class Settings:
    app_name: str = "轨道交通信号检修管理平台"
    env: str = field(default_factory=lambda: _env("APP_ENV", "local"))
    port: int = field(default_factory=lambda: int(_env("BACKEND_PORT", "8000")))
    # 熔断器示例数据文件：相对 backend/ 目录解析，本地与容器内路径一致
    fuse_seed_file: str = field(default_factory=lambda: _env("FUSE_SEED_FILE", "data/fuse.json"))
    allowed_origins: list[str] = field(
        default_factory=lambda: [
            "http://127.0.0.1:5173",
            "http://localhost:5173",
        ]
    )
    page_size_default: int = 20
    page_size_max: int = 200

    @property
    def fuse_seed_path(self) -> Path:
        path = Path(self.fuse_seed_file)
        return path if path.is_absolute() else BACKEND_ROOT / path


settings = Settings()
