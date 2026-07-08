# Cholera Alert Explorer (Shiny app)

A four-tab research tool for comparing cholera outbreak alert definitions:
**How to use the app** (help), **Top Alert Definitions** (View 1, utility
scores), **Explore Timelines** (View 2, alert-window explorer),
and **About us**.

## Running the app 

```r
shiny::runApp()
```

Requires: `shiny`, `dplyr`, `tidyr`, `ggplot2`, `kableExtra`, `patchwork`, `arrow`
(all available via CRAN, or via `apt install r-cran-shiny r-cran-dplyr
r-cran-tidyr r-cran-ggplot2 r-cran-kableextra r-cran-patchwork r-cran-arrow` on
Debian/Ubuntu). Data files are Parquet, read via `arrow::read_parquet()`.

## Directory structure

```
alerts_app/
├── app.R                       # entry point (UI + server wiring, 4 tabs)
├── R/
│   ├── data_load.R           # loads the precomputed data
│   ├── utility_calc.R        # labels, table formatter, distribution figure
│   ├── view1_utility.R       # "Top Alert Definitions" module (UI + server)
│   ├── view2_timeseries.R    # "Explore Timelines" module (UI + server)
│   ├── view_help.R           # "How to use the app" (static help page)
│   └── view_about.R          # "About us" (static project info page)
└── data/
    ├── complete_utility_data_mean_sd.csv                  
    ├── compare_significant_impact_testmeans_epidemic.parquet     
    ├── compare_significant_efficiency_testmeans_epidemic.parquet 
    ├── compare_significant_delay_testmeans_epidemic.parquet      
    ├── alert_groups_nweeks8.parquet                           
    └── time_series_preoutbreak_extraction.parquet             
```


