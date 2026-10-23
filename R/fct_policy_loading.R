# Policy-arm factor loading (DOC-12) ----
#
# The policy arm is the baseline arm plus a correction (linear model: the
# fitted policy coefficients times the lever changes, and the weather-by-policy
# interactions times the row's weather). The correction is linear in the
# coefficients, so its coefficient uncertainty is a loading added to the
# baseline loading `F = X_A L_AA` (Step 2). Coefficients of the policy
# variables are not in the baseline's active block A, so the loading is
# extended in the Cholesky basis [A, P] of the block A plus the policy
# coefficients P: the leading block is the baseline's own L_AA, so the
# baseline loading is unchanged, the policy coefficients add columns, and
# their covariance with the active block is kept.

# Coefficient terms the policy correction depends on: the main term of each
# moved lever and its interactions with the run's weather variables. Names are
# resolved as `.decompose_ols()` resolves them. Each term is a list of its
# coefficient `name`, its `kind` ("main", "cont" or "bin"), the `lever`
# variable, the `weather` variable and, for a bin, the `level`.
.policy_loading_terms <- function(context) {
  coef_names <- context$coef_names
  svy <- context$svy_baseline
  terms <- list()
  add <- function(name, kind, lever, weather = NULL, level = NULL) {
    if (!is.null(name) && name %in% coef_names) {
      terms[[length(terms) + 1L]] <<- list(
        name = name, kind = kind, lever = lever, weather = weather, level = level
      )
    }
  }
  for (v in names(context$deltas)) {
    main <- context$ols_term_map[[v]] %||% v
    if (!main %in% coef_names) {
      hit <- .policy_lever_terms(v, coef_names, svy[[v]])
      main <- if (length(hit)) hit[[1L]] else NULL
    }
    add(main, "main", v)
    for (wv in context$weather_vars) {
      candidates <- context$ols_interaction_map[[wv]][[v]] %||% character(0)
      if (is.factor(svy[[wv]])) {
        for (lv in levels(svy[[wv]])) {
          pair <- c(paste0(wv, lv, ":", v), paste0(v, ":", wv, lv))
          matched <- pair[pair %in% candidates]
          name <- if (length(matched)) matched[[1L]] else pair[pair %in% coef_names][1L]
          add(if (is.na(name)) NULL else name, "bin", v, wv, lv)
        }
      } else {
        name <- if (length(candidates)) candidates[[1L]] else NULL
        if (is.null(name)) {
          exact <- c(paste0(wv, ":", v), paste0(v, ":", wv))
          exact <- exact[exact %in% coef_names]
          name <- if (length(exact)) exact[[1L]] else {
            hit <- .policy_lever_terms(v, coef_names, svy[[v]], partner = wv)
            if (length(hit)) hit[[1L]] else NULL
          }
        }
        add(name, "cont", v, wv)
      }
    }
  }
  terms
}

# Row weights of those terms: the derivative of the correction with respect to
# each coefficient, per prediction row (`ids` index the survey, `idx` the
# exposure table).
.policy_loading_weights <- function(terms, context, exposure, ids, idx) {
  out <- matrix(0, length(ids), length(terms))
  for (j in seq_along(terms)) {
    t <- terms[[j]]
    d <- as.numeric(context$deltas[[t$lever]])[ids]
    d[!is.finite(d)] <- 0
    out[, j] <- switch(t$kind,
      main = d,
      cont = d * as.numeric(exposure$table[[t$weather]][idx]),
      bin = d * (as.character(exposure$table[[t$weather]][idx]) == t$level)
    )
  }
  out[!is.finite(out)] <- 0
  out
}

# Rows of the loading basis for coefficient names `names`: row j holds the
# coefficient's loading on the `k_base` baseline columns followed by one column
# per policy coefficient outside the active block. NULL when the baseline
# basis cannot be rebuilt (the width of the baseline loading is neither the
# full set nor the active block).
.policy_loading_rows <- function(context, k_base, names) {
  L <- context$coef_L
  coef_names <- context$coef_names
  if (is.null(L) || nrow(L) != length(coef_names)) return(NULL)
  rownames(L) <- coef_names
  if (k_base == length(coef_names)) {
    return(L[names, , drop = FALSE])
  }
  mask <- build_active_coef_mask(coef_names, context$weather_vars)
  if (is.null(mask) || sum(mask) != k_base) return(NULL)
  active <- coef_names[mask]
  extra <- setdiff(names, active)
  L_aa <- t(chol(tcrossprod(L[active, , drop = FALSE])))
  rows <- matrix(0, length(names), k_base + length(extra),
    dimnames = list(names, NULL))
  in_a <- names %in% active
  # Active coefficients: their row of L_aa (the baseline's own factor)
  pos <- match(names[in_a], active)
  rows[in_a, seq_len(k_base)] <- L_aa[pos, , drop = FALSE]
  if (length(extra)) {
    # Policy coefficients: [Sigma_pa L_aa^-T, chol(Sigma_pp - L_pa L_pa')]
    sigma_pa <- L[extra, , drop = FALSE] %*% t(L[active, , drop = FALSE])
    l_pa <- t(forwardsolve(L_aa, t(sigma_pa)))
    sigma_pp <- tcrossprod(L[extra, , drop = FALSE])
    rest <- sigma_pp - tcrossprod(l_pa)
    rest <- (rest + t(rest)) / 2
    l_pp <- tryCatch(t(chol(rest)), error = function(err) {
      # Collinear coefficients: use the positive part
      eig <- eigen(rest, symmetric = TRUE)
      keep <- eig$values > sqrt(.Machine$double.eps) * max(eig$values, 1)
      m <- eig$vectors[, keep, drop = FALSE] %*% diag(sqrt(eig$values[keep]), sum(keep))
      cbind(m, matrix(0, nrow(m), nrow(m) - sum(keep)))
    })
    where <- match(names[!in_a], extra)
    rows[!in_a, seq_len(k_base)] <- l_pa[where, , drop = FALSE]
    rows[!in_a, k_base + seq_along(extra)] <- l_pp[where, , drop = FALSE]
  }
  rows
}

# The policy arm's loading for a block of prediction rows: the baseline
# loading plus the correction's loading. Returns the baseline block when no
# term moves in the block (a run without a covariate lever).
.policy_loading_block <- function(F_base, weights, rows_t) {
  extra <- ncol(rows_t) - ncol(F_base)
  delta <- weights %*% rows_t
  if (extra == 0L) return(F_base + delta)
  cbind(F_base + delta[, seq_len(ncol(F_base)), drop = FALSE],
    delta[, ncol(F_base) + seq_len(extra), drop = FALSE])
}

# The policy arm's full loading for a pipeline, chunked by `chunk_size`, or
# NULL when the arm keeps the baseline loading: no loading, not the linear
# model, no coefficient the correction depends on, or no row moves.
.policy_arm_loading <- function(pipeline, prepared, exposure, chunk_size) {
  context <- prepared$context
  F_base <- pipeline$F_loading
  if (is.null(F_base) || !identical(context$engine, "fixest") ||
    is.null(context$coef_L) || is.null(dim(F_base))) {
    return(NULL)
  }
  terms <- prepared$loading_terms
  if (!length(terms)) return(NULL)
  rows_t <- .policy_loading_rows(context, ncol(F_base), vapply(terms, `[[`, "", "name"))
  if (is.null(rows_t)) return(NULL)
  n <- nrow(F_base)
  ids <- pipeline$svy_row_id
  idx <- exposure$row_index
  extra <- ncol(rows_t) - ncol(F_base)
  out <- matrix(0, n, ncol(F_base) + extra)
  moved <- FALSE
  for (start in seq.int(1L, n, by = chunk_size)) {
    r <- seq.int(start, min(n, start + chunk_size - 1L))
    w <- .policy_loading_weights(terms, context, exposure, ids[r], idx[r])
    if (any(w != 0)) moved <- TRUE
    out[r, ] <- .policy_loading_block(F_base[r, , drop = FALSE], w, rows_t)
  }
  if (!moved) return(NULL)
  rownames(out) <- rownames(F_base)
  out
}
