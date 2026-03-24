resource "google_compute_instance" "api_mantenimiento" {
  name         = "mantenimiento-enekoortega-com"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_acme.id
    subnetwork = google_compute_subnetwork.subnet_apps.id
    access_config {
      # IP pública para acceder desde tu PC/VPS
    }
  }

  metadata_startup_script = templatefile("../scripts/startup-mantenimiento.sh", {
    ad_server_ip  = google_compute_instance.acme_ad_primary.network_interface.0.network_ip
    ad_replica_ip = google_compute_instance.acme_ad_replica.network_interface.0.network_ip
    zabbix_url    = var.zabbix_server
    loki_url      = var.loki_url
    api_app_py    = file("../api/app.py")
    api_reqs      = file("../api/requirements.txt")
    api_docker    = file("../api/Dockerfile")
  })

  # El tag "http-server" hace que se le apliquen las reglas de firewall allow-http-restricted
  tags = ["http-server", "api-mantenimiento"]
}
