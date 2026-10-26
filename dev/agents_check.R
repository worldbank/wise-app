# Check the instructions that coding agents read (R5 of review/agent_setup_review.md).
#
# Checks: paths and R functions named in backticks in AGENTS.md, ARCHITECTURE.md,
# the skills and the two review standards exist; every skill has a name that
# matches its folder and a description, and is listed in AGENTS.md; size budgets
# keep AGENTS.md short; DESCRIPTION and inst/golem-config.yml carry one version.
#
# Usage (from the repo root): Rscript dev/agents_check.R
# Exit status is 1 when any problem is printed.

problems <- 0L
report <- function(...) {
  problems <<- problems + 1L
  cat(..., "\n")
}

read_lines <- function(f) readLines(f, warn = FALSE, encoding = "UTF-8")

# Files read by agents ----

# The shared folder; .claude/skills is only a local link to it.
skill_dirs <- ".agents/skills"
skill_files <- unlist(lapply(skill_dirs, list.files, pattern = "\\.md$", recursive = TRUE, full.names = TRUE))
doc_files <- Filter(
  file.exists,
  c("AGENTS.md", "ARCHITECTURE.md", "DEPLOYMENT.md", "review/code_hygiene.md", "review/optimization_guidelines.md", skill_files)
)

# Size budgets ----

# Limits sit just above today's size, so the files cannot grow unnoticed. Detail
# belongs in docs/, an R file header or a skill.
budgets <- list(
  "AGENTS.md" = c(lines = 120L, width = 800L),
  "ARCHITECTURE.md" = c(lines = 60L, width = 1300L),
  "DEPLOYMENT.md" = c(lines = 50L, width = 1000L)
)
for (f in names(budgets)) {
  x <- read_lines(f)
  if (length(x) > budgets[[f]][["lines"]]) {
    report("TOO LONG", f, length(x), "lines, budget", budgets[[f]][["lines"]])
  }
  if (max(nchar(x)) > budgets[[f]][["width"]]) {
    report("LINE TOO WIDE", f, max(nchar(x)), "characters, budget", budgets[[f]][["width"]])
  }
}

# Paths and functions named in backticks ----

r_src <- unlist(lapply(
  c(list.files("R", pattern = "\\.R$", full.names = TRUE),
    list.files("dev", pattern = "\\.R$", full.names = TRUE, recursive = TRUE),
    list.files("tests/testthat", pattern = "\\.R$", full.names = TRUE)),
  read_lines
))
defined <- unique(unlist(regmatches(
  r_src,
  gregexpr("^\\s*[`\"]?[A-Za-z.][A-Za-z0-9_.]*[`\"]?\\s*(<-|=)\\s*function", r_src)
)))
defined <- unique(sub("^\\s*[`\"]?([A-Za-z.][A-Za-z0-9_.]*).*$", "\\1", defined))
# Assigned reactives and helpers inside modules are not `function` literals.
assigned <- unique(sub(
  "^\\s*[`\"]?([A-Za-z.][A-Za-z0-9_.]*)[`\"]?\\s*(<-|=)\\s*(reactive|reactiveVal|eventReactive).*$", "\\1",
  grep("(<-|=)\\s*(reactive|reactiveVal|eventReactive)\\b", r_src, value = TRUE)
))
known <- c(
  "bundle_resources" # golem
)
is_known_fn <- function(n) {
  n %in% c(defined, assigned, known) ||
    exists(n, envir = baseenv()) ||
    exists(n, envir = asNamespace("stats")) ||
    exists(n, envir = asNamespace("utils"))
}

skip_path <- paste(
  c(
    "^worldbank/", # GitHub repos
    "^retained/", # runtime directory
    "^dev/outputs", # git-ignored output
    "^tests/e2e/out", # git-ignored output
    "^\\.Renviron$",
    "^SKILL\\.md$", # generic name of a skill file
    "^global\\.R$", # named only to say the app has none
    "^inst/duckdb_extensions/" # binaries are bundled at release
  ),
  collapse = "|"
)
roots <- c("", "R", "tests/testthat", "dev", "dev/bench", "inst/app", "inst/app/vendor", "inst/batch", "review", "review/archive", "docs")
path_exists <- function(p, doc) {
  p <- sub("/$", "", p)
  dirs <- c(roots, dirname(doc))
  any(file.exists(ifelse(dirs == "", p, file.path(dirs, p))))
}

for (f in doc_files) {
  x <- read_lines(f)
  # Fenced code blocks hold example commands, not references.
  fenced <- cumsum(grepl("^```", x)) %% 2L == 1L | grepl("^```", x)
  tokens <- unique(gsub("`", "", unlist(regmatches(x[!fenced], gregexpr("`[^`]+`", x[!fenced])))))
  tokens <- tokens[!grepl("[ *<>${}|~=,]|://|\\.\\.\\.|::", tokens)]
  paths <- tokens[grepl("/|\\.(R|md|yml|yaml|cpp|js|sh|json)$", tokens) & !grepl(skip_path, tokens)]
  paths <- paths[!grepl("^[A-Za-z]+/[A-Za-z]+$", paths) | grepl("\\.", paths)]
  for (p in paths) {
    if (!path_exists(p, f)) report("MISSING PATH", f, p)
  }
  fns <- sub("\\(\\)$", "", tokens[grepl("^\\.?[A-Za-z][A-Za-z0-9_.]*\\(\\)$", tokens)])
  fns <- fns[!grepl("[A-Z]", fns)] # placeholders such as mod_NAME_ui
  # Skills and standards also name functions of other packages and of JavaScript.
  if (!f %in% c("AGENTS.md", "ARCHITECTURE.md", "DEPLOYMENT.md")) fns <- character()
  for (n in fns) {
    if (!is_known_fn(n)) report("UNKNOWN FUNCTION", f, paste0(n, "()"))
  }
}

# Skills ----

agents_md <- paste(read_lines("AGENTS.md"), collapse = "\n")
skill_md <- unlist(lapply(skill_dirs, list.files, pattern = "^SKILL\\.md$", recursive = TRUE, full.names = TRUE))
for (f in skill_md) {
  x <- read_lines(f)
  fm_end <- which(x == "---")[2]
  if (!identical(x[1], "---") || is.na(fm_end)) {
    report("NO FRONT MATTER", f)
    next
  }
  fm <- x[2:(fm_end - 1L)]
  name <- sub("^name:\\s*", "", grep("^name:", fm, value = TRUE))
  folder <- basename(dirname(f))
  if (length(name) != 1L || !identical(trimws(name), folder)) {
    report("SKILL NAME != FOLDER", f, if (length(name)) name else "(none)")
  }
  if (!any(grepl("^description:", fm))) report("NO DESCRIPTION", f)
  if (!grepl(paste0("`", folder, "`"), agents_md, fixed = TRUE)) {
    report("SKILL NOT IN AGENTS.md", folder)
  }
  if (length(x) > 300L) report("SKILL TOO LONG", f, length(x), "lines, budget 300")
}

# Version ----

desc_version <- unname(read.dcf("DESCRIPTION", fields = "Version")[1, 1])
cfg <- read_lines("inst/golem-config.yml")
cfg_version <- sub("^\\s*golem_version:\\s*", "", grep("^\\s*golem_version:", cfg, value = TRUE)[1])
if (!identical(desc_version, trimws(cfg_version))) {
  report("VERSION MISMATCH", "DESCRIPTION", desc_version, "inst/golem-config.yml", cfg_version)
}

if (problems > 0L) {
  cat(problems, "problem(s)\n")
  quit(status = 1L)
}
cat("agents_check: ok\n")
