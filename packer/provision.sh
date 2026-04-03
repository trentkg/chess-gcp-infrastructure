#!/bin/bash
set -euxo pipefail

# ── Install Elasticsearch ────────────────────────────────────────
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg jq
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | tee /etc/apt/sources.list.d/elastic-8.x.list
echo "Package: elasticsearch
Pin: version 8.13.4
Pin-Priority: 1001" > /etc/apt/preferences.d/elasticsearch
apt-get update -y
apt-get install -y elasticsearch=8.13.4

# ── Kernel settings ──────────────────────────────────────────────
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# ── Configure Elasticsearch ──────────────────────────────────────
cat > /etc/elasticsearch/elasticsearch.yml <<CONFIG
node.name: chess-es-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
CONFIG

# ── Data directory (placeholder — real mount happens at boot) ────
mkdir -p /var/lib/elasticsearch
chown elasticsearch:elasticsearch /var/lib/elasticsearch

# ── Boot-time disk setup script ──────────────────────────────────
cat > /usr/local/bin/es-boot-setup.sh <<'BOOT'
#!/bin/bash
set -euo pipefail

DATA_DISK="/dev/disk/by-id/google-es-data"
MOUNT_POINT="/var/lib/elasticsearch"

# Set heap size from instance metadata
HEAP_SIZE=$(curl -sf \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/es-heap-size" \
  -H "Metadata-Flavor: Google" || true)

if [ -n "$HEAP_SIZE" ]; then
  echo "es-boot-setup: heap size from instance metadata: ${HEAP_SIZE}"
else
  HEAP_SIZE="2g"
  echo "es-boot-setup: heap size not found in metadata, using default: ${HEAP_SIZE}"
fi

echo "-Xms${HEAP_SIZE}" > /etc/elasticsearch/jvm.options.d/heap.options
echo "-Xmx${HEAP_SIZE}" >> /etc/elasticsearch/jvm.options.d/heap.options

# Wait for the data disk to appear (up to 30s)
for i in $(seq 1 30); do
  if [ -b "$DATA_DISK" ]; then break; fi
  echo "Waiting for data disk... ($i)"
  sleep 1
done

if [ ! -b "$DATA_DISK" ]; then
  echo "ERROR: Data disk not found at $DATA_DISK" >&2
  exit 1
fi

# Format if this is a fresh disk (no filesystem yet)
if ! blkid "$DATA_DISK" | grep -q ext4; then
  mkfs.ext4 -F "$DATA_DISK"
fi

# Only mount if not already mounted — prevents failure on preemptible VM restarts
if ! mountpoint -q "$MOUNT_POINT"; then
  mount "$DATA_DISK" "$MOUNT_POINT"
fi

# Resize filesystem to fill available disk space (no-op if already full size)
resize2fs "$DATA_DISK"

chown -R elasticsearch:elasticsearch "$MOUNT_POINT"
chmod 750 "$MOUNT_POINT"
BOOT
chmod +x /usr/local/bin/es-boot-setup.sh

# ── Boot-time password setup script ─────────────────────────────
cat > /usr/local/bin/es-set-password.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

PROJECT_ID=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/project/project-id" \
  -H "Metadata-Flavor: Google")

ES_PASSWORD=$(gcloud secrets versions access latest \
  --secret="chess-es-password" \
  --project="$PROJECT_ID") || { echo "ERROR: secret fetch failed" >&2; exit 1; }

# Wait for ES to be up — accept 200 (no auth) or 401 (security enabled, ES ready)
echo "Waiting for Elasticsearch..."
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9200/ 2>/dev/null || true)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "401" ]; then
    echo "Elasticsearch is up (http_status=$STATUS)"
    break
  fi
  echo "  attempt $i: http_status=$STATUS"
  sleep 3
done

# On first boot ES writes a bootstrap password to its log — use it if present,
# otherwise assume the password has already been set (re-run case) and use the
# secret itself as the current credential.
BOOTSTRAP_PASSWORD=$(grep -oP "(?<=generated password for the elastic built-in superuser is : ).*" \
  /var/log/elasticsearch/*.log 2>/dev/null | tail -1 | tr -d '[:space:]' || true)

CURRENT_PASSWORD="${BOOTSTRAP_PASSWORD:-$ES_PASSWORD}"

HTTP_STATUS=$(curl -s -o /tmp/es-pw-response.json -w "%{http_code}" \
  -X POST "http://localhost:9200/_security/user/elastic/_password" \
  -u "elastic:${CURRENT_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg p "$ES_PASSWORD" '{password: $p}')")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "Password set successfully."
else
  echo "ERROR: password reset returned HTTP $HTTP_STATUS" >&2
  cat /tmp/es-pw-response.json >&2
  exit 1
fi
SCRIPT
chmod +x /usr/local/bin/es-set-password.sh

# ── Systemd unit: disk mount (runs before ES) ────────────────────
cat > /etc/systemd/system/es-boot-setup.service <<'UNIT'
[Unit]
Description=Elasticsearch data disk mount and setup
Before=elasticsearch.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/es-boot-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

# ── Systemd unit: password set (runs after ES, restartable) ──────
cat > /etc/systemd/system/es-set-password.service <<'UNIT'
[Unit]
Description=Set Elasticsearch elastic user password from Secret Manager
After=elasticsearch.service
Requires=elasticsearch.service

[Service]
Type=simple
ExecStart=/usr/local/bin/es-set-password.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

# ── Drop-in to make elasticsearch wait for disk mount ────────────
mkdir -p /etc/systemd/system/elasticsearch.service.d
cat > /etc/systemd/system/elasticsearch.service.d/wait-for-mount.conf <<'DROP'
[Unit]
After=es-boot-setup.service
Requires=es-boot-setup.service
DROP

# ── Enable services (do NOT start — disk absent during bake) ─────
systemctl daemon-reload
systemctl enable es-boot-setup
systemctl enable elasticsearch
systemctl enable es-set-password