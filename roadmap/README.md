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
- `seasonal_forecast.md`: seasonal forecast scenario (method `docs/34_seasonal_forecast.md`). Branch `seasonal-forecast`.
