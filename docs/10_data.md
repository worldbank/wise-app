---
id: data
title: Data and spatial linking
app_step: 0
depends_on: [notation, framework]
symbols: [i, l, t, mu, Y, omega]
guide: https://github.com/worldbank/wise-app-docs/blob/main/data.qmd
code: [R/fct_surveystats.R, R/fct_step1_data.R, R/fct_loc_panel.R, R/fct_get_weather.R, R/fct_sample.R, R/fct_incidence.R, R/fct_weatherstats.R]
verified_against: 6529b81
---

# Data and spatial linking

> WISE-APP joins household survey microdata to monthly weather through H3 grid cells. This page describes what the three data sources contain, how survey welfare is put in 2021 prices, how weather is attached to survey locations, and how locations are grouped across survey rounds. The file layout and column definitions are in the data preparation repository, not here.

## Setup

Three kinds of input are used.

| Input | Content | Source |
|---|---|---|
| Survey microdata | Harmonised household, individual or firm records with welfare, characteristics, interview month and a location code tied to H3 cells | Global Monitoring Database [@worldbank2026], geocoded |
| Observed weather | Monthly weather variables on a global grid, from 1950 | ERA5-Land reanalysis [@munozsabater2021], taken from the Copernicus climate atlas [@c3satlas2024] |
| Climate projections | The same variables for up to 30 members of the CMIP6 ensemble [@eyring2016], for a historical baseline (1950 to 2014) and three emissions pathways (2015 to 2100) | Same atlas |

Three metadata tables describe the surveys, the variables and the price deflators. Their columns and the directory layout are defined in the data repository: <https://github.com/worldbank/wise-app-data>. This page does not copy them, so the two cannot drift apart.

The data may be read from a local folder or from cloud storage. The source does not change any computation. See [Overview](https://github.com/worldbank/wise-app-docs/blob/main/data.qmd#connecting-wise-app-to-data) in the user guide.

## Method

### 1. Survey welfare in 2021 prices

Every variable that the variable list marks as a local-currency amount is converted to 2021 international dollars per person per day. For unit $i$ in country $c$, survey year $t$ and data level $d$:

$$Y_i^{\text{PPP}} = \frac{Y_i^{\text{LCU, nominal}}}{\text{CPI}_{ct}\ \pi_{ct}} \qquad \text{(1.1)}$$

where $\text{CPI}_{ct}$ is the price index that takes survey-year prices to 2021 prices and $\pi_{ct}$ is the 2021 conversion factor from local currency to PPP dollars, both as supplied in the CPI and PPP table. The table is matched on country, survey year and a data level. The data level is "national" for every country except China, where urban and rural households use separate deflators.

After conversion, welfare is bottom-coded at $0.28$ per person per day (Eq. (1.2) in [00_notation](00_notation.md)). This is the floor of the World Bank Poverty and Inequality Platform.

A survey record with no matching deflator keeps a missing converted value. Such records fall out of any model that uses that variable. The app counts them and reports the number.

### 2. Locations and weather cells

A survey location $\ell$ is a set of H3 cells that the geocoding step assigned to the interview cluster. A survey with GPS coordinates gives small locations. A survey that reports only an administrative area gives one large location made of many cells.

The weather grid and the survey cells can have different H3 resolutions. The app maps both to the coarser of the two, so that each weather value is joined to the survey cells it covers.

### 3. Weather at the location

The weather of location $\ell$ in calendar month $h$ (a month of a given year) is the population-weighted mean of the weather in its cells:

$$x_{\ell h} = \frac{\sum_{c} p_{\ell c}\  x_{ch}\ \mathbf{1}[x_{ch}\ \text{observed}]}{\sum_{c} p_{\ell c}\ \mathbf{1}[x_{ch}\ \text{observed}]} \qquad \text{(3.1)}$$

where $x_{ch}$ is the monthly value in weather cell $c$ and $p_{\ell c}$ is the 2020 population in the part of cell $c$ that lies in location $\ell$ [@schiavina2022]. Population weights give more weight to the settled parts of a large location. When a mapping file carries no population, every cell receives weight one. A cell-month with a missing value drops out of both sums for that variable only; the other variables of the same cell are kept.

All households in a location and month receive the same $x_{\ell h}$. This is why standard errors are clustered at the location level ([20_model_specification](20_model_specification.md)).

Eq. (3.1) gives the raw monthly series. Rolling windows, anomalies and bins are built on top of it in [12_weather_measures](12_weather_measures.md).

### 4. Location panels

The same place appears in several survey rounds with slightly different cluster boundaries. Two locations $A$ and $B$ are linked when their cell overlaps are large in both directions:

$$o_{A\to B} = \frac{\sum_{c \in A\cap B} p_{Ac}}{\sum_{c \in A} p_{Ac}}, \qquad \text{link if } \min\lbrace o_{A\to B},\  o_{B\to A}\rbrace  \ge 0.5 \qquad \text{(4.1)}$$

A location panel is a connected set of linked locations. If $A$ links to $B$ and $B$ links to $C$, all three are in one panel. Locations with no link form their own panel. The panel identifier $g_\ell$ is the cluster used for standard errors in Steps 1 and 2.

### 5. Merging survey and weather

Each survey record is matched to the weather of its location and interview month. Records without matching weather are dropped, and their number is reported. The weather table has one row per location and month. A duplicated key stops the merge with an error, so a record is never counted twice.

### 6. Variable roles

A variable list assigns each variable one or more roles: outcome, weather variable, individual, household, firm or area characteristic, eligible moderator, eligible fixed effect, and policy lever. The roles decide which variables the Model tab offers. A variable becomes a policy lever when the list gives it a policy code. The code, not the variable name, identifies the lever everywhere in Step 3 ([41_policy_levers](41_policy_levers.md)).

### 7. Sampling weights

The weight column is read from the survey under the first of the names `weight`, `hhweight`, `wgt`, `pw` that exists. The same column is used by every weighted statistic in Steps 2 and 3.

## Interpretation

- The interview month fixes which weather the model attaches to a household. A wrong or missing month makes the household drop out or receive the wrong weather.
- Location weather is an area average. For a survey with coarse geography, it describes the area, not the household.
- The 2021 PPP scale makes welfare comparable across countries and rounds. It does not remove differences in survey design or question wording.

## Assumptions

- **A1. Correct geocoding and timing.** The interview month and location assigned to each record are right.
- **A2. Area weather proxies household exposure.** The population-weighted location mean represents the weather that the household experienced.
- **A3. Deflators are right.** The CPI and PPP factors convert each survey to comparable 2021 prices.
- **A4. Population weights stable.** The 2020 population within cells is used for every survey round, whatever its year.

## Limitations and what is not modelled

- Variation of weather inside a location is not used.
- Survey design variables (strata and primary sampling units) are not available, so design-based standard errors cannot be computed.
- Variables are harmonised but not always strictly comparable across surveys.
- Households that moved, or interviews held away from the location, are not detected.
- Missing deflators and missing weather months reduce the sample without any imputation.

## In the app

- Step 0 > Overview: data source and survey list.
- Step 1 > Sample: economy, survey rounds and level of analysis; **Survey stats** shows interview timing and the location map.

User guide: [Data](https://github.com/worldbank/wise-app-docs/blob/main/data.qmd).

## References

[@worldbank2026], [@munozsabater2021], [@c3satlas2024], [@eyring2016], [@schiavina2022], [@uber2018]. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Conversion to 2021 PPP | (1.1) | `R/fct_surveystats.R` `convert_lcu_to_ppp()`, `assign_data_level()` |
| Bottom-coding | (1.2) in notation | `R/fct_surveystats.R` `bottom_code_welfare()` |
| Survey preparation order | (1.1) | `R/fct_step1_data.R` `prepare_survey_data()` |
| Records without deflator | (1.1) | `R/fct_step1_data.R` `survey_n_no_deflator()` |
| H3 resolution harmonisation | 2 | `R/fct_get_weather.R` `.harmonise_h3()` |
| Population-weighted location weather | (3.1) | `R/fct_get_weather.R` `get_weather()` |
| Location panel | (4.1) | `R/fct_loc_panel.R` `loc_panel()`; `R/fct_step1_data.R` `wise_location_panel()` |
| Survey-weather merge | 5 | `R/fct_weatherstats.R` `merge_survey_weather()` |
| Weight column | 7 | `R/fct_incidence.R` `survey_weight_column()` |
| Available surveys and files | 5 | `R/fct_sample.R` `build_survey_fnames()`, `build_selected_surveys()` |
