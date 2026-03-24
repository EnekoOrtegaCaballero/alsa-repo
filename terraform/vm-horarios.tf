# Plantilla de instancia para el clúster autoescalable de horarios
resource "google_compute_instance_template" "horarios_template" {
  name_prefix  = "api-horarios-template-"
  machine_type = "e2-micro"
  region       = var.region

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network    = google_compute_network.vpc_acme.id
    subnetwork = google_compute_subnetwork.subnet_apps.id
    access_config {
      # Mantenemos IP pública para simplificar reglas NAT
    }
  }

  metadata_startup_script = templatefile("../scripts/startup-horarios.sh", {
    zabbix_url = var.zabbix_server
    loki_url   = var.loki_url
  })

  tags = ["http-server", "api-horarios"]

  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Group base
resource "google_compute_instance_group_manager" "horarios_mig" {
  name               = "api-horarios-mig"
  base_instance_name = "horarios"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.horarios_template.id
    name              = "primary"
  }

  named_port {
    name = "http"
    port = 80
  }
}

# Autoescalador basado en CPU
resource "google_compute_autoscaler" "horarios_autoscaler" {
  name   = "api-horarios-autoscaler"
  zone   = var.zone
  target = google_compute_instance_group_manager.horarios_mig.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 1
    cooldown_period = 480 # 8 minutos: el startup-script de e2-micro necesita tiempo

    cpu_utilization {
      target = 0.85 # Escala si la CPU supera el 85%
    }
  }
}

# Health Check para el Load Balancer
resource "google_compute_region_health_check" "horarios_hc" {
  name               = "api-horarios-hc"
  region             = var.region
  timeout_sec        = 5
  check_interval_sec = 10

  http_health_check {
    port = "80"
  }
}

# Backend Service L4 (Network Load Balancer)
resource "google_compute_region_backend_service" "horarios_backend" {
  name                  = "api-horarios-backend"
  region                = var.region
  health_checks         = [google_compute_region_health_check.horarios_hc.id]
  load_balancing_scheme = "EXTERNAL"

  backend {
    group          = google_compute_instance_group_manager.horarios_mig.instance_group
    balancing_mode = "CONNECTION"
  }
}

# Forwarding Rule (Punto de entrada con IP estática única)
resource "google_compute_forwarding_rule" "horarios_lb" {
  name                  = "api-horarios-lb"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  backend_service       = google_compute_region_backend_service.horarios_backend.id
}
