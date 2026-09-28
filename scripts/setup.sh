#!/usr/bin/env bash
# 一条命令装齐前后端依赖：make setup
#
# 设计原则：
#  - 原子安装：先把旧 venv / node_modules 备份走，在最终路径上构建，
#    成功后删备份，中途失败删掉半成品并还原旧环境，绝不留下“半套环境”；
#  - 依赖文件未变化时跳过（用 stamp 记录哈希），换机器/换 Python 会自动重建；
#  - 每一步都打印阶段名，失败时明确指出卡在依赖检查、后端依赖还是前端依赖。
set -euo pipefail

source "$(dirname "$0")/common.sh"

STAMP_DIR="$REPO_ROOT/.setup-stamp"
mkdir -p "$STAMP_DIR"

hash_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | awk '{print $1}'
  else
    shasum -a 256 "$@" | awk '{print $1}'
  fi
}

# ---------- 0. 前置检查 ----------
log setup "检查本机依赖（python3 / node / npm）"
command -v python3 >/dev/null 2>&1 || fail 前置检查 "缺少 python3，请先安装 Python 3.11+"
command -v node >/dev/null 2>&1 || fail 前置检查 "缺少 node，请先安装 Node.js 20+"
command -v npm >/dev/null 2>&1 || fail 前置检查 "缺少 npm，请随 Node.js 一起安装"
PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
log setup "python3 $PY_VER / node $(node --version) / npm $(npm --version)"

# ---------- 1. 后端虚拟环境 + 依赖 ----------
BACKEND_DIR="$REPO_ROOT/backend"
VENV="$BACKEND_DIR/.venv"
STAMP="$STAMP_DIR/backend.venv.$PY_VER.sha256"
EXPECTED_HASH="$(hash_files "$BACKEND_DIR/requirements.txt")"
CURRENT_HASH="$(cat "$STAMP" 2>/dev/null || true)"
VENV_OK=0
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
  VENV_OK=1
fi

if [ "$VENV_OK" = 1 ] && [ "$CURRENT_HASH" = "$EXPECTED_HASH" ]; then
  log setup "后端依赖已是最新，跳过（requirements.txt 未变化）"
else
  STAGE="后端依赖"
  BACKUP_VENV="$BACKEND_DIR/.venv.bak.$$"
  log "$STAGE" "创建虚拟环境并安装 requirements.txt（原地构建、成功才删旧环境；失败自动回滚，不留半成品）"
  # 必须在最终路径上建 venv：pip 生成的 uvicorn 等命令把解释器路径写死在
  # shebang 里，建在临时目录再 mv 会导致命令不可执行。旧环境先备份走，失败还原。
  if [ -e "$VENV" ]; then
    mv "$VENV" "$BACKUP_VENV"
  fi
  rollback_venv() {
    rm -rf "$VENV"
    if [ -d "$BACKUP_VENV" ]; then mv "$BACKUP_VENV" "$VENV"; fi
    fail "$STAGE" "虚拟环境创建/依赖安装失败，已清理半成品并还原原有环境。
  排查建议：
    1) 标准方案：安装系统包 python3-venv（Debian/Ubuntu：apt install python3-venv）；
    2) 无 root 时：python3 -m pip install --user virtualenv，脚本会自动改用 virtualenv；
    3) 网络或包版本问题请看上方 pip 输出。"
  }
  trap rollback_venv ERR
  # 优先标准库 venv；Debian 缺 python3-venv 时它要么建出来没 pip、要么直接失败，
  # 两种情况都改走用户态 virtualenv；两个都不行才回滚报错。
  # （放在 if 条件里的失败命令不会触发 ERR trap，可以安全地逐个尝试。）
  venv_ready=0
  if python3 -m venv "$VENV" >/dev/null 2>&1 && "$VENV/bin/python" -m pip --version >/dev/null 2>&1; then
    venv_ready=1
  else
    rm -rf "$VENV"
    if python3 -m virtualenv "$VENV" >/dev/null 2>&1 && "$VENV/bin/python" -m pip --version >/dev/null 2>&1; then
      venv_ready=1
    fi
  fi
  if [ "$venv_ready" != 1 ]; then
    trap - ERR
    rollback_venv
  fi
  "$VENV/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV/bin/pip" install -r "$BACKEND_DIR/requirements.txt"
  trap - ERR

  rm -rf "$BACKUP_VENV"
  printf '%s\n' "$EXPECTED_HASH" > "$STAMP"
  log "$STAGE" "后端依赖安装完成：$VENV"
fi

# ---------- 2. 前端依赖 ----------
FRONTEND_DIR="$REPO_ROOT/frontend"
NM="$FRONTEND_DIR/node_modules"
STAMP="$STAMP_DIR/frontend.nm.sha256"
EXPECTED_HASH="$(hash_files "$FRONTEND_DIR/package.json")"
CURRENT_HASH="$(cat "$STAMP" 2>/dev/null || true)"
NM_OK=0
if [ -x "$NM/.bin/vite" ]; then NM_OK=1; fi

if [ "$NM_OK" = 1 ] && [ "$CURRENT_HASH" = "$EXPECTED_HASH" ]; then
  log setup "前端依赖已是最新，跳过（package.json 未变化）"
else
  STAGE="前端依赖"
  BACKUP="$FRONTEND_DIR/node_modules.bak.$$"
  log "$STAGE" "npm install（原地安装、成功才删旧依赖；失败自动回滚，不留半成品）"
  # npm 固定装到 node_modules：先把旧目录备份走，安装成功后删除备份；
  # 安装失败则删掉半成品并把备份还原。
  if [ -d "$NM" ]; then
    mv "$NM" "$BACKUP"
  fi
  rollback_nm() {
    rm -rf "$NM"
    if [ -d "$BACKUP" ]; then mv "$BACKUP" "$NM"; fi
    fail "$STAGE" "前端依赖安装失败，已清理半成品并回滚原有 node_modules。请查看上方 npm 输出定位原因（网络/registry/包版本）。"
  }
  trap rollback_nm ERR
  ( cd "$FRONTEND_DIR" && npm install --no-audit --no-fund )
  trap - ERR
  rm -rf "$BACKUP"
  printf '%s\n' "$EXPECTED_HASH" > "$STAMP"
  log "$STAGE" "前端依赖安装完成：$NM"
fi

log setup "依赖全部就绪。启动本地环境：make dev"
