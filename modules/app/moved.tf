moved {
  from = google_cloudbuild_trigger.transformer
  to   = google_cloudbuild_trigger.images["transformer"]
}
moved {
  from = google_cloudbuild_trigger.loader
  to   = google_cloudbuild_trigger.images["loader"]
}
moved {
  from = google_cloudbuild_trigger.extractor
  to   = google_cloudbuild_trigger.images["extractor"]
}