# Pre-render every LaTeX string used by wise_math() into inst/math_cache.json,
# so the deployed app does not need {katex} (and V8). Needs {katex}.
# Re-run after adding or editing a wise_math() call. Run from the repo root.

devtools::load_all(quiet = TRUE)

literals <- unlist(lapply(list.files("R", "\\.R$", full.names = TRUE), function(f) {
  pd <- utils::getParseData(parse(f, keep.source = TRUE))
  calls <- pd$parent[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "wise_math"]
  vapply(calls, function(id) {
    # the call expr is the parent of the function-name expr; its first arg follows "("
    expr <- pd$parent[pd$id == id]
    kids <- pd[pd$parent == expr, ]
    kids <- kids[order(kids$line1, kids$col1), ]
    arg <- kids$id[which(kids$token == "'('") + 1L]
    str <- pd[pd$parent == arg & pd$token == "STR_CONST", "text"]
    if (length(str)) eval(parse(text = str)) else NA_character_
  }, character(1))
}))
literals <- unique(literals[!is.na(literals)])

# Fresh cache, filled by rendering with {katex}
rm(list = ls(.katex_cache, all.names = TRUE), envir = .katex_cache)
assign(".loaded", TRUE, envir = .katex_cache)
for (tex in literals) wise_math(tex)
# Dynamic strings
invisible(welfare_equation_ui(FALSE))
invisible(welfare_equation_ui(TRUE))

keys <- setdiff(ls(.katex_cache, all.names = TRUE), ".loaded")
out <- mget(sort(keys), envir = .katex_cache)
jsonlite::write_json(out, "inst/math_cache.json", auto_unbox = TRUE, pretty = TRUE)
cat(length(out), "math strings written to inst/math_cache.json\n")
