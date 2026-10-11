#!/usr/bin/env bash
# qsql 下载器 / 安装器
#   curl -fsSL https://psql.naling.net/dl/install.sh | sudo bash
#
# 走官方下载服务器：每次下载现场注入唯一 PID（20 位）+ 一年评估期，并记录下载。
set -e

DL_BASE="${QSQL_DL_BASE:-https://psql.naling.net/dl}"
VER="${QSQL_VERSION:-0.2.0}"
PORT="${QSQL_PORT:-8077}"
DEST="${QSQL_HOME:-/opt/qsql}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1;34m[qsql]\033[0m %s\n' "$*"; }
[ "$(id -u)" = "0" ] || { echo "请用 root 运行（sudo bash）"; exit 1; }

say "1/5 依赖"
if command -v apt-get >/dev/null; then
  apt-get install -y -qq python3 python3-cryptography curl unzip >/dev/null 2>&1 || true
elif command -v apk >/dev/null; then
  apk add --no-cache python3 py3-cryptography curl unzip >/dev/null 2>&1 || true
elif command -v yum >/dev/null; then
  yum install -y -q python3 python3-cryptography curl unzip >/dev/null 2>&1 || true
fi
python3 -c "import cryptography" 2>/dev/null || { echo "缺 python3-cryptography"; exit 1; }

say "2/5 从官方下载服务器取包 v$VER"
if [ -f ./qsql.py ]; then
  say "  本地已有文件，跳过下载（自建部署）"
  mkdir -p "$TMP/pkg/qsql"; cp -rf ./qsql.py ./qsql-mcp.py ./static "$TMP/pkg/qsql/" 2>/dev/null || true
else
  curl -fsSL "$DL_BASE/qsql-$VER.zip" -o "$TMP/qsql.zip" -D "$TMP/hdr" || {
    echo "下载失败：$DL_BASE/qsql-$VER.zip"; exit 1; }
  PID="$(grep -i '^x-qsql-pid' "$TMP/hdr" | tr -d '\r' | awk '{print $2}')"
  say "  本次授权 PID：${PID:-（随包自带）}"
  unzip -q "$TMP/qsql.zip" -d "$TMP/pkg"
fi

say "3/5 安装到 $DEST"
mkdir -p "$DEST"; chmod 700 "$DEST"
SRC="$TMP/pkg/qsql"; [ -d "$SRC" ] || SRC="$TMP/pkg"
cp -f "$SRC"/*.py "$DEST"/ 2>/dev/null || true
rm -rf "$DEST/static"; cp -rf "$SRC/static" "$DEST/static"
[ -f "$SRC/README.md" ] && cp -f "$SRC/README.md" "$DEST/"
[ -f "$SRC/LICENSE" ] && cp -f "$SRC/LICENSE" "$DEST/"
[ -f "$SRC/使用文档.md" ] && cp -f "$SRC/使用文档.md" "$DEST/"
[ -f "$SRC/license.json" ] && cp -f "$SRC/license.json" "$DEST/"
chmod 600 "$DEST"/*.py "$DEST/license.json" 2>/dev/null || true

say "4/5 systemd 服务"
cat > /etc/systemd/system/qsql.service <<EOF
[Unit]
Description=qsql database gatekeeper
After=network.target
[Service]
Type=simple
Environment=QSQL_HOME=$DEST
Environment=QSQL_PORT=$PORT
ExecStart=/usr/bin/python3 $DEST/qsql.py
Restart=always
RestartSec=3
StandardOutput=append:/var/log/qsql.log
StandardError=append:/var/log/qsql.log
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q qsql
systemctl restart qsql
sleep 1

say "5/5 完成"
systemctl is-active qsql | sed 's/^/  服务: /'
SLUG="$(python3 -c "import json;print(json.load(open('$DEST/state.json'))['slug'])" 2>/dev/null || echo '?')"
IP="$(curl -fsS -m 5 ifconfig.me 2>/dev/null || echo '<你的域名或IP>')"
echo
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  你的管理后台地址（这就是你的暗门，别外传）：             │"
printf "  │  http://%s/psql/%s\n" "$IP" "$SLUG"
echo "  └──────────────────────────────────────────────────────────┘"
echo
echo "  打开它 →「你是首次用管理后台」→ 开始初始化。"
echo "  授权信息（评估期 / PID）可在后台「设置」里看到。"
