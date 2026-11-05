#!/usr/bin/env bash
# Run as root on the authorized single-user host. No credentials in arguments.
set -euo pipefail
umask 027
: "${PUBLIC_IP:?Set the public IPv4 address}"
: "${PACKAGE:?Set an uploaded precompiled backend tar.gz path}"
: "${PACKAGE_SHA256:?Set the independently calculated package SHA256}"
: "${RELEASE_ID:?Set a unique release identifier}"
TLS_PORT=${TLS_PORT:-443}
BACKEND_PORT=${BACKEND_PORT:-18787}
MCP_MODE=${MCP_MODE:-mock}
NODE_VERSION=22.23.4
NODE_SHA256=1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce
python3 - "$PUBLIC_IP" "$TLS_PORT" "$BACKEND_PORT" "$RELEASE_ID" "$MCP_MODE" <<'PY'
import ipaddress,re,sys
assert ipaddress.ip_address(sys.argv[1]).version == 4
assert int(sys.argv[2]) == 443 or 1024 <= int(sys.argv[2]) <= 65535
assert 1024 <= int(sys.argv[3]) <= 65535
assert sys.argv[2] != sys.argv[3]
assert re.fullmatch(r'[A-Za-z0-9_-]{1,80}',sys.argv[4])
assert sys.argv[5] in ('mock','live')
PY
test "$(id -u)" = 0
test "$(uname -m)" = x86_64
test -f "$PACKAGE"
printf '%s  %s\n' "$PACKAGE_SHA256" "$PACKAGE" | sha256sum --check --status
test ! -e /etc/systemd/system/luckin-random.service || {
  echo 'Existing deployment found: use the documented upgrade procedure.' >&2; exit 1;
}
nginx -t
! ss -lntH | awk '{print $4}' | grep -Eq ":(${TLS_PORT}|${BACKEND_PORT}|80)$"
SNAPSHOT=/var/backups/luckin-random/bootstrap-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 700 "$SNAPSHOT"
tar -czf "$SNAPSHOT/nginx-before.tar.gz" -C /etc nginx
if test -d /etc/nginx/stream.d; then
  find /etc/nginx/stream.d -type f -exec sha256sum {} \; > "$SNAPSHOT/stream-before.sha256"
fi
install -d -m 755 /var/lib/luckin-random-acme/.well-known/acme-challenge
SITE=/etc/nginx/sites-available/luckin-random
test ! -e "$SITE"
cat > "$SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $PUBLIC_IP;
    access_log off;
    location ^~ /.well-known/acme-challenge/ { root /var/lib/luckin-random-acme; }
    location / { return 404; }
}
EOF
ln -s "$SITE" /etc/nginx/sites-enabled/luckin-random
if ! nginx -t; then
  rm /etc/nginx/sites-enabled/luckin-random "$SITE"
  exit 1
fi
systemctl reload nginx
CERTBOT=$(command -v certbot || true)
test -n "$CERTBOT" || CERTBOT=/snap/bin/certbot
"$CERTBOT" certonly --non-interactive --agree-tos --register-unsafely-without-email --webroot \
  --webroot-path /var/lib/luckin-random-acme --preferred-profile shortlived \
  --ip-address "$PUBLIC_IP" --cert-name "$PUBLIC_IP" \
  --deploy-hook '/usr/sbin/nginx -t && /bin/systemctl reload nginx'
openssl x509 -in "/etc/letsencrypt/live/$PUBLIC_IP/fullchain.pem" -checkend 86400 -noout
if systemctl cat snap.certbot.renew.timer >/dev/null 2>&1; then
  systemctl enable --now snap.certbot.renew.timer
fi

install -d -m 755 /opt/luckin-random/runtime /opt/luckin-random/releases
NODE_DIR=/opt/luckin-random/runtime/node-v${NODE_VERSION}-linux-x64
if ! test -x "$NODE_DIR/bin/node"; then
  ARCHIVE="$SNAPSHOT/node.tar.xz"
  curl --fail --location --retry 2 --connect-timeout 15 --max-time 300 \
    "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" -o "$ARCHIVE"
  printf '%s  %s\n' "$NODE_SHA256" "$ARCHIVE" | sha256sum --check --status
  tar -xJf "$ARCHIVE" -C /opt/luckin-random/runtime
fi
chown -R root:root "$NODE_DIR"
chmod -R go-w "$NODE_DIR"
export PATH="$NODE_DIR/bin:$PATH"
node --version
RELEASE=/opt/luckin-random/releases/$RELEASE_ID
test ! -e "$RELEASE"
install -d -m 755 "$RELEASE"
tar -xzf "$PACKAGE" -C "$RELEASE" --no-same-owner
chown -R root:root "$RELEASE"
chmod -R go-w "$RELEASE"
cd "$RELEASE"
# Compile and install locked pure-JavaScript dependencies on the development
# machine. Constrain the target-side runtime tests on small-memory servers.
test -f dist/src/main.js
test -d node_modules/ajv
systemd-run --quiet --wait --pipe --unit="luckin-test-$RELEASE_ID" \
  -p "WorkingDirectory=$RELEASE" -p MemoryMax=140M -p MemorySwapMax=192M \
  -p CPUQuota=50% /usr/bin/timeout 90 "$NODE_DIR/bin/node" --max-old-space-size=80 \
  --test dist/test/*.test.js > "$SNAPSHOT/backend-tests.txt" 2>&1 || {
  tail -n 60 "$SNAPSHOT/backend-tests.txt"; exit 1;
}
tail -n 9 "$SNAPSHOT/backend-tests.txt"
id luckin-random >/dev/null 2>&1 || useradd --system --home-dir /var/lib/luckin-random --shell /usr/sbin/nologin luckin-random
install -d -m 750 -o luckin-random -g luckin-random /var/lib/luckin-random
install -d -m 750 -o root -g luckin-random /etc/luckin-random
test ! -e /etc/luckin-random/server.env
MCP_MODE="$MCP_MODE" BACKEND_PORT="$BACKEND_PORT" python3 <<'PY'
import os,secrets
from pathlib import Path
p=Path('/etc/luckin-random/server.env')
p.write_text('\n'.join([
 'HOST=127.0.0.1','PORT='+os.environ['BACKEND_PORT'],
 'DATABASE_PATH=/var/lib/luckin-random/luckin.sqlite',
 'API_KEY='+secrets.token_hex(32),'ENCRYPTION_KEY='+secrets.token_hex(32),
 'MCP_MODE='+os.environ['MCP_MODE'],'ALLOW_LIVE_ORDERS=false',
 'LIVE_CONTRACT_VERIFIED=false','ALLOW_LOOPBACK_HTTP=false','TZ=Asia/Shanghai','']))
PY
chown root:luckin-random /etc/luckin-random/server.env
chmod 640 /etc/luckin-random/server.env
ln -s "$RELEASE" /opt/luckin-random/current
cat > /etc/systemd/system/luckin-random.service <<EOF
[Unit]
Description=Luckin Random single-user backend
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5
[Service]
Type=simple
User=luckin-random
Group=luckin-random
WorkingDirectory=/opt/luckin-random/current
EnvironmentFile=/etc/luckin-random/server.env
ExecStart=$NODE_DIR/bin/node --max-old-space-size=96 dist/src/main.js
Restart=on-failure
RestartSec=5
MemoryHigh=100M
MemoryMax=140M
MemorySwapMax=192M
CPUQuota=70%
TimeoutStopSec=30
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/luckin-random
CapabilityBoundingSet=
RestrictSUIDSGID=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now luckin-random
sleep 2
systemctl is-active --quiet luckin-random

cat >> "$SITE" <<EOF
server {
    listen $TLS_PORT ssl;
    listen [::]:$TLS_PORT ssl;
    server_name $PUBLIC_IP;
    ssl_certificate /etc/letsencrypt/live/$PUBLIC_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PUBLIC_IP/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    client_max_body_size 1m;
    access_log off;
    location /v1/ {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Origin \$http_origin;
        proxy_connect_timeout 5s;
        proxy_read_timeout 70s;
    }
    location / { return 404; }
}
EOF
nginx -t
systemctl reload nginx
if ufw status | grep -q '^Status: active'; then ufw allow "$TLS_PORT/tcp"; fi
if test -s "$SNAPSHOT/stream-before.sha256"; then sha256sum --check "$SNAPSHOT/stream-before.sha256"; fi
echo "Deployment installed; run external HTTPS, authentication, persistence and renewal checks."
