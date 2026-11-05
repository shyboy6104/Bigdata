#!/usr/bin/env bash
# ============================================================
# BigData / Docker 管理器 —— 一键启动器（Ubuntu / Linux 版，幂等）
#   - relay 已在运行时，只打开浏览器
#   - 否则启动 relay：桌面环境优先开独立终端窗口（看日志、关窗即停）；
#     无图形环境则回退为后台运行（日志写入 relay.log）
#   - 使用期间保持 relay 运行
#
# 用法：
#   ./start.sh                    仅本机访问（127.0.0.1）
#   ./start.sh lan                局域网可访问（0.0.0.0），不设令牌
#   ./start.sh lan mytoken        局域网可访问，并设置访问令牌 mytoken
#   ./start.sh lan mytoken 9000   自定义端口 + 令牌 + 局域网
# ============================================================

cd "$(dirname "$0")" || { echo "[错误] 无法进入脚本目录"; exit 1; }

HOST="127.0.0.1"
PORT=8000
TOKEN=""

# 解析参数
if [ "$1" = "lan" ]; then
  HOST="0.0.0.0"
  [ -n "$2" ] && TOKEN="$2"
  [ -n "$3" ] && PORT="$3"
elif [ -n "$1" ]; then
  PORT="$1"
fi

# 带 token 时浏览器 URL 追加 ?token=
if [ -n "$TOKEN" ]; then
  URL="http://127.0.0.1:${PORT}/bigdata?token=${TOKEN}"
else
  URL="http://127.0.0.1:${PORT}/bigdata"
fi

# 1) 探测 python3
if command -v python3 >/dev/null 2>&1; then
  PY="python3"
elif command -v python >/dev/null 2>&1; then
  PY="python"
else
  echo "[错误] 未找到 python3，请先安装：sudo apt install python3"
  exit 1
fi

is_listening() { ss -tln 2>/dev/null | grep -q ":${PORT} "; }

# relay 启动命令（带环境变量）
RELAY_CMD="RELAY_HOST=${HOST}"
if [ -n "$TOKEN" ]; then
  RELAY_CMD="RELAY_HOST=${HOST} RELAY_TOKEN=${TOKEN}"
fi

# 2) 幂等检查
if is_listening; then
  echo "Relay 已在运行： ${URL}"
else
  echo "正在启动 relay： host=${HOST} port=${PORT} token=${TOKEN:-无}"
  WIN_STARTED=0
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="BigData Relay" -- bash -c "env ${RELAY_CMD} ${PY} docker-relay.py ${PORT} ${HOST}; echo; echo 'relay 已停止，按回车关闭窗口'; read" &
    WIN_STARTED=1
  elif command -v xterm >/dev/null 2>&1; then
    xterm -T "BigData Relay" -e bash -c "env ${RELAY_CMD} ${PY} docker-relay.py ${PORT} ${HOST}; echo; read -p 'relay 已停止，按回车关闭窗口'" &
    WIN_STARTED=1
  fi

  sleep 2
  if ! is_listening; then
    [ "$WIN_STARTED" = "1" ] && echo "（未检测到监听端口，可能无图形环境，回退为后台运行）"
    env ${RELAY_CMD} nohup "${PY}" docker-relay.py ${PORT} ${HOST} > relay.log 2>&1 &
    echo "（已后台运行，日志见 relay.log，PID $!）"
    sleep 2
  fi
fi

# 3) 打开浏览器
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 &
  echo "已打开浏览器： ${URL}"
else
  echo "请手动打开浏览器访问： ${URL}"
fi

# 4) 局域网模式下打印本机 IP 供分享
if [ "$HOST" = "0.0.0.0" ]; then
  echo ""
  echo "局域网访问地址（任选其一）："
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | while read ip; do
    [ -n "$TOKEN" ] && echo "  http://${ip}:${PORT}/bigdata?token=${TOKEN}"
    [ -z "$TOKEN" ] && echo "  http://${ip}:${PORT}/bigdata"
  done
fi
