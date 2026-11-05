#!/usr/bin/env bash
# Upgrade an existing single-user instance without replacing its data or keys.
set -euo pipefail
umask 077
: "${PACKAGE:?Set uploaded runtime package}"
: "${PACKAGE_SHA256:?Set verified package SHA256}"
: "${RELEASE_ID:?Set a new release identifier}"
[[ "$RELEASE_ID" =~ ^[A-Za-z0-9_-]{1,80}$ ]]
test "$(id -u)" = 0
printf '%s  %s\n' "$PACKAGE_SHA256" "$PACKAGE" | sha256sum --check --status
PREVIOUS=$(readlink -f /opt/luckin-random/current)
[[ "$PREVIOUS" == /opt/luckin-random/releases/* ]]
RELEASE=/opt/luckin-random/releases/$RELEASE_ID
test ! -e "$RELEASE"
NODE_BIN=${NODE_BIN:-/opt/luckin-random/runtime/node-v22.23.4-linux-x64/bin/node}
SNAPSHOT=/var/backups/luckin-random/upgrade-$RELEASE_ID
install -d -m 700 "$SNAPSHOT"
install -d -m 755 "$RELEASE"
tar -xzf "$PACKAGE" -C "$RELEASE" --no-same-owner
chown -R root:root "$RELEASE"
chmod -R go-w "$RELEASE"
cd "$RELEASE"
systemd-run --quiet --wait --pipe --unit="luckin-test-$RELEASE_ID" \
  -p "WorkingDirectory=$RELEASE" -p MemoryMax=140M -p MemorySwapMax=192M \
  -p CPUQuota=50% /usr/bin/timeout 90 "$NODE_BIN" --max-old-space-size=80 \
  --test dist/test/*.test.js > "$SNAPSHOT/backend-tests.txt" 2>&1 || {
    tail -n 60 "$SNAPSHOT/backend-tests.txt"; exit 1;
  }
tail -n 9 "$SNAPSHOT/backend-tests.txt"
sha256sum /etc/luckin-random/server.env > "$SNAPSHOT/environment-before.sha256"
systemctl stop luckin-random
rollback() {
  trap - ERR
  echo 'Upgrade failed; checking database compatibility before reverting code.' >&2
  if python3 - "$SNAPSHOT/database.sqlite" <<'PY'
import sqlite3,sys
def version(path):
 c=sqlite3.connect('file:'+path+'?mode=ro',uri=True)
 try:return c.execute('SELECT MAX(version) FROM migrations').fetchone()[0]
 finally:c.close()
assert version('/var/lib/luckin-random/luckin.sqlite') == version(sys.argv[1])
PY
  then
    ln -sfn "$PREVIOUS" /opt/luckin-random/current
    systemctl start luckin-random
  else
    echo 'Database version changed: service kept stopped for an audited recovery.' >&2
  fi
  exit 1
}
trap rollback ERR
python3 - "$SNAPSHOT/database.sqlite" <<'PY'
import sqlite3,sys,os
source=sqlite3.connect('file:/var/lib/luckin-random/luckin.sqlite?mode=ro',uri=True)
target=sqlite3.connect(sys.argv[1])
try:
 source.backup(target)
 assert target.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
finally:source.close();target.close()
os.chmod(sys.argv[1],0o600)
PY
ln -sfn "$RELEASE" /opt/luckin-random/current
systemctl start luckin-random
sleep 2
systemctl is-active --quiet luckin-random
sha256sum --check "$SNAPSHOT/environment-before.sha256"
trap - ERR
echo 'UPGRADE_INSTALLED; configuration, secrets and history kept in the same database.'
