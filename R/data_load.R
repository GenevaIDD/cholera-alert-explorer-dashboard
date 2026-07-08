## ---------------------------------------------------------------------------
## data_load.R
## Loads the data the app needs at runtime:
##   - view1_tbl : the precomputed pooled (all-country) per-definition utility
##                 table, read from data/complete_utility_data_mean_sd.csv
##                 (the output of alert_utility_score.qmd).
##   - country_tbl : the same dimensions broken out by country, combined from
##                 data/country_utility_lt50k.csv, country_utility_50k_500k.csv
##                 and country_utility_gte500k.csv. NULL if those files are
##                 absent. Lacks the pooled table's SD/N companion columns.
##   - time_series, alert_groups : used by View 2 (the timeline explorer).
## View 1 only displays these tables - no utility calculations run in the app.
## ---------------------------------------------------------------------------

#' Recode whatever population-bracket labels appear in the precomputed table
#' to the app's internal codes ("<50k", "50k-500k", ">500k"). Handles the
#' manuscript/qmd labels ("< 50k", "[50k, 500k)", "\u2265 500k") as well as
#' the app's own codes.
recode_pop_brk <- function(x) {
  x <- trimws(as.character(x))
  dplyr::case_when(
    x %in% c("<50k", "< 50k")                          ~ "<50k",
    x %in% c("50k-500k", "[50k, 500k)", "[50k,500k)")  ~ "50k-500k",
    grepl("500k", x) & grepl("\u2265|>=|>", x)         ~ ">500k",
    x == ">500k"                                       ~ ">500k",
    TRUE ~ x
  )
}

#' Load the precomputed View 1 utility table from CSV (or Parquet fallback).
#' Returns NULL if no file is found.
load_view1_table <- function(data_dir) {
  csv_path <- file.path(data_dir, "complete_utility_data_mean_sd.csv")
  parquet_path <- file.path(data_dir, "view1_utility_table.parquet")

  if (file.exists(csv_path)) {
    tbl <- utils::read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE,
                           fileEncoding = "UTF-8")
    ## drop the unnamed row-index column the CSV carries, if present
    if (names(tbl)[1] == "" || names(tbl)[1] == "X") tbl <- tbl[, -1, drop = FALSE]
  } else if (file.exists(parquet_path)) {
    tbl <- as.data.frame(arrow::read_parquet(parquet_path))
  } else {
    return(NULL)
  }

  tbl$pop_brk <- recode_pop_brk(tbl$pop_brk)
  if ("alert_lab" %in% names(tbl)) tbl$alert_lab <- enc2utf8(as.character(tbl$alert_lab))
  tbl
}

#' Load and combine the per-country utility tables (one CSV per population
#' group: country_utility_lt50k.csv, country_utility_50k_500k.csv,
#' country_utility_gte500k.csv). Each row is one (country, population group,
#' alert definition) combination. Unlike the pooled table
#' (complete_utility_data_mean_sd.csv), these do not carry sd_impact,
#' sd_eff, sd_delay, n_alerts or n_outbreaks - build_top_alerts_table()
#' formats those columns conditionally when absent.
#'
#' Returns NULL if none of the three files are present, so the country
#' selector can degrade gracefully to "pooled only" rather than erroring.
load_country_tbl <- function(data_dir) {
  sources <- list(
    "<50k"     = "country_utility_lt50k.csv",
    "50k-500k" = "country_utility_50k_500k.csv",
    ">500k"    = "country_utility_gte500k.csv"
  )

  parts <- lapply(names(sources), function(pop_brk) {
    path <- file.path(data_dir, sources[[pop_brk]])
    if (!file.exists(path)) return(NULL)
    tbl <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                           fileEncoding = "UTF-8")
    tbl$pop_brk <- pop_brk
    tbl$alert_lab <- enc2utf8(as.character(tbl$alert_lab))
    tbl$country <- toupper(trimws(as.character(tbl$country)))
    tbl
  })
  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0) return(NULL)

  tbl <- dplyr::bind_rows(parts)
  add_alert_number(tbl)  # defined in utility_calc.R; safe here since this is
                          # only ever called from load_app_data(), which itself
                          # only runs after every R/ file has been sourced
}

#' Load application data.
#'
#' @param data_dir directory containing the data files
#' @return a named list: view1_tbl, country_tbl, dist_tbl, time_series, alert_groups
load_app_data <- function(data_dir = "data") {

  alert_groups <- as.data.frame(arrow::read_parquet(file.path(data_dir, "alert_groups_nweeks8.parquet")))
  time_series <- as.data.frame(arrow::read_parquet(file.path(data_dir, "time_series_preoutbreak_extraction.parquet")))

  ## data ships anonymised + slimmed (see anonymize_data.R): `location` is an
  ## opaque id, and only the columns the app needs are present. The selects
  ## below are defensive in case a fuller extract is dropped in.
  time_series <- dplyr::select(time_series, dplyr::any_of(c("location", "TL", "sCh")))
  alert_groups <- dplyr::select(alert_groups, dplyr::any_of(c(
    "location", "alert_number", "alert_type", "TL_first_alert"
  )))

  list(
    view1_tbl = load_view1_table(data_dir),
    country_tbl = load_country_tbl(data_dir),
    dist_tbl = load_dist_table(data_dir),
    time_series = time_series,
    alert_groups = alert_groups
  )
}

#' Load the raw per-alert-group distributions used to draw the View 1
#' Figure-2-style boxplots (Impact, Efficiency, Timeliness), from the
#' compare_significant_*_testmeans_epidemic.parquet exports. Returns a long
#' table (pop_brk, country, alert_number, alert_lab, alert_type, dimension,
#' value) or NULL. `country` is present when the source files carry it (it
#' does as of the pipeline update that added country-level exports); older
#' pooled-only exports without a country column still work, just without a
#' country breakdown of the boxplots.
load_dist_table <- function(data_dir) {
  imp_path <- file.path(data_dir, "compare_significant_impact_testmeans_epidemic.parquet")
  eff_path <- file.path(data_dir, "compare_significant_efficiency_testmeans_epidemic.parquet")
  dly_path <- file.path(data_dir, "compare_significant_delay_testmeans_epidemic.parquet")

  if (!file.exists(imp_path) && !file.exists(dly_path)) return(NULL)

  norm <- function(df, dimension, value_col) {
    out <- df %>%
      dplyr::transmute(
        pop_brk    = recode_pop_brk(pop_brk),
        alert_number,
        alert_lab  = enc2utf8(as.character(alert_lab)),
        alert_type = as.character(alert_type),
        dimension  = dimension,
        value      = .data[[value_col]],
        country    = if ("country" %in% names(df)) toupper(trimws(as.character(country))) else NA_character_
      ) %>%
      dplyr::filter(!is.na(value))
    out
  }

  parts <- list()
  if (file.exists(imp_path)) {
    imp <- as.data.frame(arrow::read_parquet(imp_path))
    parts$impact <- norm(imp, "Impact", "impact")
    eff_src <- if (file.exists(eff_path)) as.data.frame(arrow::read_parquet(eff_path)) else imp
    parts$eff <- norm(eff_src, "Efficiency", "eff")
  }
  if (file.exists(dly_path)) {
    parts$delay <- norm(as.data.frame(arrow::read_parquet(dly_path)), "Timeliness", "delay")
  }

  if (length(parts) == 0) return(NULL)
  dplyr::bind_rows(parts)
}
