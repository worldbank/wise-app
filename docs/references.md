---
id: references
title: References
app_step: cross
depends_on: [notation]
symbols: []
guide: https://github.com/worldbank/wise-app-docs/blob/main/index.qmd
code: []
verified_against: 8592a9d
---

# References

> Entries cited in this folder, as BibTeX. Keys marked "guide" are the keys of the user guide's `references.bib`, so a page here and a page there cite the same work with the same key. New keys are marked "new". A later task can copy the new entries into the guide's bibliography.

## Where each work is cited

| Key | Source | Cited on |
|---|---|---|
| `moulton1990` | guide | [01_framework](01_framework.md), [20_model_specification](20_model_specification.md) |
| `cameronmiller2015` | guide | [01_framework](01_framework.md), [20_model_specification](20_model_specification.md), [21_model_linear](21_model_linear.md), [24_model_results](24_model_results.md), [33_uncertainty](33_uncertainty.md) |
| `abadie2023` | guide | [01_framework](01_framework.md), [20_model_specification](20_model_specification.md) |
| `firpo2009` | guide | [00_notation](00_notation.md), [22_model_rif](22_model_rif.md), [33_uncertainty](33_uncertainty.md), [40_policy_framework](40_policy_framework.md), [44_decomposition](44_decomposition.md) |
| `auffhammer2013` | guide | [01_framework](01_framework.md), [12_weather_measures](12_weather_measures.md), [20_model_specification](20_model_specification.md), [30_simulation](30_simulation.md), [31_climate_scenarios](31_climate_scenarios.md) |
| `burkedykema2015` | guide | [31_climate_scenarios](31_climate_scenarios.md), [33_uncertainty](33_uncertainty.md) |
| `eyring2016` | guide | [10_data](10_data.md), [31_climate_scenarios](31_climate_scenarios.md) |
| `munozsabater2021` | guide | [10_data](10_data.md), [12_weather_measures](12_weather_measures.md) |
| `c3satlas2024` | guide | [10_data](10_data.md), [31_climate_scenarios](31_climate_scenarios.md) |
| `schiavina2022` | guide | [10_data](10_data.md) |
| `uber2018` | guide | [10_data](10_data.md) |
| `worldbank2026` | guide | [10_data](10_data.md) |
| `foster1984` | new | [32_metrics](32_metrics.md) |
| `duan1983` | new | [21_model_linear](21_model_linear.md), cited by name |
| `breiman2001` | new | [23_model_ml](23_model_ml.md), cited by name |
| `friedman2001` | new | [23_model_ml](23_model_ml.md), cited by name |
| `sheather1991` | new | [22_model_rif](22_model_rif.md), cited by name |
| `silverman1986` | new | [22_model_rif](22_model_rif.md), [33_uncertainty](33_uncertainty.md), cited by name |

The guide's `burke2015` is not cited in this folder.

## BibTeX

### Keys of the user guide

```bibtex
@article{moulton1990,
  author  = {Moulton, Brent R.},
  title   = {An Illustration of a Pitfall in Estimating the Effects of Aggregate Variables on Micro Units},
  journal = {The Review of Economics and Statistics},
  year    = {1990},
  volume  = {72},
  number  = {2},
  pages   = {334--338}
}

@article{cameronmiller2015,
  author  = {Cameron, A. Colin and Miller, Douglas L.},
  title   = {A Practitioner's Guide to Cluster-Robust Inference},
  journal = {Journal of Human Resources},
  year    = {2015},
  volume  = {50},
  number  = {2},
  pages   = {317--372}
}

@article{abadie2023,
  author  = {Abadie, Alberto and Athey, Susan and Imbens, Guido W. and Wooldridge, Jeffrey M.},
  title   = {When Should You Adjust Standard Errors for Clustering?},
  journal = {The Quarterly Journal of Economics},
  year    = {2023},
  volume  = {138},
  number  = {1},
  pages   = {1--35}
}

@article{firpo2009,
  author  = {Firpo, Sergio and Fortin, Nicole M. and Lemieux, Thomas},
  title   = {Unconditional Quantile Regressions},
  journal = {Econometrica},
  year    = {2009},
  volume  = {77},
  number  = {3},
  pages   = {953--973}
}

@article{auffhammer2013,
  author  = {Auffhammer, Maximilian and Hsiang, Solomon M. and Schlenker, Wolfram and Sobel, Adam H.},
  title   = {Using Weather Data and Climate Model Output in Economic Analyses of Climate Change},
  journal = {Review of Environmental Economics and Policy},
  year    = {2013},
  volume  = {7},
  number  = {2},
  pages   = {181--198}
}

@misc{uber2018,
  author = {{Uber Technologies}},
  title  = {H3: A Hexagonal Hierarchical Spatial Index},
  year   = {2018},
  url    = {https://h3geo.org}
}

@techreport{worldbank2026,
  author      = {{World Bank}},
  title       = {Global Monitoring Database (GMD)},
  institution = {World Bank},
  address     = {Washington, DC},
  year        = {2026}
}

@article{munozsabater2021,
  author  = {Mu{\~n}oz-Sabater, Joaqu{\'i}n and others},
  title   = {ERA5-Land: A State-of-the-Art Global Reanalysis Dataset for Land Applications},
  journal = {Earth System Science Data},
  year    = {2021},
  volume  = {13},
  number  = {9},
  pages   = {4349--4383},
  doi     = {10.5194/essd-13-4349-2021}
}

@misc{c3satlas2024,
  author = {{Copernicus Climate Change Service, Climate Data Store}},
  title  = {Gridded Dataset Underpinning the Copernicus Interactive Climate Atlas},
  year   = {2024},
  doi    = {10.24381/cds.h35hb680}
}

@article{eyring2016,
  author  = {Eyring, Veronika and others},
  title   = {Overview of the Coupled Model Intercomparison Project Phase 6 (CMIP6) Experimental Design and Organization},
  journal = {Geoscientific Model Development},
  year    = {2016},
  volume  = {9},
  number  = {5},
  pages   = {1937--1958},
  doi     = {10.5194/gmd-9-1937-2016}
}

@article{burkedykema2015,
  author  = {Burke, Marshall and Dykema, John and Lobell, David B. and Miguel, Edward and Satyanath, Shanker},
  title   = {Incorporating Climate Uncertainty into Estimates of Climate Change Impacts},
  journal = {Review of Economics and Statistics},
  year    = {2015},
  volume  = {97},
  number  = {2},
  pages   = {461--471},
  doi     = {10.1162/REST_a_00478}
}

@misc{schiavina2022,
  author = {Schiavina, Marcello and Freire, Sergio and MacManus, Kytt},
  title  = {GHS-POP R2022A - GHS Population Grid Multitemporal (1975--2030)},
  year   = {2022},
  doi    = {10.2905/D83C0D50-00A9-4A23-9023-EFF10426AA37}
}
```

### New keys

```bibtex
@article{foster1984,
  author  = {Foster, James and Greer, Joel and Thorbecke, Erik},
  title   = {A Class of Decomposable Poverty Measures},
  journal = {Econometrica},
  year    = {1984},
  volume  = {52},
  number  = {3},
  pages   = {761--766}
}

@article{duan1983,
  author  = {Duan, Naihua},
  title   = {Smearing Estimate: A Nonparametric Retransformation Method},
  journal = {Journal of the American Statistical Association},
  year    = {1983},
  volume  = {78},
  number  = {383},
  pages   = {605--610}
}

@article{breiman2001,
  author  = {Breiman, Leo},
  title   = {Random Forests},
  journal = {Machine Learning},
  year    = {2001},
  volume  = {45},
  number  = {1},
  pages   = {5--32}
}

@article{friedman2001,
  author  = {Friedman, Jerome H.},
  title   = {Greedy Function Approximation: A Gradient Boosting Machine},
  journal = {The Annals of Statistics},
  year    = {2001},
  volume  = {29},
  number  = {5},
  pages   = {1189--1232}
}

@article{sheather1991,
  author  = {Sheather, Simon J. and Jones, M. C.},
  title   = {A Reliable Data-Based Bandwidth Selection Method for Kernel Density Estimation},
  journal = {Journal of the Royal Statistical Society: Series B},
  year    = {1991},
  volume  = {53},
  number  = {3},
  pages   = {683--690}
}

@book{silverman1986,
  author    = {Silverman, B. W.},
  title     = {Density Estimation for Statistics and Data Analysis},
  publisher = {Chapman and Hall},
  address   = {London},
  year      = {1986}
}
```

## Implementation map

This page has no code. The entries are data for the references of the other pages.
