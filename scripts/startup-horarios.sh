#!/bin/bash
echo ">>> [INIT] Iniciando configuración de VM API Horarios (MIG)..."

# Variables inyectadas por Terraform templatefile
ZABBIX_URL="${zabbix_url}"
LOKI_URL="${loki_url}"

# 1. Dependencias y Docker
echo ">>> [INSTALL] Docker..."
apt-get update && apt-get install -y curl apt-transport-https ca-certificates software-properties-common gnupg lsb-release jq
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
apt-get install -y docker-compose-plugin

# 2. Despliegue de API Estática (Simulada para testear autoscaling)
echo ">>> [APP] Creando servidor web Nginx simulando horarios..."
mkdir -p /opt/acme/horarios
cat <<JSON > /opt/acme/horarios/horarios.json
{
  "status": "success",
  "data": [
    {"ruta": "Madrid-Oviedo", "salida": "10:00", "plazas": 12},
    {"ruta": "Madrid-Gijón", "salida": "12:30", "plazas": 4}
  ],
  "message": "Generado desde API Horarios autoescalable"
}
JSON

cat <<CONF > /opt/acme/horarios/default.conf
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index horarios.json;
        default_type application/json;
    }
}
CONF

docker run -d --restart unless-stopped \
  --name api-horarios \
  -p 80:80 \
  -v /opt/acme/horarios/horarios.json:/usr/share/nginx/html/horarios.json \
  -v /opt/acme/horarios/default.conf:/etc/nginx/conf.d/default.conf \
  nginx:alpine

# Carga de CPU simuladora (para forzar autoescalado si nos hacen peticiones GET /cpu_burn)
# Este script consume CPU artificialmente para las pruebas de MIG
cat <<'EOF' > /opt/acme/horarios/cpu_burner.sh
#!/bin/bash
while true; do
  for i in {1..1000000}; do
    x=$((i*i))
  done
done
EOF
chmod +x /opt/acme/horarios/cpu_burner.sh

# 3. Zabbix Agent 2
echo ">>> [ZABBIX] Configurando Agente..."
MY_REAL_HOSTNAME=$(hostname)
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu22.04_all.deb
dpkg -i zabbix-release_7.0-1+ubuntu22.04_all.deb
apt-get update
apt-get install -y zabbix-agent2

# Reemplazar valores por defecto en el config principal
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
  - job_name: api-horarios
    static_configs:
      - targets:
          - localhost
        labels:
          job: api-horarios
          instance: $MY_REAL_HOSTNAME
          __path__: /var/lib/docker/containers/*/*-json.log
    pipeline_stages:
      - docker: {}
YAML

docker run -d --name promtail \
  --restart unless-stopped \
  -v /var/lib/docker/containers:/var/lib/docker/containers \
  -v /opt/promtail/config.yaml:/etc/promtail/config.yml \
  grafana/promtail:latest -config.file=/etc/promtail/config.yml

echo ">>> [DONE] VM Horarios (MIG) lista."
