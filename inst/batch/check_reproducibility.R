# Check that this machine matches the run recorded in results/manifest.json:
# Rscript check_reproducibility.R
#
# Compares the wiseapp version and commit, the R and duckdb versions, renv.lock
# and the survey files in WISEAPP_DATA_PATH with the values the run recorded.

`%||%` <- function(a, b) if (is.null(a)) b else a

m <- jsonlite::read_json("results/manifest.json", simplifyVector = TRUE)
data_path <- Sys.getenv("WISEAPP_DATA_PATH")

now_sha <- function(f) if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA_character_
# The same lookup the run used for the manifest.
now_git <- tryCatch(wiseapp:::.git_sha(), error = function(e) NA_character_)

# A value the run could not record is null in the manifest and absent here.
rec <- function(x) as.character(x %||% NA_character_)

checks <- data.frame(
  item = c("wiseapp version", "wiseapp commit", "R version", "duckdb version", "renv.lock"),
  recorded = c(
    rec(m$wiseapp_version), rec(m$wiseapp_git_sha), rec(m$r_version), rec(m$duckdb_version),
    rec(m$renv_lock_sha256)
  ),
  current = c(
    as.character(utils::packageVersion("wiseapp")), now_git,
    paste0(R.version$major, ".", R.version$minor),
    as.character(utils::packageVersion("duckdb")), now_sha("renv.lock")
  ),
  stringsAsFactors = FALSE
)

if (is.data.frame(m$data_files) && nzchar(data_path)) {
  cur <- vapply(m$data_files$file, function(f) now_sha(file.path(data_path, "microdata", f)), "")
  checks <- rbind(checks, data.frame(
    item = paste("data:", m$data_files$file), recorded = m$data_files$sha256,
    current = unname(cur), stringsAsFactors = FALSE
  ))
}

checks$match <- !is.na(checks$recorded) & !is.na(checks$current) & checks$recorded == checks$current
print(checks[, c("item", "match")], row.names = FALSE)
if (!all(checks$match)) {
  message("Differences found: results may not reproduce exactly. See the table above.")
  quit(status = 1)
}
message("All recorded items match.")
