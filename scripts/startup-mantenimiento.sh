#!/bin/bash
echo ">>> [INIT] Iniciando configuración de VM API Mantenimiento..."

# Variables inyectadas por Terraform templatefile
AD_SERVER_IP="${ad_server_ip}"
AD_REPLICA_IP="${ad_replica_ip}"
ZABBIX_URL="${zabbix_url}"
LOKI_URL="${loki_url}"

# 1. Dependencias y Docker
echo ">>> [INSTALL] Docker..."
apt-get update && apt-get install -y curl apt-transport-https ca-certificates software-properties-common gnupg lsb-release
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
apt-get install -y docker-compose-plugin

# 2. Escribir código local y compilar API
echo ">>> [APP] Escribiendo código local y compilando API Mantenimiento..."
mkdir -p /opt/acme/api
cd /opt/acme/api

cat <<'EOF_APP' > app.py
${api_app_py}
EOF_APP

cat <<'EOF_REQ' > requirements.txt
${api_reqs}
EOF_REQ

cat <<'EOF_DOC' > Dockerfile
${api_docker}
EOF_DOC

docker build -t api-mantenimiento-acme:v1 .

# Arrancamos la API con ambas IPs para failover
docker run -d --restart unless-stopped \
  --name api-mantenimiento \
  -p 8080:8080 \
  -e AD_SERVER_IP=$AD_SERVER_IP \
  -e AD_REPLICA_IP=$AD_REPLICA_IP \
  api-mantenimiento-acme:v1

# 3. Zabbix Agent 2
echo ">>> [ZABBIX] Configurando Agente..."
MY_REAL_HOSTNAME=$(hostname)
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu22.04_all.deb
dpkg -i zabbix-release_7.0-1+ubuntu22.04_all.deb
apt-get update
apt-get install -y zabbix-agent2

# Reemplazar valores por defecto en el config principal (el drop-in NO los sobreescribe)
sed -i "s/^Server=127.0.0.1/Server=$ZABBIX_URL/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=127.0.0.1/ServerActive=$ZABBIX_URL/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=Zabbix server/Hostname=$MY_REAL_HOSTNAME/" /etc/zabbix/zabbix_agent2.conf

# Inyectar HostMetadata si no existe (CRÍTICO para Auto-Registro)
grep -q "^HostMetadata=" /etc/zabbix/zabbix_agent2.conf || \
  echo "HostMetadata=Linux-App-Acme" >> /etc/zabbix/zabbix_agent2.conf

systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

# 4. Promtail (para Grafana/Loki)
echo ">>> [PROMTAIL] Configurando recolección de logs JSON..."
mkdir -p /opt/promtail
cat <<YAML > /opt/promtail/config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: $LOKI_URL
scrape_configs:
  - job_name: api-mantenimiento
    static_configs:
      - targets:
          - localhost
        labels:
          job: api-mantenimiento
          instance: $MY_REAL_HOSTNAME
          __path__: /var/lib/docker/containers/*/*-json.log
    pipeline_stages:
      - docker: {}
      - json:
          expressions:
            method: method
            path: path
            status: status
            response_time_ms: response_time_ms
            service: service
            traceID: traceID
      - labels:
          method:
          status:
          service:
          traceID:
YAML

docker run -d --name promtail \
  --restart unless-stopped \
  -v /var/lib/docker/containers:/var/lib/docker/containers \
  -v /opt/promtail/config.yaml:/etc/promtail/config.yml \
  grafana/promtail:latest -config.file=/etc/promtail/config.yml

echo ">>> [DONE] VM Mantenimiento lista."
