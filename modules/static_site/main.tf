locals {
  bucket_name = "${var.prefix}-${var.environment}-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "google_storage_bucket" "site" {
  name                        = local.bucket_name
  project                     = var.project_id
  location                    = var.location
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  versioning {
    enabled = true
  }

  labels = var.labels
}

resource "google_storage_bucket_iam_member" "publico" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "index" {
  name         = "index.html"
  bucket       = google_storage_bucket.site.name
  source       = var.index_file
  content_type = "text/html"

  depends_on = [google_storage_bucket_iam_member.publico]
}
