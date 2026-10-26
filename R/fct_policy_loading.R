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
  if (is.null(F_base) || is.null(dim(F_base))) return(NULL)
  if (identical(context$engine, "rif")) {
    return(.policy_arm_loading_rif(pipeline, prepared, exposure, chunk_size))
  }
  if (!identical(context$engine, "fixest") || is.null(context$coef_L)) {
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


# Quantile model ----
#
# The correction is linear in the coefficient curves given the household's
# positions before and after the main effect (the position moves with the
# outcome, not with the coefficients, so it is held fixed as in the channel
# standard deviations). At the weather x of a row, a household with positions
# tau_pre and tau_post has
#   correction = sum_lever d_lever b_lever(tau_pre)
#              + sum_weather x (b_w(tau_post) - b_w(tau_pre))
#              + sum_weather,lever x d_lever b_wl(tau_post)
# (for a binned weather variable x is the indicator of the row's bin). Each
# curve b(tau) is the linear interpolation of the grid coefficients, so the
# loading is the same interpolation of the rows of the per-quantile Cholesky
# basis of the joint covariance of the quantile equations.

# The curves the correction uses: lever main terms, weather terms and their
# interactions with the levers, resolved as `.compute_rif_channels()` does.
.policy_loading_terms_rif <- function(context) {
  all_terms <- context$all_terms
  svy <- context$svy_baseline
  main <- list()
  for (v in names(context$deltas)) {
    term <- context$rif_term_map[[v]]
    if (!is.null(term)) main[[length(main) + 1L]] <- list(term = term, lever = v)
  }
  weather <- inter <- list()
  for (wv in context$weather_vars) {
    binned <- is.factor(svy[[wv]])
    levels_wv <- if (binned) levels(svy[[wv]]) else NA_character_
    for (lv in levels_wv) {
      term <- if (binned) paste0(wv, lv) else wv
      if (term %in% all_terms) {
        weather[[length(weather) + 1L]] <- list(var = wv, level = lv, term = term)
      }
      for (u in names(context$deltas)) {
        candidates <- context$rif_interaction_map[[wv]][[u]] %||% character(0)
        it <- if (binned) {
          pair <- c(paste0(wv, lv, ":", u), paste0(u, ":", wv, lv))
          hit <- pair[pair %in% candidates]
          if (length(hit)) hit[[1L]] else NULL
        } else if (length(candidates)) {
          candidates[[1L]]
        }
        if (!is.null(it)) {
          inter[[length(inter) + 1L]] <- list(var = wv, level = lv, term = it, lever = u)
        }
      }
    }
  }
  terms <- c(main, weather, inter)
  if (!length(terms)) return(NULL)
  list(main = main, weather = weather, inter = inter,
    names = unique(vapply(terms, `[[`, "", "term")))
}

# Interpolation weights of the grid points of a curve at positions `tau`
# (n x length(curve_tau)); positions outside the curve take its end points.
.policy_curve_weights <- function(curve_tau, tau) {
  m <- length(curve_tau)
  out <- matrix(0, length(tau), m)
  if (m == 1L) {
    out[, 1L] <- 1
    return(out)
  }
  ord <- order(curve_tau)
  ct <- curve_tau[ord]
  tau <- pmin(pmax(tau, ct[1L]), ct[m])
  lo <- findInterval(tau, ct, all.inside = TRUE)
  w <- (tau - ct[lo]) / (ct[lo + 1L] - ct[lo])
  rows <- seq_along(tau)
  out[cbind(rows, ord[lo])] <- 1 - w
  out[cbind(rows, ord[lo + 1L])] <- w
  out
}

# Rows of the basis [A, P] for `names` in every quantile equation, from the
# joint covariance of the equations (the same one the baseline loading uses:
# `rif_joint_factor()`). The leading block A is the baseline's own factor of the
# active block, the policy coefficients P outside it add columns, and their
# covariance with A, within and across equations, is kept. NULL when a term is
# missing from an equation or the baseline basis cannot be rebuilt.
.policy_loading_rows_rif <- function(context, k_base, names) {
  chol_obj <- context$coef_chol_list
  K <- length(chol_obj)
  coef_names <- names(chol_obj[[1L]]$beta)
  if (!all(names %in% coef_names)) return(NULL)
  mask <- build_active_coef_mask(coef_names, context$weather_vars)
  if (is.null(mask)) return(NULL)
  if (k_base != K * sum(mask)) mask <- NULL
  fac <- tryCatch(rif_joint_factor(chol_obj, mask), error = function(e) NULL)
  if (is.null(fac)) return(NULL)
  jn <- paste0(rep(seq_len(K), each = length(coef_names)), "|", rep(coef_names, K))
  V <- fac$V_full
  dimnames(V) <- list(jn, jn)
  if (is.null(mask)) {
    # Full propagation: every coefficient is in the baseline basis
    L <- tryCatch(t(chol(V)), error = function(e) NULL)
    if (is.null(L)) return(NULL)
    rownames(L) <- jn
    rows_all <- L
  } else {
    active <- jn[rep(mask, K)]
    want <- paste0(rep(seq_len(K), each = length(names)), "|", rep(names, K))
    rows_all <- .policy_loading_rows_cov(V, active, want, k_base, fac$L)
  }
  lapply(seq_len(K), function(k) {
    r <- rows_all[paste0(k, "|", names), , drop = FALSE]
    rownames(r) <- names
    r
  })
}

# Rows of the basis [A, P] for coefficients `want` of a joint covariance `V`
# (dimnames = coefficient labels), `active` the labels in the baseline's block
# and `L_aa` the lower factor of that block, as in `.policy_loading_rows()`.
.policy_loading_rows_cov <- function(V, active, want, k_base, L_aa) {
  extra <- setdiff(want, active)
  rows <- matrix(0, length(want), k_base + length(extra), dimnames = list(want, NULL))
  in_a <- want %in% active
  rows[in_a, seq_len(k_base)] <- L_aa[match(want[in_a], active), , drop = FALSE]
  if (length(extra)) {
    sigma_pa <- V[extra, active, drop = FALSE]
    l_pa <- t(forwardsolve(L_aa, t(sigma_pa)))
    rest <- V[extra, extra, drop = FALSE] - tcrossprod(l_pa)
    rest <- (rest + t(rest)) / 2
    l_pp <- tryCatch(t(chol(rest)), error = function(err) {
      # Collinear coefficients: use the positive part
      eig <- eigen(rest, symmetric = TRUE)
      keep <- eig$values > sqrt(.Machine$double.eps) * max(eig$values, 1)
      m <- eig$vectors[, keep, drop = FALSE] %*% diag(sqrt(eig$values[keep]), sum(keep))
      cbind(m, matrix(0, nrow(m), nrow(m) - sum(keep)))
    })
    where <- match(want[!in_a], extra)
    rows[!in_a, seq_len(k_base)] <- l_pa[where, , drop = FALSE]
    rows[!in_a, k_base + seq_along(extra)] <- l_pp[where, , drop = FALSE]
  }
  rows
}

# Interpolated loading rows of curve `term` at positions `tau`.
.policy_curve_rows <- function(term, tau, context, rows_by_k) {
  curve <- context$rif_curve_index[[term]]
  if (is.null(curve)) return(0)
  grid_k <- match(round(curve$tau, 8), round(context$taus, 8))
  if (anyNA(grid_k)) return(NULL)
  rmat <- do.call(rbind, lapply(grid_k, function(k) rows_by_k[[k]][term, ]))
  .policy_curve_weights(curve$tau, tau) %*% rmat
}

.policy_arm_loading_rif <- function(pipeline, prepared, exposure, chunk_size) {
  context <- prepared$context
  F_base <- pipeline$F_loading
  recipe <- prepared$loading_terms
  if (is.null(recipe) || !length(context$coef_chol_list) ||
    length(context$coef_chol_list) != length(context$taus)) {
    return(NULL)
  }
  rows_by_k <- .policy_loading_rows_rif(context, ncol(F_base), recipe$names)
  if (anyNA(vapply(rows_by_k, is.null, NA)) || any(vapply(rows_by_k, is.null, NA))) {
    return(NULL)
  }
  extra <- ncol(rows_by_k[[1L]]) - ncol(F_base)
  if (extra < 0L) return(NULL)
  n <- nrow(F_base)
  ids <- pipeline$svy_row_id
  idx <- exposure$row_index
  out <- matrix(0, n, ncol(F_base) + extra)
  moved <- FALSE
  pre <- context$tau_i_pre
  post <- context$tau_i_post
  for (start in seq.int(1L, n, by = chunk_size)) {
    r <- seq.int(start, min(n, start + chunk_size - 1L))
    h <- ids[r]
    d <- matrix(0, length(r), ncol(out))
    for (t in recipe$main) {
      dl <- as.numeric(context$deltas[[t$lever]])[h]
      dl[!is.finite(dl)] <- 0
      if (!any(dl != 0)) next
      d <- d + dl * .policy_curve_rows(t$term, pre[h], context, rows_by_k)
    }
    x_of <- function(var) exposure$table[[var]][idx[r]]
    for (t in recipe$weather) {
      x <- x_of(t$var)
      w <- if (is.na(t$level)) as.numeric(x) else as.numeric(as.character(x) == t$level)
      sel <- which(w != 0)
      if (!length(sel)) next
      diff_rows <- .policy_curve_rows(t$term, post[h[sel]], context, rows_by_k) -
        .policy_curve_rows(t$term, pre[h[sel]], context, rows_by_k)
      d[sel, ] <- d[sel, , drop = FALSE] + w[sel] * diff_rows
    }
    for (t in recipe$inter) {
      x <- x_of(t$var)
      w <- if (is.na(t$level)) as.numeric(x) else as.numeric(as.character(x) == t$level)
      dl <- as.numeric(context$deltas[[t$lever]])[h]
      dl[!is.finite(dl)] <- 0
      w <- w * dl
      sel <- which(w != 0)
      if (!length(sel)) next
      d[sel, ] <- d[sel, , drop = FALSE] +
        w[sel] * .policy_curve_rows(t$term, post[h[sel]], context, rows_by_k)
    }
    d[!is.finite(d)] <- 0
    if (any(d != 0)) moved <- TRUE
    out[r, seq_len(ncol(F_base))] <- F_base[r, , drop = FALSE] +
      d[, seq_len(ncol(F_base)), drop = FALSE]
    if (extra > 0L) out[r, ncol(F_base) + seq_len(extra)] <- d[, ncol(F_base) + seq_len(extra), drop = FALSE]
  }
  if (!moved) return(NULL)
  rownames(out) <- rownames(F_base)
  out
}
