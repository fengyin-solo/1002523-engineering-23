# scripts/common.sh 是 bash 脚本（用到 BASH_SOURCE、间接展开），统一用 bash 执行配方
SHELL := /bin/bash

.PHONY: help setup dev smoke seed-snapshot seed-reload deploy

help: ## 显示可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "用法：make <目标>\n\n目标：\n"} /^[a-zA-Z_-]+:.*##/ { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## 装齐前后端依赖（原子安装，失败回滚，不留半套环境）
	bash scripts/setup.sh

dev: ## 一条命令：装依赖 + 起前后端 + 自动冒烟
	bash scripts/dev.sh

# smoke / seed-reload 通过 common.sh 读取统一配置（.env，模板 .env.example）
smoke: ## 只跑熔断器冒烟检查（确认列表接口、三种情形、覆盖式导入）
	@source scripts/common.sh; \
	python3 scripts/smoke.py --base-url "$$BACKEND_URL"

seed-snapshot: ## 按种子文件生成熔断器基线快照（提交到仓库，供上线比对）
	bash scripts/seed-snapshot.sh

seed-reload: ## 对运行中的环境重新导入熔断器示例数据（按编号覆盖，不追加）
	@source scripts/common.sh; \
	curl -fsS -X POST "$$BACKEND_URL/api/fuse/seed/reload" && echo

deploy: ## 构建镜像、部署、健康检查、冒烟并比对熔断器基线（与本地同源配置）
	bash scripts/deploy.sh
