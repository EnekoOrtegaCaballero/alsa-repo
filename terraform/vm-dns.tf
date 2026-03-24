# Asumimos que la zona ya existe en GCP (creada por el script import_dns_csv.sh)
data "google_dns_managed_zone" "enekoortega_com" {
  name = "enekoortega-com-zone"
}

# --- NUEVOS REGISTROS HÍBRIDOS (Dinámicos) ---
# Se añaden automáticamente a la zona preexistente cuando se levanta Terraform

# Registro A para Active Directory
resource "google_dns_record_set" "ad_a" {
  name         = "ad.${data.google_dns_managed_zone.enekoortega_com.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.enekoortega_com.name
  rrdatas = [
    google_compute_instance.acme_ad_primary.network_interface.0.access_config.0.nat_ip,
    google_compute_instance.acme_ad_replica.network_interface.0.access_config.0.nat_ip
  ]
}

# Registro A para Mantenimiento
resource "google_dns_record_set" "mantenimiento_a" {
  name         = "mantenimiento.${data.google_dns_managed_zone.enekoortega_com.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.enekoortega_com.name
  rrdatas      = [google_compute_instance.api_mantenimiento.network_interface.0.access_config.0.nat_ip]
}

# Registro A para Horarios (Apunta a la IP de la Forwarding Rule del MIG Load Balancer)
resource "google_dns_record_set" "horarios_a" {
  name         = "horarios.${data.google_dns_managed_zone.enekoortega_com.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.enekoortega_com.name
  rrdatas      = [google_compute_forwarding_rule.horarios_lb.ip_address]
}
