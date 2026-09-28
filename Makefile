# 本地与部署共用的工程入口。配置一律来自 config/settings.env，不要在这里硬编码端口。
.PHONY: dev install seed smoke deploy backend frontend

## 一条命令：装依赖 + 起前后端本地环境 + 自动冒烟（详见 scripts/dev.sh）
dev:
	./scripts/dev.sh

## 单独重复导入熔断器示例数据（按熔断器编号覆盖，不追加；需要后端在运行）
seed:
	./scripts/seed.sh

## 冒烟检查：确认熔断器接口返回列表、三种状态齐全、重复导入不追加
smoke:
	./scripts/smoke.sh

## 部署：docker compose 构建启动 + 同一套冒烟检查（与本地共用配置和种子数据）
deploy:
	./scripts/deploy.sh

## 以下为分步手动入口，日常开发用 make dev 即可
install:
	cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd frontend && npm install

backend:
	cd backend && ./run.sh

frontend:
	cd frontend && npm run dev
