resource "google_compute_network" "chess" {
  name                    = "chess-vpc-${var.env}"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "chess" {
  name                     = "chess-subnet-${var.env}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.chess.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_router" "chess" {
  name    = "chess-router-${var.env}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.chess.id
}

resource "google_compute_router_nat" "chess" {
  name                               = "chess-nat-${var.env}"
  project                            = var.project_id
  router                             = google_compute_router.chess.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "beam-to-es" {
  name    = "chess-beam-to-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200", "9300"]
  }

  source_tags = ["beam-worker"]
  target_tags = ["elasticsearch"]
}

resource "google_compute_firewall" "vpc-to-es" {
  name    = "chess-vpc-to-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = [google_compute_subnetwork.chess.ip_cidr_range]
  target_tags   = ["elasticsearch"]
}

resource "google_compute_firewall" "iap-ssh" {
  name    = "chess-iap-ssh-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["elasticsearch"]
}

resource "google_compute_firewall" "iap-es" {
  name    = "chess-iap-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["elasticsearch"]
}

resource "google_compute_firewall" "dataflow-internal" {
  name    = "chess-dataflow-internal-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["12345", "12346"]
  }

  source_tags = ["beam-worker"]
  target_tags = ["beam-worker"]
}