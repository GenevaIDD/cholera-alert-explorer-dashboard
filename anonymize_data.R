## ---------------------------------------------------------------------------
## anonymize_data.R  (run once, offline)
##
## Produces the anonymised, slimmed data/ files that ship in the repo from the
## name-bearing originals in data_raw/ (which are git-ignored and never
## committed). The app only ever uses `location` as an opaque join/sample key
## and never displays it, so replacing each location string with a random ID
## ("loc00001", ...) and dropping country/admin columns has no effect on the
## app's behaviour.
##
## Outputs (into data/, as Parquet):
##   - time_series_preoutbreak_extraction.parquet : location(id), TL, sCh
##   - alert_groups_nweeks8.parquet               : location(id), alert_number,
##                                                  alert_type, TL_first_alert
##   - compare_significant_*_testmeans_epidemic.parquet : pop_brk, alert_number,
##                                                  alert_lab, alert_type,
##                                                  <value>, which_setting
##                                                  (location / country / admin /
##                                                  alert_id / outbreak_UID dropped)
##   - complete_utility_data_mean_sd.csv already contains no location and is
##     left untouched.
##
## Also writes location_key.csv (git-ignored): the location -> id mapping,
## kept private so the anonymisation can be reversed for debugging. Delete it
## for irreversible anonymisation.
## ---------------------------------------------------------------------------

suppressMessages({library(dplyr); library(arrow)})
set.seed(20240101)  # reproducible ID assignment

raw_dir <- "data_raw"
out_dir <- "data"

## data_raw/ originals are provided as .rds; only the app's own data/ files
## are Parquet.
ts <- readRDS(file.path(raw_dir, "time_series_preoutbreak_extraction.rds"))
ag <- readRDS(file.path(raw_dir, "alert_groups_nweeks8.rds"))

## --- build a single location -> opaque id map (shuffled so ids don't leak
##     any alphabetical / country ordering) ----------------------------------
all_locs <- sort(unique(c(as.character(ts$location), as.character(ag$location))))
all_locs <- sample(all_locs)                       # shuffle
ids <- sprintf("loc%05d", seq_along(all_locs))
loc_map <- stats::setNames(ids, all_locs)

write.csv(
  data.frame(location = names(loc_map), location_id = unname(loc_map)),
  file.path(".", "location_key.csv"), row.names = FALSE
)

anon <- function(x) unname(loc_map[as.character(x)])

## --- time series: keep only what View 2 needs ------------------------------
ts_out <- ts %>%
  dplyr::transmute(location = anon(location), TL, sCh)
arrow::write_parquet(ts_out, file.path(out_dir, "time_series_preoutbreak_extraction.parquet"))

## --- alert groups: keep only what View 2 needs -----------------------------
## TL_last_alert is dropped - the app only ever uses TL_first_alert.
ag_out <- ag %>%
  dplyr::transmute(location = anon(location), alert_number, alert_type,
                   TL_first_alert)
arrow::write_parquet(ag_out, file.path(out_dir, "alert_groups_nweeks8.parquet"))

## --- distribution files: drop every name-bearing column --------------------
strip_dist <- function(fname, value_col) {
  d <- readRDS(file.path(raw_dir, paste0(fname, ".rds")))
  keep <- intersect(c("pop_brk", "alert_number", "alert_lab", "alert_type",
                       value_col, "which_setting"), names(d))
  arrow::write_parquet(dplyr::select(d, dplyr::all_of(keep)),
                        file.path(out_dir, paste0(fname, ".parquet")))
}
strip_dist("compare_significant_impact_testmeans_epidemic", "impact")
strip_dist("compare_significant_efficiency_testmeans_epidemic", "eff")
strip_dist("compare_significant_delay_testmeans_epidemic", "delay")

cat("Anonymised", length(loc_map), "locations.\n")
cat("Wrote anonymised Parquet files to", out_dir, "and location_key.csv (keep private).\n")
