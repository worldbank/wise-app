library(targets)

# Workers share this machine: set WISEAPP_BATCH_WORKERS (run.R does) and, on a
# shared host, WISEAPP_BATCH_MEMORY_GB.
workers <- as.integer(Sys.getenv("WISEAPP_BATCH_WORKERS", "1"))
memory_gb <- Sys.getenv("WISEAPP_BATCH_MEMORY_GB", "")

tar_option_set(
  packages = "wiseapp",
  error = "continue",
  memory = "transient",
  garbage_collection = TRUE,
  controller = wiseapp::wise_batch_controller(
    workers = workers,
    memory_gb = if (nzchar(memory_gb)) as.numeric(memory_gb)
  )
)

wiseapp::wise_targets("spec.yaml", out_dir = "results")
