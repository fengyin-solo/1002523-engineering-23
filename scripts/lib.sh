#!/usr/bin/env bash
# scripts/lib.sh：dev / seed / smoke / deploy 四个脚本共用的公共部分。
# 只提供函数与统一的失败提示，不可单独执行，由其他脚本 source。

# 仓库根目录与唯一配置来源
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT/config/settings.env"

# 加载共享配置：本地脚本与 docker compose 部署都读 config/settings.env 这一份。
# 逐行读取并以 ${VAR:-文件值} 兜底，因此调用方显式传入的环境变量
# （如 BACKEND_PORT=9999 ./scripts/smoke.sh）优先级更高，可用于临时覆盖。
load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ 缺少共享配置文件：$CONFIG_FILE" >&2
    echo "  本地脚本和部署脚本都依赖这一份配置（端口、环境标识、种子数据路径），" >&2
    echo "  请勿删除或改名；如丢失请从 git 恢复。" >&2
    exit 2
  fi
  set -a
  while IFS='=' read -r key value; do
    case "$key" in
      ''|'#'*|' '*|'	'*) continue ;;
    esac
    # 文件中的值只在环境未提供时兜底（去掉行尾回车，兼容 CRLF）
    eval "$key=\${$key:-\"\${value%\"\r\"}\"}"
    export "$key"
  done < "$CONFIG_FILE"
  set +a
}

# 当前执行到的步骤名，失败时用来明确告诉人卡在哪一环
CURRENT_STEP="脚本初始化"

step() {
  CURRENT_STEP="$1 $2"
  echo "==> [$1] $2"
}

ok() {
  echo "  ✓ $1"
}

# 命令不存在时返回 127（由 ERR 陷阱补上「卡在哪个步骤」）
require_command() {
  local name="$1" hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "✗ 缺少命令「$name」：$hint" >&2
    return 127
  fi
}

# 轮询 HTTP 地址直到 2xx；参数：host port path 重试秒数 日志路径(可选)
wait_for_url() {
  local host="$1" port="$2" path="$3" tries="${4:-30}" logfile="${5:-}" i
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS --max-time 2 "http://$host:$port$path" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "✗ 等待 http://$host:$port$path 超时（${tries} 秒未就绪）。" >&2
  if [ -n "$logfile" ] && [ -f "$logfile" ]; then
    echo "  服务日志最后 20 行（$logfile）：" >&2
    tail -n 20 "$logfile" >&2
  fi
  return 1
}

# 端口占用检查：避免新服务绑定失败后，就绪探测误打到别的进程造成「假成功」。
# 参数：port 用途说明
ensure_port_free() {
  local port="$1" label="$2"
  # 尝试 bind 127.0.0.1：有人监听就失败。不依赖 ss/lsof，换机器也能用。
  if python3 - "$port" <<'PYEOF' 2>/dev/null
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PYEOF
  then
    return 0
  fi
  echo "✗ 端口 $port 已被占用，$label无法绑定。" >&2
  echo "  先停掉占用进程（如另一个 make dev），或修改 config/settings.env 里的端口后重跑；" >&2
  echo "  不要直接重跑——否则就绪探测可能打到旧进程，造成看似成功的假象。" >&2
  if command -v ss >/dev/null 2>&1; then
    ss -ltnpH "sport = :$port" 2>/dev/null | head -3 >&2 || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -3 >&2 || true
  fi
  return 1
}

# 统一的失败出口：指出卡在第几步、退出码与脚本行号
on_error() {
  local code=$?
  local line=${BASH_LINENO[0]:-未知}
  echo "" >&2
  echo "✗ 流程中断：卡在「${CURRENT_STEP}」这一环（退出码 ${code}，脚本第 ${line} 行）。" >&2
  echo "  - 上方是该环节的原始输出，请据此排查；" >&2
  echo "  - 未装完的依赖已判为半成品清理（或未打完成标记），修好后直接重跑同一命令即可，" >&2
  echo "    不会带着半套环境继续。" >&2
  exit "$code"
}
