# Rebuild docs/index.yml from the pages of docs/ (DOC-14).
#
# The index is built from the front matter, the numbered Method subsections,
# the equation tags and the "In the app" bullets of each page. Run it after a
# page changes; `dev/docs_check.R` validates the pages themselves.
#
# Usage (from the repo root): Rscript dev/docs_index.R

docs_dir <- "docs"

# Front matter ----

# Parse the "key: value" lines between the leading --- fences. A value in
# square brackets becomes a character vector.
.docs_front_matter <- function(text) {
  m <- regmatches(text, regexec("(?s)^---\n(.*?)\n---\n", text, perl = TRUE))[[1]]
  if (length(m) < 2L) stop("page has no front matter", call. = FALSE)
  fm <- list()
  for (line in strsplit(m[2], "\n", fixed = TRUE)[[1]]) {
    parts <- regmatches(line, regexec("^([a-z_]+):\\s*(.*?)(\\s+#.*)?$", line, perl = TRUE))[[1]]
    if (length(parts) < 3L) stop("bad front matter line: ", line, call. = FALSE)
    v <- parts[3]
    fm[[parts[2]]] <- if (startsWith(v, "[")) {
      items <- trimws(strsplit(substr(v, 2L, nchar(v) - 1L), ",", fixed = TRUE)[[1]])
      items[nzchar(items)]
    } else {
      v
    }
  }
  list(fm = fm, body = substring(text, nchar(m[1]) + 1L))
}

# Writers ----

.q <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
.arr <- function(x) paste0("[", paste(vapply(x, .q, ""), collapse = ", "), "]")

# Strip markdown links, bold, code ticks and inline math from a heading.
.plain <- function(s) {
  s <- gsub("\\[([^]]+)\\]\\([^)]+\\)", "\\1", s)
  s <- gsub("**", "", s, fixed = TRUE)
  s <- gsub("`", "", s, fixed = TRUE)
  s <- gsub("\\$([^$]+)\\$", "\\1", s)
  trimws(s)
}

.page_entry <- function(name) {
  page <- .docs_front_matter(paste(readLines(file.path(docs_dir, name), warn = FALSE,
    encoding = "UTF-8"), collapse = "\n"))
  fm <- page$fm
  lines <- strsplit(page$body, "\n", fixed = TRUE)[[1]]
  methods <- sub("^### ", "", grep("^### [0-9]+\\. .+$", lines, value = TRUE))
  eq_tags <- character(0)
  eq_sections <- character(0)
  heading <- ""
  for (line in lines) {
    h <- regmatches(line, regexec("^#{2,3} (.+)$", line))[[1]]
    if (length(h)) heading <- trimws(h[2])
    tags <- regmatches(line, gregexpr("qquad \\\\text\\{\\(([0-9]+\\.[0-9]+)\\)\\}", line))[[1]]
    for (t in tags) {
      eq_tags <- c(eq_tags, sub(".*\\(([0-9]+\\.[0-9]+)\\).*", "\\1", t))
      eq_sections <- c(eq_sections, heading)
    }
  }
  ui <- character(0)
  start <- grep("^## In the app$", lines)
  if (length(start)) {
    stop_at <- grep("^## ", lines)
    stop_at <- stop_at[stop_at > start[1]]
    end <- if (length(stop_at)) stop_at[1] - 1L else length(lines)
    sec <- lines[(start[1] + 1L):end]
    ui <- .plain(sub("^- ", "", sec[startsWith(sec, "- ")]))
  }
  get <- function(k, default = "") fm[[k]] %||% default
  c(
    paste0("  - id: ", .q(get("id"))),
    paste0("    file: ", .q(name)),
    paste0("    title: ", .q(get("title"))),
    paste0("    app_step: ", .q(get("app_step"))),
    paste0("    depends_on: ", .arr(get("depends_on", character(0)))),
    paste0("    methods:", if (length(methods)) "" else " []"),
    if (length(methods)) paste0("      - ", vapply(.plain(methods), .q, "")),
    paste0("    equations:", if (length(eq_tags)) "" else " []"),
    if (length(eq_tags)) {
      paste0("      - {tag: ", vapply(paste0("(", eq_tags, ")"), .q, ""),
        ", section: ", vapply(.plain(eq_sections), .q, ""), "}")
    },
    paste0("    symbols: ", .arr(get("symbols", character(0)))),
    paste0("    ui:", if (length(ui)) "" else " []"),
    if (length(ui)) paste0("      - ", vapply(ui, .q, "")),
    paste0("    guide: ", .q(get("guide"))),
    paste0("    code: ", .arr(get("code", character(0)))),
    paste0("    verified_against: ", .q(get("verified_against")))
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

files <- sort(list.files(docs_dir, pattern = "\\.md$"))
files <- c("README.md", setdiff(files, "README.md"))
out <- c(
  "# Machine-readable index of the pages of docs/.",
  "# Built from the front matter, the numbered Method subsections, the equation",
  "# tags and the 'In the app' bullets of each page. Rebuild it when a page changes.",
  "pages:",
  unlist(lapply(files, .page_entry))
)
writeLines(out, file.path(docs_dir, "index.yml"), useBytes = TRUE)
cat("pages", length(files), "\n")
