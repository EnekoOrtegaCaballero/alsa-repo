#!/bin/bash
# Este script crea la zona DNS en GCP e importa los registros del CSV desde ya
# No depende de Terraform.

# SUSTITUYE TU PROJECT ID DE GOOGLE CLOUD AQUÍ
PROJECT_ID="acme-interview"
ZONE_NAME="enekoortega-com-zone"
DNS_NAME="enekoortega.com."

echo ">>> [1] Creando la zona DNS gestionada: $ZONE_NAME"
gcloud dns managed-zones create $ZONE_NAME \
    --dns-name=$DNS_NAME \
    --description="Zona DNS principal (Migrada desde CSV)" \
    --project=$PROJECT_ID \
    || echo "La zona ya existe, continuando..."

echo ">>> [2] Iniciando transacción para volcar el CSV de enekoortega.com..."
gcloud dns record-sets transaction start --zone=$ZONE_NAME --project=$PROJECT_ID

# --- Registros A directos ---
# Dominio principal
gcloud dns record-sets transaction add "51.91.156.141" --name="enekoortega.com." --ttl=300 --type=A --zone=$ZONE_NAME --project=$PROJECT_ID
# Subdominios administrativos
gcloud dns record-sets transaction add "51.91.156.141" --name="admin.enekoortega.com." --ttl=300 --type=A --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "51.91.156.141" --name="grafana.enekoortega.com." --ttl=300 --type=A --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "51.91.156.141" --name="zabbix.enekoortega.com." --ttl=300 --type=A --zone=$ZONE_NAME --project=$PROJECT_ID

# --- Registros CNAME ---
gcloud dns record-sets transaction add "www.enekoortega.com." --name="*.enekoortega.com." --ttl=300 --type=CNAME --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "autoconfig.buzondecorreo.com." --name="autoconfig.enekoortega.com." --ttl=300 --type=CNAME --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "autodiscover.buzondecorreo.com." --name="autodiscover.enekoortega.com." --ttl=300 --type=CNAME --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "pdc.piensasolutions.com." --name="control.enekoortega.com." --ttl=300 --type=CNAME --zone=$ZONE_NAME --project=$PROJECT_ID

# --- Registros MX y TXT (SPF) para correo corporativo ---
gcloud dns record-sets transaction add "10 mx.buzondecorreo.com." --name="enekoortega.com." --ttl=300 --type=MX --zone=$ZONE_NAME --project=$PROJECT_ID
gcloud dns record-sets transaction add "\"v=spf1 include:_spf.buzondecorreo.com ~all\"" --name="enekoortega.com." --ttl=300 --type=TXT --zone=$ZONE_NAME --project=$PROJECT_ID


echo ">>> [3] Ejecutando transacción en Google Cloud..."
gcloud dns record-sets transaction execute --zone=$ZONE_NAME --project=$PROJECT_ID

echo ""
echo "✅ ¡Registros base creados con éxito!"
echo ""
echo ">> IMPORTANTE: Configura estos NameServers en tu registrador (DonDominio, GoDaddy, etc.) HOY MISMO para apuntar a GCP:"
gcloud dns managed-zones describe $ZONE_NAME --project=$PROJECT_ID --format="value(nameServers)"
