library(targets)

# Workers share this machine: set WISEAPP_BATCH_WORKERS (run.R does) and, on a
# shared host, WISEAPP_BATCH_MEMORY_GB. The Step 2 simulation runs hold
# hundreds of MB each, so they run on their own, smaller set of workers
# (WISEAPP_BATCH_SIM_WORKERS).
workers <- as.integer(Sys.getenv("WISEAPP_BATCH_WORKERS", "1"))
sim_workers <- as.integer(Sys.getenv("WISEAPP_BATCH_SIM_WORKERS", "1"))
memory_gb <- Sys.getenv("WISEAPP_BATCH_MEMORY_GB", "")

tar_option_set(
  packages = "wiseapp",
  error = "continue",
  memory = "transient",
  garbage_collection = TRUE,
  controller = wiseapp::wise_batch_controller(
    workers = workers,
    sim_workers = sim_workers,
    memory_gb = if (nzchar(memory_gb)) as.numeric(memory_gb)
  )
)

wiseapp::wise_targets("spec.yaml", out_dir = "results")
