# Check the pages of docs/ (DOC-14).
#
# Checks: front matter parses, ids are unique, `depends_on` ids exist, relative
# links and anchors resolve, no code names appear in a page body outside the
# Implementation map, every `R/` file and object named in an Implementation map
# row exists (objects are looked for in the files of their row, or anywhere in
# R/ when the row names no file), `code:` paths in the front matter exist, and
# `docs/index.yml` is current.
#
# Usage (from the repo root): Rscript dev/docs_check.R
# Exit status is 1 when any problem is printed.

docs_dir <- "docs"
files <- sort(list.files(docs_dir, pattern = "\\.md$", full.names = TRUE))
problems <- 0L
report <- function(...) {
  problems <<- problems + 1L
  cat(..., "\n")
}

`%||%` <- function(a, b) if (is.null(a)) b else a
read_page <- function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

# Front matter ----

pages <- list()
for (f in files) {
  text <- read_page(f)
  m <- regmatches(text, regexec("(?s)^---\n(.*?)\n---\n(.*)", text, perl = TRUE))[[1]]
  if (length(m) < 3L) {
    report("NO FRONT MATTER", basename(f))
    next
  }
  fm <- list()
  for (line in strsplit(m[2], "\n", fixed = TRUE)[[1]]) {
    p <- regmatches(line, regexec("^([a-z_]+):\\s*(.*?)(\\s+#.*)?$", line, perl = TRUE))[[1]]
    if (length(p) < 3L) {
      report("BAD FRONT MATTER LINE", basename(f), line)
      next
    }
    v <- p[3]
    fm[[p[2]]] <- if (startsWith(v, "[")) {
      items <- trimws(strsplit(substr(v, 2L, nchar(v) - 1L), ",", fixed = TRUE)[[1]])
      items[nzchar(items)]
    } else {
      v
    }
  }
  pages[[f]] <- list(fm = fm, body = m[3], text = text)
}

ids <- vapply(pages, function(p) p$fm$id %||% NA_character_, "")
dup <- unique(ids[duplicated(ids)])
if (length(dup)) report("DUPLICATE IDS", paste(dup, collapse = ", "))
for (f in names(pages)) {
  for (d in pages[[f]]$fm$depends_on) {
    if (!d %in% ids) report("MISSING depends_on", basename(f), d)
  }
}

# Links and anchors ----

slug <- function(h) {
  h <- tolower(trimws(h))
  h <- gsub("[^[:alnum:]_ -]", "", h)
  gsub(" ", "-", h, fixed = TRUE)
}
heading_slugs <- function(text) {
  slug(sub("^#+\\s+", "", grep("^#+\\s+", strsplit(text, "\n", fixed = TRUE)[[1]], value = TRUE)))
}
for (f in names(pages)) {
  text <- pages[[f]]$text
  links <- regmatches(text, gregexpr("\\[[^]]+\\]\\(([^)]+)\\)", text))[[1]]
  for (link in sub(".*\\]\\(([^)]+)\\)$", "\\1", links)) {
    if (startsWith(link, "http")) next
    path <- sub("#.*$", "", link)
    anchor <- if (grepl("#", link, fixed = TRUE)) sub("^[^#]*#", "", link) else ""
    target <- if (nzchar(path)) normalizePath(file.path(dirname(f), path), mustWork = FALSE) else normalizePath(f)
    if (!file.exists(target)) {
      report("DANGLING", basename(f), link)
    } else if (nzchar(anchor) && target %in% normalizePath(names(pages))) {
      src <- names(pages)[normalizePath(names(pages)) == target]
      if (!anchor %in% heading_slugs(pages[[src]]$text)) report("BAD ANCHOR", basename(f), link)
    }
  }
}

# Code names outside the Implementation map ----

code_pattern <- "(fct_|mod_|utils_|\\.wiseapp_|[a-z_]+\\(\\))"
for (f in names(pages)) {
  body <- strsplit(pages[[f]]$body, "## Implementation map", fixed = TRUE)[[1]][1]
  lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  for (n in grep(code_pattern, lines)) report("CODE NAME", basename(f), n, substr(lines[n], 1, 100))
}

# Implementation maps ----

r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
r_text <- NULL
defined_in <- function(name, paths) {
  pat <- paste0("(^|\n)\\s*", gsub(".", "\\.", name, fixed = TRUE), "\\s*(<-|=)")
  any(vapply(paths, function(p) grepl(pat, paste(readLines(p, warn = FALSE), collapse = "\n")), TRUE))
}
for (f in names(pages)) {
  parts <- strsplit(pages[[f]]$body, "## Implementation map", fixed = TRUE)[[1]]
  if (length(parts) >= 2L) {
    for (row in strsplit(parts[2], "\n", fixed = TRUE)[[1]]) {
      if (!startsWith(row, "|") || startsWith(row, "|---") || startsWith(row, "| Concept")) next
      row_files <- unique(regmatches(row, gregexpr("`R/[A-Za-z0-9_]+\\.R`", row))[[1]])
      row_files <- gsub("`", "", row_files)
      for (rf in row_files[!file.exists(row_files)]) report("NO FILE", basename(f), rf)
      ticks <- gsub("`", "", regmatches(row, gregexpr("`[^`]+`", row))[[1]])
      names_in_row <- sub("\\(\\)$", "", ticks[grepl("^[.A-Za-z_][A-Za-z0-9_.]*(\\(\\))?$", ticks)])
      names_in_row <- names_in_row[!grepl("\\.R$", names_in_row)]
      search <- if (length(row_files)) row_files[file.exists(row_files)] else r_files
      for (n in names_in_row) {
        if (!defined_in(n, search)) report("NOT FOUND", basename(f), n)
      }
    }
  }
  for (p in pages[[f]]$fm$code) {
    if (!file.exists(p)) report("FM code missing", basename(f), p)
  }
}

# Index is current ----

if (file.exists(file.path(docs_dir, "index.yml"))) {
  before <- readLines(file.path(docs_dir, "index.yml"), warn = FALSE)
  tmp <- tempfile()
  file.copy(file.path(docs_dir, "index.yml"), tmp)
  status <- system2("Rscript", "dev/docs_index.R", stdout = FALSE)
  after <- readLines(file.path(docs_dir, "index.yml"), warn = FALSE)
  file.copy(tmp, file.path(docs_dir, "index.yml"), overwrite = TRUE)
  if (status != 0L || !identical(before, after)) report("INDEX STALE: run Rscript dev/docs_index.R")
}

cat("done:", problems, "problem(s)\n")
if (problems) quit(status = 1L)
