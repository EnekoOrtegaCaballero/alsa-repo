variable "project_id" {
  description = "ID del proyecto de GCP"
  type        = string
}

variable "region" {
  description = "Región de GCP"
  type        = string
  default     = "europe-southwest1"
}

variable "zone" {
  description = "Zona principal de GCP"
  type        = string
  default     = "europe-southwest1-b"
}

variable "zone_replica" {
  description = "Zona secundaria para la réplica de AD (debe ser distinta a zone para HA)"
  type        = string
  default     = "europe-southwest1-c"
}

variable "domain_name" {
  description = "Nombre de dominio para Active Directory"
  type        = string
  default     = "acme.local"
}

variable "ad_password" {
  description = "Contraseña segura para el Administrador de Active Directory"
  type        = string
  sensitive   = true
}

variable "zabbix_server" {
  description = "Servidor Zabbix (ej: zabbix.enekoortega.com)"
  type        = string
  default     = "zabbix.enekoortega.com"
}

variable "zabbix_user" {
  description = "Usuario para conectarse a Zabbix (agente/API)"
  type        = string
}

variable "zabbix_pass" {
  description = "Contraseña para conectarse a Zabbix"
  type        = string
  sensitive   = true
}

variable "loki_url" {
  description = "URL endpoint Loki para Promtail"
  type        = string
  default     = "http://grafana.enekoortega.com:3100/loki/api/v1/push"
}

variable "vps_ip" {
  description = "IP estática del Servidor VPS (enekoortega.com) para whitelist HTTP/RDP/Zabbix"
  type        = string
}

variable "git_repo_url" {
  description = "URL del repositorio git con el código fuente de las API"
  type        = string
}
