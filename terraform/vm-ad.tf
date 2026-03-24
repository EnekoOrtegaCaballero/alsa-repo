# Active Directory PDC (Controlador Principal) en la zona primaria
resource "google_compute_instance" "acme_ad_primary" {
  name         = "ad1"
  machine_type = "e2-standard-2"
  zone         = var.zone # Zona primaria


  boot_disk {
    initialize_params {
      image = "windows-cloud/windows-2022"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_acme.id
    subnetwork = google_compute_subnetwork.subnet_ad.id
    access_config {
      # Asigna IP pública para RDP
    }
  }

  metadata = {
    windows-startup-script-ps1 = templatefile("../scripts/startup-ad-primary.ps1", {
      ad_domain     = var.domain_name
      ad_password   = var.ad_password
      zabbix_server = var.zabbix_server
    })
  }

  tags = ["ad-server"]
}

# Active Directory Réplica (Controlador Secundario) en zona secundaria
resource "google_compute_instance" "acme_ad_replica" {
  name         = "ad2"
  machine_type = "e2-standard-2"
  zone         = var.zone_replica # Zona secundaria para HA


  boot_disk {
    initialize_params {
      image = "windows-cloud/windows-2022"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_acme.id
    subnetwork = google_compute_subnetwork.subnet_ad.id
    access_config {
      # Asigna IP pública para RDP
    }
  }

  metadata = {
    windows-startup-script-ps1 = templatefile("../scripts/startup-ad-replica.ps1", {
      ad_domain     = var.domain_name
      ad_password   = var.ad_password
      zabbix_server = var.zabbix_server
      pdc_ip        = google_compute_instance.acme_ad_primary.network_interface.0.network_ip
    })
  }

  tags = ["ad-server"]

  depends_on = [google_compute_instance.acme_ad_primary]
}
