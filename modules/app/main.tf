resource "google_storage_bucket" "chess-games" {
  name          = "chess-games-raw-${var.env}"
  location      = "US"
  force_destroy = false 

  public_access_prevention = "enforced"
}

resource "google_storage_bucket_object" "sources-365" {
  name   = "sources/365-chess/" # folder name should end with '/'
  content = " "       # content is ignored but should be non-empty
  bucket = resource.chess-games.name 
}
