# Helpers shared by the test-batch-pipeline*.R files.

write_project <- function(dir, grid_lines, keep = TRUE) {
  writeLines(grid_lines, file.path(dir, "spec.yaml"))
  writeLines(c(
    "library(targets)",
    "tar_option_set(error = \"continue\", memory = \"transient\")",
    paste0("wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\", keep_step2 = ", keep, ")")
  ), file.path(dir, "_targets.R"))
}

make_it <- function(dir) {
  # _targets.R runs in the global environment: in a helper file the default (the
  # caller's frame) does not see the targets functions that library(targets) attaches.
  withr::with_dir(dir, targets::tar_make(callr_function = NULL, reporter = "silent", envir = globalenv()))
}

# Branch counts per dynamic target after the last run.
progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("data_frames", "data_tables", "weather_tables"), ])
  rownames(p) <- p$name
  p
}
