#!/usr/bin/env bash
# ============================================================
# BigData / Docker 管理器 —— 局域网一键启动（带固定令牌）
#
# 用法：
#   ./start-lan.sh                  用脚本内置令牌启动局域网模式
#   ./start-lan.sh mytoken          临时用 mytoken 作令牌
#   ./start-lan.sh mytoken 9000     临时用 mytoken + 端口 9000
#
# 修改默认令牌：编辑下面 TOKEN= 这一行
# ============================================================

cd "$(dirname "$0")" || { echo "[错误] 无法进入脚本目录"; exit 1; }

# === 默认令牌（改这一行即可更换）===
TOKEN="bigdata2026"
PORT=8000

# 命令行覆盖
[ -n "$1" ] && TOKEN="$1"
[ -n "$2" ] && PORT="$2"

echo "启动局域网模式：令牌=${TOKEN} 端口=${PORT}"
exec ./start.sh lan "$TOKEN" "$PORT"
