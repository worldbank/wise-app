# wiseapp 0.6.0

## Seasonal forecast

* Step 2 simulates welfare for a seasonal weather forecast (ECMWF SEAS5 via C3S), one weather state per member. Production runs cover 33 countries.
* Steps 2 and 3 show the forecast on one chart per question, next to Historical for the same months, Historical (annual) and the climate scenarios. A placement card shows where the forecast falls among reference years, with skill flags. Member spread is not a calibrated probability.
* Step 3 runs levers and transfers on forecast members, including every shock-responsive design: weather and impact triggers, the national gate, dynamic targeting, loss-linked budgets, and ex-post or anticipatory payments. A window is paid once and scored against each household's level in the same months of the historical years. An anticipatory transfer pays a location when a chosen share of members pass its trigger (`forecast_member_share_pct`, default 50). Step 3 adds cards for leakage, missed and false-alarm rates, loss offset and, for anticipatory payments, the cost paid before no event. These are indicators: the member spread is not calibrated.
* Batch runs add the `forecast` table and the `placement`, `skill`, `season`, `policy_effect` and `shock_window` summary sections (the latter with leakage, rate and anticipatory figures).
* Fixed repeated clicks on Run in Steps 2 and 3 being dropped.

## ENSO

* Years are labelled by El Niño, La Niña, Neutral or Mixed exposure (RONI) and marked in Steps 1 to 3, Diagnostics, the forecast flyout, exports and batch tables.
* A simulated year combines interview months and lags, so it is classified by exposure, not calendar year: the phase covering at least half of the exposed months, otherwise Mixed. Climate scenario years take the label of their template year; forecast members get one outlook for the run.
* Steps 2 and 3 add an ENSO phase toggle (off by default) and an ENSO section; Step 3 adds a policy comparison by phase.
* ENSO is annotation only and does not enter estimation or simulation. Without the ENSO tables, every ENSO element is hidden.

## Other

* Return periods use the Weibull rule (`m / (n + 1)`) throughout; the level of a 1-in-N year is slightly more adverse than before, and an observed year is given a shorter return period (the worst of 30 years is 1 in 31, not 1 in 60).
* R files renamed to `<role>_<stage or domain>_<topic>.R`. No change in behaviour.
