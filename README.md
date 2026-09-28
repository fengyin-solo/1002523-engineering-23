# 轨道交通信号检修管理平台

面向轨道交通信号设备日常巡检、故障处置、天窗修作业、器材检修与联锁试验的一体化信号检修管理后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
两边各自独立启动，前端 dev server 已关掉自动打开页面，启动后按终端打印的地址手工打开。

## 目录结构

```text
.
├── config/
│   └── settings.env           本地脚本与部署脚本共用的唯一配置来源（端口/环境/数据路径）
├── scripts/
│   ├── lib.sh                 脚本公共库：配置加载、失败提示、就绪探测
│   ├── dev.sh                 一键本地环境：装依赖 → 起服务 → 冒烟检查
│   ├── seed.sh                熔断器示例数据重复导入（按熔断器编号覆盖）
│   ├── smoke.sh               冒烟检查：熔断器列表 + 三种状态 + 幂等导入
│   └── deploy.sh              docker compose 部署（与本地共用配置与数据）
├── frontend/                  Vue 3 + Vite + TypeScript 前端
│   ├── src/views/             每个业务模块一个页面
│   ├── src/api/               统一请求封装
│   ├── src/stores/            会话与筛选状态
│   └── vite.config.ts         dev server 配置（open: false）
├── backend/                   FastAPI（Python） 后端
│   ├── app/routers/           每个业务模块一组接口
│   ├── app/services/          业务规则与状态流转
│   ├── app/store.py           内存数据仓库（含按业务编号覆盖导入）
│   ├── app/seed.py            示例数据装配（熔断器数据读 data/fuse.json）
│   └── data/fuse.json         熔断器示例数据：正常 / 已熔断 / 备件不足三种情形
├── .gitignore
└── docker-compose.yml
```

## 一键本地开发（推荐）

```bash
make dev
```

这一条命令（等价于 `./scripts/dev.sh`）按顺序完成 6 个环节：

1. **前置检查**：确认 `python3`（含 venv 模块）、`node`、`npm`、`curl` 可用；
2. **安装后端依赖**：在 `backend/.venv` 建虚拟环境并安装 `requirements.txt`；
3. **安装前端依赖**：在 `frontend/node_modules` 执行 `npm install`；
4. **启动后端**：服务启动时自动加载 `backend/data/fuse.json`；
5. **冒烟检查**：自动确认熔断器接口返回列表（见下节）；
6. **启动前端**：dev server 就绪后打印访问地址。

启动成功后访问 `http://127.0.0.1:5173/`（熔断器页 `/fuse`），按 `Ctrl+C` 会同时
停止前后端。运行日志在 `logs/backend.log` 与 `logs/frontend.log`。

### 失败会怎样

脚本对每个环节都打印 `==> [n/6] 环节名`。任何一步失败都会明确指出**卡在第几环、
退出码、脚本行号**，并附上原始报错：

- 后端 `pip install` 失败 → 删除未装完的 `.venv`，下次重跑从零建环境；
- 前端 `npm install` 中断 → `node_modules` 没有完成标记，下次重跑删除后重装；
- 换了机器或 Python 版本导致旧 `.venv` 不可用 → 没有完成标记，同样自动重建。

不会带着半套环境继续往下跑。

### 分步手动入口（可选）

`make backend`、`make frontend`、`make install` 仍然保留，供只起一端时使用；它们
同样读取 `config/settings.env`，不会与一键流程产生端口或数据上的分歧。

## 熔断器示例数据与导入

熔断器的示例数据**不内嵌在代码里**，唯一来源是 `backend/data/fuse.json`，
覆盖三种情形：

| 熔断器编号 | 状态 | 说明 |
| --- | --- | --- |
| FUSE-0001 | 正常 | 在役、备件充足 |
| FUSE-0002 | 已熔断 | 过流熔断、待更换 |
| FUSE-0003 | 备件不足 | 备件存量低于安全库存 |

后端启动时自动加载该文件；想在**不重启服务**的情况下重新导入：

```bash
make seed      # 等价于 ./scripts/seed.sh
```

导入语义是**按「熔断器编号」整行覆盖（upsert）**：编号已存在就替换，新编号才追加，
连跑任意次数都不会出现重复编号的记录。对应实现：`store.upsert_rows()` 与
`POST /api/fuse/import`。

## 冒烟检查

```bash
make smoke     # 等价于 ./scripts/smoke.sh
```

自动确认三件事：

1. `GET /api/health` 服务存活；
2. `GET /api/fuse` 返回熔断器列表，且正常 / 已熔断 / 备件不足三种状态齐全
   （FUSE-0001/2/3 都在）；
3. 调一次 `POST /api/fuse/import` 后总数不变——自动验证重复导入是覆盖而非追加。

任意一项不满足，脚本以非零码退出并打印具体差异（缺哪个编号、缺哪个状态、
导入前后条数变化）。

## 部署

```bash
make deploy    # 等价于 ./scripts/deploy.sh
```

部署机需要 Docker Engine + Docker Compose v2。流程为：构建镜像 → `up -d` 起容器 →
**跑同一条 `scripts/smoke.sh`**。

**本地与部署的一致性保障：**

- 配置只有一份：`config/settings.env` 由 `scripts/dev.sh` source，也通过
  `env_file` 注入 compose 容器，端口插值同样来自 deploy 脚本 source 该文件；
- 数据只有一份：`backend/data/fuse.json` 构建镜像时原样打入（`.dockerignore`
  不会忽略它），容器启动后由与本地相同的加载/导入逻辑处理；
- 检查只有一套：部署完成后执行的冒烟脚本与本地完全相同。

因此上线前后跑出来的熔断器数据一致。部署后可用
`curl http://127.0.0.1:8000/api/health` 核对回显的 `env` 是否为预期环境标识。

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
| 检修工具 | `tool` | 工具编号、工具名称、规格型号 |
| 技术规章 | `regulation` | 技术规章 | 规章编号、规章名称、适用专业 |
| 技能培训 | `training` | 培训记录 | 培训编号、培训主题、培训对象 |

## 约定

- 每个模块的前端页面在 `frontend/src/views/<模块>/index.vue`，后端接口在
  `backend/app/routers/<模块>.py`，业务规则在 `backend/app/services/<模块>.py`。
- 列表接口统一返回 `{ items, total, page, size }`，动作接口统一返回 `{ ok, message }`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
