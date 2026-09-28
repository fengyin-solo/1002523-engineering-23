# 轨道交通信号检修管理平台

面向轨道交通信号设备日常巡检、故障处置、天窗修作业、器材检修与联锁试验的一体化信号检修管理后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
本地与部署共用同一份配置（仓库根目录 `.env`，模板为 `.env.example`）、同一套脚本与同一份熔断器数据文件，
换一台机器只要能跑通一条命令就能得到一致的开发环境。

## 目录结构

```text
.
├── frontend/                 Vue 3 + Vite + TypeScript 前端
│   ├── src/views/            每个业务模块一个页面
│   ├── src/api/              统一请求封装
│   ├── src/stores/           会话与筛选状态
│   └── vite.config.ts        dev server 配置（地址/端口读统一配置）
├── backend/                  FastAPI（Python） 后端
│   ├── app/routers/          每个业务模块一组接口
│   ├── app/services/         业务规则与状态流转
│   ├── app/seed_loader.py    熔断器示例数据装载（按编号覆盖，不追加）
│   ├── app/store.py          内存数据仓库
│   └── data/
│       ├── fuse-seed.json       熔断器示例数据（唯一数据来源，需提交）
│       └── fuse-snapshot.json   熔断器基线快照（上线前后比对，需提交）
├── scripts/                  本地与部署共用的工程流程脚本
│   ├── common.sh             统一配置加载 / 阶段日志 / 就绪探测
│   ├── setup.sh              一条命令装齐前后端依赖（原子安装、失败回滚）
│   ├── dev.sh                一条命令起本地环境并自动冒烟
│   ├── smoke.py              熔断器接口冒烟 + 三种情形 + 覆盖导入 + 快照比对
│   ├── seed-snapshot.sh      由种子文件生成基线快照
│   └── deploy.sh             部署：构建镜像 → 启动 → 健康检查 → 冒烟比对
├── Makefile                  上述流程的统一入口
├── .env.example              统一配置模板（本地脚本与 docker-compose 同源）
└── docker-compose.yml        部署编排（变量来自同一份 .env）
```

## 快速开始（一条命令）

```bash
make dev
```

它会按顺序完成：

1. **装依赖**（等价于 `make setup`）：后端虚拟环境 + `requirements.txt`、前端 `npm install`；
   安装采用「备份旧环境 → 在最终路径构建 → 成功才删旧环境，失败自动还原」，中途失败会指出
   卡在**前置检查 / 后端依赖 / 前端依赖**哪一环，不会留下半套环境。依赖文件没变时自动跳过。
2. **起后端** FastAPI，等待 `/api/health` 就绪；
3. **起前端** Vite dev server，等待端口就绪；
4. **自动冒烟**：确认熔断器列表接口能返回数据、三种情形齐全、重复导入为按编号覆盖。

启动成功后：

- 前端页面：`http://127.0.0.1:5173/`（dev server 不会自动打开浏览器）
- 后端健康检查：`http://127.0.0.1:8000/api/health`
- 熔断器列表：`http://127.0.0.1:8000/api/fuse`
- 日志：`.run-logs/backend.log`、`.run-logs/frontend.log`
- `Ctrl-C` 停止，前后端进程会被整组回收，不留孤儿进程。

前置要求：Python 3.11+、Node.js 20+、npm。若系统 Python 缺少 `venv`（Debian/Ubuntu 报
`ensurepip is not available`），二选一：`apt install python3-venv`，或
`python3 -m pip install --user virtualenv`（脚本会自动改用 virtualenv）。

### 分步命令

| 命令 | 作用 |
| --- | --- |
| `make setup` | 只装依赖，幂等可重复执行 |
| `make dev` | 装依赖 + 起前后端 + 自动冒烟 |
| `make smoke` | 对运行中的环境单独跑冒烟检查 |
| `make seed-reload` | 对运行中的环境重新导入熔断器示例数据（按编号覆盖，不追加） |
| `make seed-snapshot` | 由种子文件生成熔断器基线快照 |
| `make deploy` | 构建并部署（Docker），健康检查 + 冒烟 + 快照比对 |

## 配置来源（本地与部署同源）

所有地址、端口、数据文件路径只有一份来源：仓库根目录的 `.env`（首次执行脚本时若不存在，
会自动从 `.env.example` 复制）。`scripts/` 本地脚本与 `docker-compose.yml` 都读这一份，
进程已有的环境变量优先级更高，便于临时覆盖，例如：

```bash
BACKEND_PORT=18000 FRONTEND_PORT=15173 make dev
```

主要配置项见 `.env.example`：`BACKEND_HOST/PORT`、`FRONTEND_HOST/PORT`、
`VITE_PROXY_TARGET`（前端 `/api` 代理目标）、`FUSE_SEED_FILE`。容器内只对监听地址
（`0.0.0.0`）和服务间代理（`http://backend:<端口>`）做必要覆盖，端口仍取自同一份配置。

## 熔断器示例数据

唯一数据来源是 `backend/data/fuse-seed.json`，后端**启动时自动装载**，覆盖三种情形：

| 熔断器编号 | 状态 | 说明 |
| --- | --- | --- |
| FUSE-0001 | 正常 | 运行正常，备件充足 |
| FUSE-0002 | 已熔断 | 雷击过流熔断，待天窗更换 |
| FUSE-0003 | 备件不足 | 备件低于安全库存 |

**重复导入按熔断器编号覆盖，而不是追加**：编号已存在则整条替换（保留 id），不存在才插入。
因此可以随时用 `make seed-reload`（或 `POST /api/fuse/seed/reload`）把数据恢复成基线，
重复执行不会产生重复记录。种子文件缺失、JSON 非法、缺必填字段或编号重复时，服务会直接
启动失败并指出具体问题，不带病起一套缺料环境。

### 上线前后数据一致性

```bash
# 1) 修改/确认种子后，在本地生成基线快照并提交
make seed-snapshot        # 生成 backend/data/fuse-snapshot.json

# 2) 部署（构建 → 启动 → 健康检查 → 同一套冒烟 → 与快照逐字段比对）
make deploy
```

`make deploy` 用的冒烟脚本（`scripts/smoke.py`）与本地完全相同，它会把线上熔断器数据
与提交进仓库的 `fuse-snapshot.json` 逐字段比对；不一致则部署判失败，从而保证**上线前后用
同一套流程跑出来的熔断器数据一致**。缺少快照会明确拒绝部署并提示先生成。

## 业务模块

| 模块 | 目录 | 业务对象 | 主要字段 |
| --- | --- | --- | --- |
| 联锁管理 | `interlock` | 联锁道岔 | 道岔编号、所属车站、道岔类型 |
| 轨道电路 | `trackcircuit` | 轨道电路 | 区段编号、所属区间、载频类型 |
| 信号机 | `signal` | 信号机 | 信号机编号、所属车站、信号机类型 |
| 转辙机 | `pointmachine` | 转辙机 | 转辙机编号、所属道岔、转辙机型号 |
| 信号电缆 | `cable` | 信号电缆 | 电缆编号、起止站点、电缆芯数 |
| 信号电源 | `powersupply` | 电源屏 | 电源屏编号、所属车站、输入电压 |
| 车载设备 | `atp` | 车载ATP | 设备编号、所属列车、设备型号 |
| 应答器 | `balise` | 应答器 | 应答器编号、所在位置、报文版本 |
| 计轴设备 | `axlecounter` | 计轴器 | 计轴器编号、所属区间、检测磁头 |
| 调度中心 | `dispatchcenter` | 调度台 | 调度台编号、管辖范围、显示设备 |
| 天窗修作业 | `maintenancewindow` | 天窗计划 | 计划编号、作业日期、作业区间 |
| 继电器检修 | `relay` | 继电器 | 继电器编号、继电器型号、所属设备 |
| 熔断器管理 | `fuse` | 熔断器 | 熔断器编号、额定电流、安装位置 |
| 防雷元件 | `lightning` | 防雷元件 | 元件编号、安装位置、防护等级 |
| 应急备品 | `emergencyresp` | 应急备品 | 备品编号、备品名称、规格型号 |
| 联锁试验 | `testrecord` | 试验记录 | 试验编号、试验日期、试验车站 |
| 信号故障 | `fault` | 故障记录 | 故障编号、发生时间、故障设备 |
| 检修工具 | `tool` | 检修工具 | 工具编号、工具名称、规格型号 |
| 技术规章 | `regulation` | 技术规章 | 规章编号、规章名称、适用专业 |
| 技能培训 | `training` | 培训记录 | 培训编号、培训主题、培训对象 |

## 约定

- 每个模块的前端页面在 `frontend/src/views/<模块>/index.vue`，后端接口在
  `backend/app/routers/<模块>.py`，业务规则在 `backend/app/services/<模块>.py`。
- 列表接口统一返回 `{ items, total, page, size }`，动作接口统一返回 `{ ok, message }`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
