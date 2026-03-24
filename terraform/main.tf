provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Obtiene la IP con la que estamos lanzando Terraform
data "http" "my_ip" {
  url = "https://api.ipify.org?format=text"
}

# Red Virtual
resource "google_compute_network" "vpc_acme" {
  name                    = "acme-hibrida-vpc"
  auto_create_subnetworks = false
}

# Subredes
resource "google_compute_subnetwork" "subnet_ad" {
  name          = "subnet-ad"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_acme.id
}

resource "google_compute_subnetwork" "subnet_apps" {
  name          = "subnet-apps"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_acme.id
}

# Firewall
resource "google_compute_firewall" "allow_internal" {
  name    = "acme-allow-internal"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
  description   = "Permite todo el tráfico interno entre las subredes VPC"
}

resource "google_compute_firewall" "allow_rdp_restricted" {
  name    = "acme-allow-rdp-restricted"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  source_ranges = [
    "${data.http.my_ip.response_body}/32",
    "${var.vps_ip}/32"
  ]
  description = "Da acceso RDP al servidor Windows SOLO desde la IP local de tu PC actual y la del VPS"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "acme-allow-ssh"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [
    "${data.http.my_ip.response_body}/32",
    "${var.vps_ip}/32",
    "35.235.240.0/20" # Rango de IAP para SSH desde la consola de GCP
  ]
  description = "Da acceso SSH desde tu IP, el VPS y la consola de GCP (IAP)"
}

resource "google_compute_firewall" "allow_http_restricted" {
  name    = "acme-allow-http-restricted"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = [
    "${data.http.my_ip.response_body}/32",
    "${var.vps_ip}/32"
  ]
  target_tags = ["http-server"]
  description = "Da acceso HTTP/HTTPS a las VMs SOLO desde la IP local de tu PC actual y la del VPS (para proteger la API de intrusos)"
}

resource "google_compute_firewall" "allow_zabbix" {
  name    = "acme-allow-zabbix"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
    ports    = ["10050"]
  }

  source_ranges = [
    "${var.vps_ip}/32"
  ]
  description = "Da acceso a Zabbix Agent SOLO desde el Zabbix Server externo (VPS)"
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-gcp-health-checks"
  network = google_compute_network.vpc_acme.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags   = ["api-horarios"] # Asegúrate de que este tag es el que usa tu VM
  description   = "Permite las sondas de Health Check de Google Cloud Load Balancer a las instancias de la API"
}
