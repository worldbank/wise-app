test_that("agent checks reject missing inputs and inconsistent skill listings", {
  root <- tempfile("agents-check-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  script <- normalizePath(testthat::test_path("..", "..", "dev", "agents_check.R"), mustWork = TRUE)
  required <- c(
    "AGENTS.md", "ARCHITECTURE.md", "DEPLOYMENT.md", "review/README.md",
    "review/code_hygiene.md", "review/optimization_guidelines.md", "DESCRIPTION", "inst/golem-config.yml"
  )
  for (f in required) {
    dir.create(dirname(file.path(root, f)), recursive = TRUE, showWarnings = FALSE)
    writeLines(character(), file.path(root, f))
  }
  writeLines("Version: 1.0.0", file.path(root, "DESCRIPTION"))
  writeLines("golem_version: 1.0.0", file.path(root, "inst/golem-config.yml"))
  agents <- c("## Skills", "| Skill | Use when |", "|---|---|", "| `example` | Testing |")
  writeLines(agents, file.path(root, "AGENTS.md"))
  skill_dir <- file.path(root, ".agents/skills/example")
  dir.create(skill_dir, recursive = TRUE)
  skill <- c("---", "name: example", "description: Test fixture", "---")
  writeLines(skill, file.path(skill_dir, "SKILL.md"))
  run_check <- function() {
    processx::run(file.path(R.home("bin"), "Rscript"), c("--vanilla", script), wd = root, error_on_status = FALSE)
  }

  expect_equal(run_check()$status, 0L)
  for (f in required) {
    path <- file.path(root, f)
    original <- readLines(path)
    unlink(path)
    result <- run_check()
    expect_equal(result$status, 1L, info = f)
    expect_match(result$stdout, paste("MISSING REQUIRED FILE", f), fixed = TRUE)
    writeLines(original, path)
  }
  unlink(file.path(root, ".agents/skills"), recursive = TRUE)
  result <- run_check()
  expect_equal(result$status, 1L)
  expect_match(result$stdout, "MISSING SKILLS DIRECTORY", fixed = TRUE)
  dir.create(file.path(root, ".agents/skills"))
  result <- run_check()
  expect_equal(result$status, 1L)
  expect_match(result$stdout, "NO SKILLS", fixed = TRUE)
  dir.create(skill_dir)
  writeLines(skill, file.path(skill_dir, "SKILL.md"))
  writeLines(c(agents, "| `missing` | Testing |"), file.path(root, "AGENTS.md"))
  result <- run_check()
  expect_equal(result$status, 1L)
  expect_match(result$stdout, "LISTED SKILL MISSING missing", fixed = TRUE)
  writeLines(agents[1:3], file.path(root, "AGENTS.md"))
  result <- run_check()
  expect_equal(result$status, 1L)
  expect_match(result$stdout, "SKILL NOT IN AGENTS.md example", fixed = TRUE)
  writeLines(agents, file.path(root, "AGENTS.md"))
  expect_equal(run_check()$status, 0L)
})
