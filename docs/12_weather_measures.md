---
id: weather-measures
title: Weather measures
app_step: 1
depends_on: [notation, data]
symbols: [W, mu, l, v, x]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#weather-variables-transformations
code: [R/fct_get_weather.R, R/fct_weather_select.R, R/fct_weather_pipeline.R, R/fct_weatherstats.R, R/fct_loc_panel.R, R/utils_mod_1_helpers.R, R/mod_1_04_weather.R, R/mod_1_05_weatherstats.R]
verified_against: 6529b81
---

# Weather measures

> The regressors $W_i$ are built from the monthly location weather of [10_data](10_data.md) in four steps: a window of months before the interview, an aggregation over the window, an optional transformation to an anomaly, and a functional form (levels with polynomials, or bins). This page defines each step. The same steps are applied to historical and to projected weather, so a bin or an anomaly means the same thing in Steps 1, 2 and 3.

## Setup

The user picks up to two weather variables. For each variable $v$ the user sets:

| Choice | Options | Default |
|---|---|---|
| Reference period | first and last month before the interview, 0 to 12 | 1 to 1 (the month before the interview) |
| Temporal aggregation | mean, median, min, max, and sum for variables measured in millimetres or days | sum for millimetres and days, maximum for the five-day maximum rainfall, mean otherwise |
| Transformation | none, deviation from the normal, standardised anomaly | none; standardised anomaly for dimensionless indices, the only option for them |
| Functional form | bins or continuous with optional squared and cubic terms | 5 bins |
| Binning rule | equal frequency, equal width, k-means, custom cut points | equal frequency |

Let $x_{\ell h}$ denote the monthly location weather of variable $v$ (Eq. (3.1) in [10_data](10_data.md)), for location $\ell$ and month $h$. Let $h_i$ be the month in which unit $i$ was interviewed.

## Method

### 1. Window and aggregation

With a reference period from $a$ to $b$ months before the interview ($0 \le a \le b \le 12$), the aggregated value is

$$\tilde x_{\ell h} = \mathcal{G}\big(\{\, x_{\ell,\,h-k} : k = a,\dots,b,\ x_{\ell,h-k}\ \text{observed} \,\}\big) \tag{1.1}$$

where $\mathcal{G}$ is the mean, median, minimum, maximum or sum. The month $k=0$ is the interview month itself. The window is counted in calendar months, so a month missing from the weather record leaves a gap in the window instead of pulling in an older month. Months with no observation are skipped. If $a=b$, the window holds one month and no aggregation is applied. A unit's regressor is $\tilde x_{\ell h_i}$.

### 2. Transformation to an anomaly

A transformation compares $\tilde x_{\ell h}$ with the local **normal** for the same calendar month. The normal uses the aggregated series of Eq. (1.1) over 1991 to 2020. For location $\ell$ and calendar month $\mu$:

$$\bar x_{\ell\mu} = \frac{1}{|\mathcal{T}_\mu|}\sum_{h \in \mathcal{T}_\mu} \tilde x_{\ell h}, \qquad s_{\ell\mu}^2 = \frac{1}{|\mathcal{T}_\mu|-1}\sum_{h \in \mathcal{T}_\mu}\big(\tilde x_{\ell h}-\bar x_{\ell\mu}\big)^2 \tag{2.1}$$

where $\mathcal{T}_\mu$ is the set of months of 1991 to 2020 with calendar month $\mu$ and an observed value. The calendar month $\mu$ is the month of $h$, that is, the interview month, and not the months inside the window. The two transformations are

$$\text{deviation: } \tilde x_{\ell h} - \bar x_{\ell\mu}, \qquad \text{standardised anomaly: } \frac{\tilde x_{\ell h} - \bar x_{\ell\mu}}{s_{\ell\mu}} \tag{2.2}$$

The standardised anomaly is missing where $s_{\ell\mu}=0$, for example for rainfall in a month that is always dry. The app warns about the number of such location-months. The six-month standardised precipitation index and the six-month standardised precipitation-evapotranspiration index are already standardised. They are not transformed, although the control offers the standardised anomaly for them.

The normal does not depend on the historical window chosen in Step 2 or on the climate scenario. It is the same in the historical and the projected weather.

### 3. Functional form

Let $u_{\ell h}$ be the value after Eq. (1.1) and, if chosen, Eq. (2.2).

**Continuous.** The regressors are $u$, and optionally $u^2$ and $u^3$. Each is a column of $W_i$.

**Bins.** The range of $u$ is cut at $B-1$ interior points $c_1<\dots<c_{B-1}$. The outer bins are open-ended, so values outside the observed range, such as projected values, fall in the first or last bin. The bins are $(-\infty, c_1]$, $(c_1,c_2]$, ..., $(c_{B-1},\infty)$. The lowest bin is the reference and $W_i$ holds the $B-1$ indicators of the other bins:

$$W_{ib} = \mathbb{1}\big[\,c_{b-1} < u_{\ell h_i} \le c_b\,\big], \qquad b = 2,\dots,B \tag{3.1}$$

The interior cut points are set once, from a reference sample described next, and stored. The same cut points are then applied to every later weather series.

| Rule | Cut points |
|---|---|
| Equal frequency | The sample quantiles at $j/B$, $j=1,\dots,B-1$ |
| Equal width | $B$ equal intervals between the sample minimum and maximum |
| K-means | One-dimensional k-means with $B$ centres, started from a fixed seed; cuts at the midpoints between ordered centres |
| Custom | The cut points typed by the user; $B$ is one more than their number |

Duplicate cut points are dropped, so the number of bins can be smaller than requested. If a rule cannot produce cut points, such as k-means with fewer distinct values than bins, the variable stays continuous and a message says so.

**Reference sample.** The cut points are computed from the transformed weather at every location of the selected surveys, in all months that coincide with an interview month of any selected survey. The sample is pooled, unweighted, and not restricted to the months in which a given location was interviewed.

### 4. Two variables

With two weather variables, each has its own window, aggregation, transformation and form. Both enter the model together. Weather-by-moderator interactions are formed for each weather term separately ([20_model_specification](20_model_specification.md)). The app does not build joint terms between the two variables.

### 5. Weather statistics of the Step 1 sample

The Weather stats tab describes the sample with the regressors above and does not enter the estimation.

- **Weighted summaries** by country and survey round: weighted mean, weighted standard deviation, minimum, maximum and count, with the survey weight $\omega_i$.
- **Comparison with own history.** For each location, the historical weather is taken for the same location and the same calendar months as the interviews, for the years in the chosen historical window. Each location-month cell receives the weight $n_{\ell\mu}$, the number of sampled units interviewed there. For a wave value $\hat s_\ell$ (the mean over the location's interview months, weighted by $n_{\ell\mu}$) and the history $\{v_j\}$ with weights $n_j$:

$$\text{anomaly}_\ell = \hat s_\ell - \frac{\sum_j n_j v_j}{\sum_j n_j}, \qquad \text{percentile}_\ell = 100\,\frac{\sum_j n_j\big(\mathbb{1}[v_j<\hat s_\ell] + \tfrac12\mathbb{1}[v_j=\hat s_\ell]\big)}{\sum_j n_j} \tag{5.1}$$

The historical window includes the survey year. For binned variables, a location shows its modal bin.

## Interpretation

- An anomaly regressor measures weather relative to what a location normally receives in that calendar month. It removes the local seasonal climate. A level regressor still carries differences between locations and between seasons, which the default fixed effects (area and survey round) do not remove. The two choices therefore identify the effect from different variation.
- A bin coefficient is the difference in outcome between that bin and the lowest bin, holding the other terms fixed.
- A short reference period is a statement about timing. A one-month window assumes that last month's weather is what matters. A longer window with a mean or sum treats the months as equally important.
- The percentile in Eq. (5.1) is 50 for a typical year. Locations with percentiles that barely change across rounds add little within-location variation to the estimation.

## Assumptions

- **A1. Relevant window.** The chosen reference period contains the weather through which welfare responds. The app does not test this.
- **A2. Stable normal.** The 1991 to 2020 normal is a fair baseline for the local climate in all survey and simulation years.
- **A3. Adequate bins.** The bin cut points, set from the pooled sample, describe the support that the model will meet in simulations. Outer bins absorb anything beyond.
- **A4. Monthly resolution.** Monthly aggregates capture the weather feature that matters. Within-month extremes are only seen through variables that are built to count them, such as days above a threshold.

## Limitations and what is not modelled

- Crop calendars and growing seasons are not used. The window is the same in every location.
- Not more than two weather variables.
- Cut points are not weighted by population or by the number of interviews.
- A missing month inside the window is skipped, not imputed, so the window can contain fewer months in some units than in others.
- The normal is a fixed 30-year period; trends inside it are not removed.

## In the app

- Step 1 > Weather: choose variables, then **Configure** each one. **Weather stats** shows the pipeline for each variable, the distribution of each wave against its own history, maps of the regressor, binned scatter plots of the outcome, and summary tables.

User guide: [Weather variables and transformations](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#weather-variables-transformations).

## References

[@munozsabater2021] for the observed weather; [@auffhammer2013] for the use of weather variables in economic analysis. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Defaults per variable | Setup | `R/fct_weather_select.R` `weather_spec_defaults()`, `temporal_agg_default()`, `transformation_default()` |
| Window and aggregation | (1.1) | `R/fct_get_weather.R` `get_weather()` (rolling expressions) |
| Normal and anomalies | (2.1), (2.2) | `R/fct_get_weather.R` `.build_climate_reference()`, `.apply_transformations()`, `.warn_zero_sd_reference()` |
| Cut points | 3 | `R/fct_get_weather.R` `.compute_breaks()` |
| Binning | (3.1) | `R/fct_get_weather.R` `.apply_binning()`; `R/fct_weather_select.R` `relabel_bin_levels()`, `parse_custom_breaks()` |
| Polynomial terms | 3 | `R/fct_fit_model.R` `fit_model()` |
| Dates of historical comparison | (5.1) | `R/fct_weatherstats.R` `expand_hist_dates()`, `join_hist_sample_cells()` |
| Anomaly and percentile | (5.1) | `R/fct_weatherstats.R` `summarise_weather_anomaly_by_loc()`, `summarise_weather_by_loc()` |
| Weighted summaries | 5 | `R/utils_mod_1_helpers.R` `weighted_summary_long()`; `R/fct_weatherstats.R` `build_weather_stats_table()` |
| Pipeline description in the card | Setup | `R/fct_weather_pipeline.R` `weather_pipeline_stages()` |
