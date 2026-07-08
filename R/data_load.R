## ---------------------------------------------------------------------------
## data_load.R
## Loads the data the app needs at runtime:
##   - view1_tbl : the precomputed per-definition utility table, read directly
##                 from data/complete_utility_data_mean_sd.csv (the output of
##                 alert_utility_score.qmd). View 1 only displays this - no
##                 utility calculations run in the app.
##   - time_series, alert_groups : used by View 2 (the timeline explorer).
## The heavy alerts.rds extract is not needed and is not loaded.
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

#' Load application data.
#'
#' @param data_dir directory containing the data files
#' @return a named list: view1_tbl, dist_tbl, time_series, alert_groups
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
    dist_tbl = load_dist_table(data_dir),
    time_series = time_series,
    alert_groups = alert_groups
  )
}

#' Load the raw per-alert-group distributions used to draw the View 1
#' Figure-2-style boxplots (Impact, Efficiency, Timeliness), from the
#' compare_significant_*_testmeans_epidemic.parquet exports. Returns a long
#' table (pop_brk, alert_number, alert_lab, alert_type, dimension, value) or
#' NULL.
load_dist_table <- function(data_dir) {
  imp_path <- file.path(data_dir, "compare_significant_impact_testmeans_epidemic.parquet")
  eff_path <- file.path(data_dir, "compare_significant_efficiency_testmeans_epidemic.parquet")
  dly_path <- file.path(data_dir, "compare_significant_delay_testmeans_epidemic.parquet")

  if (!file.exists(imp_path) && !file.exists(dly_path)) return(NULL)

  norm <- function(df, dimension, value_col) {
    df %>%
      dplyr::transmute(
        pop_brk    = recode_pop_brk(pop_brk),
        alert_number,
        alert_lab  = enc2utf8(as.character(alert_lab)),
        alert_type = as.character(alert_type),
        dimension  = dimension,
        value      = .data[[value_col]]
      ) %>%
      dplyr::filter(!is.na(value))
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
