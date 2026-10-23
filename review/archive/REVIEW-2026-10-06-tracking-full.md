

### DOC-12 closed (2026-10-23)

| DOC-12 | M | M | ◐ | Linear model done 2026-10-23 (`R/fct_policy_loading.R`; user chose the appended policy block): the policy arm's loading is the baseline loading plus the gradient of the correction, with the policy coefficients as extra columns in the Cholesky basis of the active block plus the policy terms (cross-covariances kept; the baseline arm is untouched); `paired_model_year_effects()` pads the baseline gradient. Still open: the quantile model keeps the baseline loading (its loading is interpolated over quantiles); the policy arm's `F_loading` is no longer linked to the baseline's in the retained artifact when a covariate lever is on (size not measured). `docs/40_policy_framework.md` section 5 updated. |

Decision log, DOC-12 quantile (2026-10-23): gradient with positions fixed, shared-z interpolation as the baseline loading. BFA numbers: see the Log entry of that date.
