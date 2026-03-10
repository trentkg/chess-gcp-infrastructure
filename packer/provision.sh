#!/bin/bash
set -euxo pipefail

# ── Install Elasticsearch ────────────────────────────────────────
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg

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

# ── Heap size ────────────────────────────────────────────────────
# Provisioned for an e2 small right now
echo "-Xms${ES_HEAP_SIZE}" > /etc/elasticsearch/jvm.options.d/heap.options
echo "-Xmx${ES_HEAP_SIZE}" >> /etc/elasticsearch/jvm.options.d/heap.options

# ── Configure Elasticsearch ──────────────────────────────────────
# Note: no password or data path here - that happens at boot
cat > /etc/elasticsearch/elasticsearch.yml <<CONFIG
node.name: chess-es-node
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
CONFIG

systemctl daemon-reload
systemctl enable elasticsearch
