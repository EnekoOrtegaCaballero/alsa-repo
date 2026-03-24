output "my_detected_ip" {
  value       = data.http.my_ip.response_body
  description = "La IP pública detectada desde donde estás ejecutando Terraform"
}

output "ad_primary_public_ip" {
  value       = google_compute_instance.acme_ad_primary.network_interface.0.access_config.0.nat_ip
  description = "IP pública del servidor Windows PDC en Zona A (conéctate por RDP al puerto 3389)"
}

output "ad_primary_private_ip" {
  value       = google_compute_instance.acme_ad_primary.network_interface.0.network_ip
  description = "IP privada del Servidor PDC (usada internamente por la API Mantenimiento y Réplica)"
}

output "ad_replica_public_ip" {
  value       = google_compute_instance.acme_ad_replica.network_interface.0.access_config.0.nat_ip
  description = "IP pública del servidor Windows Secundario en Zona B"
}

output "ad_replica_private_ip" {
  value       = google_compute_instance.acme_ad_replica.network_interface.0.network_ip
  description = "IP privada del Servidor Secundario"
}

output "mantenimiento_public_ip" {
  value       = google_compute_instance.api_mantenimiento.network_interface.0.access_config.0.nat_ip
  description = "IP pública de la VM de la API de Mantenimiento"
}

output "horarios_load_balancer_ip" {
  value       = google_compute_forwarding_rule.horarios_lb.ip_address
  description = "IP pública del Load Balancer de Horarios (donde apunta horarios.enekoortega.com)"
}

output "dns_nameservers" {
  value       = data.google_dns_managed_zone.enekoortega_com.name_servers
  description = "¡IMPORTANTE! Si acabas de ejecutar el script bash import_dns_csv.sh esto debería coincidir con lo que tienes en tu registrador."
}
