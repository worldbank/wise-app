# roadmap/

Working plans for features in flight. They are state and decisions, not guidance: read one only when you work on that feature.

| Kind of work | Where |
|---|---|
| Feature requests and backlog | GitHub issues on `worldbank/wise-app` |
| State, decisions and remaining work of a feature being built | `roadmap/<feature>.md`, with a status line and the branch at the top |
| Maintenance findings | `review/TRACKING.md` |
| Method and equations | `docs/` |

When a feature merges, cut its file down to a pointer to the `docs/` method page or delete it; the full text stays in git.

Current files:

- `enso.md`: ENSO labels (method `docs/35_enso.md`). Branch `seasonal-forecast`.
- `seasonal_forecast.md`: seasonal forecast scenario (method `docs/34_seasonal_forecast.md`). Branch `seasonal-forecast`. Covers issue #83.

Proposals for open issues (no branch yet; each file lists its issues):

- `survey_stats.md`: #78, #76. Survey and outcome statistics in Step 1.
- `model_specification.md`: #62, #48, #55, #54, #57. Interactions, lags, displaced weather, crop season.
- `estimation.md`: #47, #45. Tree engines and survey-design variance.
- `uncertainty_validation.md`: #63, #56, #38. Uncertainty, climate perturbation, validation.
- `hazard_data.md`: #65, #53, #42. Event, alternative weather and land use data.
- `policy_scenarios.md`: #35, #37. Custom effects, macro links.
