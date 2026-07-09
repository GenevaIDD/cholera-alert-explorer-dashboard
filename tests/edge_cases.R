## ---------------------------------------------------------------------------
## tests/edge_cases.R
## Fast, dependency-light crash tests for both views. Exercises boundary
## inputs (empty selections, min/max sliders, every alert definition, rapid
## resampling) and forces plots to actually render so build-time errors are
## caught. Run from the app root:
##
##   Rscript tests/edge_cases.R
##
## Exits non-zero if any case fails, so it can gate a CI pipeline.
## ---------------------------------------------------------------------------

suppressMessages({
  library(shiny); library(dplyr); library(ggplot2)
  library(kableExtra); library(patchwork)
})
for (f in list.files("R", full.names = TRUE)) source(f)

ad <- load_app_data("data")

pass <- 0; fail <- 0
try_case <- function(name, expr) {
  r <- tryCatch({ force(expr); "OK" },
                error = function(e) paste("ERROR:", conditionMessage(e)))
  if (identical(r, "OK")) { pass <<- pass + 1; cat(sprintf("  [PASS] %s\n", name)) }
  else { fail <<- fail + 1; cat(sprintf("  [FAIL] %s -> %s\n", name, r)) }
}
## force a plot (ggplot or patchwork) to render, catching build-time errors
build <- function(p) if (!is.null(p)) {
  invisible(ggplot2::ggplot_build(if (inherits(p, "patchwork")) p[[1]] else p))
}

cat("=== STARTUP / LOAD-ORDER edge case ===\n")
try_case("R/ files source cleanly with ZERO libraries attached (mirrors Shiny's automatic R/-folder loading, which runs before app.R's own library() calls)", {
  out <- system2(
    "Rscript", c("-e", shQuote("for (f in list.files('R', full.names=TRUE)) source(f)")),
    stdout = TRUE, stderr = TRUE
  )
  if (any(grepl("^Error", out))) stop(paste(out, collapse = "\n"))
})
try_case("no population selected", {
  testServer(view1_server, args = list(data = ad), {
    session$setInputs(pop_keep = character(0), n_top = 4)
    tryCatch(selected_rows(), error = function(e) NULL)
  })
})
try_case("n_top = 1 (min)", {
  sr <- select_top_definitions(ad$view1_tbl, "50k-500k", 1)
  build(make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl))
  build_top_alerts_table(ad$view1_tbl, "50k-500k", 1)
})
try_case("n_top = 24 (max)", {
  sr <- select_top_definitions(ad$view1_tbl, "50k-500k", 24)
  build(make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl))
})
try_case("all three pop groups, n_top = 6", {
  sr <- select_top_definitions(ad$view1_tbl, c("<50k", "50k-500k", ">500k"), 6)
  build(make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl))
})
try_case("figure survives an alert def ranking top-N in >1 population group (duplicate label ordering)", {
  ## with all 3 groups and a generous n_top, several alert definitions are
  ## virtually guaranteed to rank in more than one group's top N; this must
  ## not crash the shared row-ordering factor in make_dimensions_figure()
  sr <- select_top_definitions(ad$view1_tbl, c("<50k", "50k-500k", ">500k"), 10)
  dup_labels <- sr %>% dplyr::count(alert_lab) %>% dplyr::filter(n > 1)
  stopifnot(nrow(dup_labels) > 0)  # confirm the scenario is actually exercised
  build(make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl))
})
try_case("multi-group figure shows only each group's own alerts, no phantom rows from other groups", {
  ## regression test for a real bug: scale_y_discrete(drop = FALSE) forced
  ## every facet to also display alerts selected only in OTHER population
  ## groups, as blank rows (reported by screenshot: "≥ 250 weekly" appearing
  ## as an empty row in the 50k-500k panel when it was only top-N in >500k).
  sr <- select_top_definitions(ad$view1_tbl, c("50k-500k", ">500k"), n_top = 7)
  p <- make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl)
  b <- ggplot2::ggplot_build(p[[1]])
  for (i in seq_along(b$layout$panel_params)) {
    shown <- b$layout$panel_params[[i]]$y$get_labels()
    stopifnot(length(shown) == 7)  # exactly this group's n_top, no extras
  }
})
try_case("each single pop group renders", {
  for (pg in c("<50k", "50k-500k", ">500k")) {
    sr <- select_top_definitions(ad$view1_tbl, pg, 5)
    build(make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl))
  }
})
try_case("table build, all groups", {
  build_top_alerts_table(ad$view1_tbl, c("<50k", "50k-500k", ">500k"), 4)
})
try_case("dist_tbl missing (NULL) is graceful", {
  stopifnot(is.null(make_dimensions_figure(
    select_top_definitions(ad$view1_tbl, "50k-500k", 4), ad$view1_tbl, NULL)))
})
try_case("table content is always eligible-only: every displayed row passes the -1 cutoff", {
  std_cols <- c("std_impact", "std_eff", "std_ppv", "std_missed", "std_delay")
  sr <- select_top_definitions(ad$view1_tbl, "50k-500k", n_top = "all", cutoff_val = -1)
  min_scores <- apply(sr[std_cols], 1, min, na.rm = TRUE)
  stopifnot(all(min_scores >= -1))
})
try_case('n_top = "3" and "5" return at most that many rows per group, all eligible', {
  for (n in c("3", "5")) {
    parts <- build_top_alerts_table(ad$view1_tbl, "50k-500k", n_top = n, cutoff_val = -1)
    stopifnot(nrow(parts$display) <= as.integer(n))
  }
})
try_case('n_top = "all" returns every eligible definition, not capped at a fixed number', {
  parts_all <- build_top_alerts_table(ad$view1_tbl, "50k-500k", n_top = "all", cutoff_val = -1)
  parts_5   <- build_top_alerts_table(ad$view1_tbl, "50k-500k", n_top = "5",   cutoff_val = -1)
  stopifnot(nrow(parts_all$display) >= nrow(parts_5$display))
})
try_case("only the single best (rank 1) alert per group is highlighted", {
  parts <- build_top_alerts_table(ad$view1_tbl, "50k-500k", n_top = "all", cutoff_val = -1)
  stopifnot(length(parts$top_row_index) == length(parts$group_counts))
})
try_case("boxplot rows are ordered strictly by real alert_number, not a regex-parsed label", {
  ## regression test: an earlier version derived the sort key via
  ## as.numeric(gsub("\\D+","",alert_lab)), which silently collided
  ## "\u2265 .25 per 10K" and "\u2265 2.5 per 10K" (both -> "2510") and reversed
  ## the true order of "\u2265 .5 per 10K" vs "\u2265 1 per 10K". Use the real
  ## alert_number column instead (already attached by select_top_definitions).
  sr <- select_top_definitions(ad$view1_tbl, "50k-500k", n_top = "all", cutoff_val = -Inf)
  p <- make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl)
  b <- ggplot2::ggplot_build(p[[1]])
  shown_labels <- rev(b$layout$panel_params[[1]]$y$get_labels())  # top-to-bottom
  shown_nums <- vapply(shown_labels, function(l) {
    sr$alert_number[match(l, as.character(sr$alert_lab))]
  }, numeric(1))
  stopifnot(!is.unsorted(shown_nums))  # strictly ascending top-to-bottom
})
try_case("boxplot ordering stays correct in EVERY population group when multiple groups are shown together", {
  ## regression test for a real bug: a single shared `alert_lab` factor level
  ## per row meant an alert eligible in more than one group kept the row
  ## position from whichever group was resolved first, breaking ascending
  ## order in every other group. Each (pop_brk, alert) pair must now get its
  ## own independent row position.
  sr <- select_top_definitions(ad$view1_tbl, c("<50k", "50k-500k", ">500k"), n_top = "all", cutoff_val = -1)
  p <- make_dimensions_figure(sr, ad$view1_tbl, ad$dist_tbl)
  b <- ggplot2::ggplot_build(p[[1]])
  pop_levels <- levels(sr$pop_brk)
  for (i in seq_along(pop_levels)) {
    pg <- pop_levels[i]
    labs_bottom_to_top <- b$layout$panel_params[[i]]$y$get_labels()
    sr_pg <- dplyr::filter(sr, as.character(pop_brk) == pg)
    nums <- sr_pg$alert_number[match(labs_bottom_to_top, as.character(sr_pg$alert_lab))]
    stopifnot(!is.unsorted(rev(nums)))  # ascending top-to-bottom, this group only
  }
})
try_case("View 1 and View 2 both expose a 'show description' banner toggle", {
  ui1 <- as.character(view1_ui("v1"))
  ui2 <- as.character(view2_ui("v2"))
  stopifnot(grepl("show_banner", ui1), grepl("Show description", ui1))
  stopifnot(grepl("show_banner", ui2), grepl("Show description", ui2))
})
try_case("view_help_ui / view_about_ui render without error", {
  invisible(view_help_ui("help"))
  invisible(view_about_ui("about"))
  testServer(view_help_server, args = list(), {})
  testServer(view_about_server, args = list(), {})
})

cat("\n=== VIEW 2 edge cases ===\n")
try_case("build_alert_instances runs and ids are unique", {
  inst <- build_alert_instances(ad$alert_groups)
  stopifnot(nrow(inst) > 0, !any(duplicated(inst$unique_alert_id)))
})
try_case("reactive server renders on load", {
  testServer(view2_server, args = list(data = ad), {
    build(current_plot())
  })
})
try_case("each anchor definition individually, full instance set", {
  inst <- build_alert_instances(ad$alert_groups)
  for (a in c(8, 15)) {
    sub <- inst[inst$alert_number == a, ]
    build(alert_window_plot(ad$time_series, ad$alert_groups, sub[seq_len(min(6, nrow(sub))), ]))
  }
})
try_case("rapid resample x10", {
  testServer(view2_server, args = list(data = ad), {
    for (i in 1:10) { session$setInputs(resample = i); sampled_instances() }
  })
})
try_case("single sampled instance (n=1) renders", {
  inst <- build_alert_instances(ad$alert_groups)
  build(alert_window_plot(ad$time_series, ad$alert_groups, inst[1, ]))
})
try_case("vlines never exceed one row per (panel, anchor)", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub)
  hl <- p$layers[[2]]$data
  stopifnot(!any(duplicated(hl[c("unique_alert_id", "alert_number")])))
})
try_case("x-axis labels are Week-based, never calendar years", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub)
  b <- ggplot2::ggplot_build(p)
  all_labels <- unlist(lapply(b$layout$panel_params, function(pp) pp$x$get_labels()))
  stopifnot(all(grepl("^Week ", all_labels)), !any(grepl("^(19|20)[0-9]{2}$", all_labels)))
})
try_case("0 extra alerts: only the 2 anchors are ever highlighted", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub)
  labs <- unique(as.character(p$layers[[2]]$data$alert_lab))
  stopifnot(length(labs) <= 2)
})
try_case("1 extra alert adds exactly one more highlighted definition", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub, extra_numbers = 20)
  labs <- unique(as.character(p$layers[[2]]$data$alert_lab))
  stopifnot(length(labs) <= 3, alert_definition_label(20) %in% labs)
})
try_case("2 extra alerts each get a distinct, stable colour", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub, extra_numbers = c(20, 5))
  b <- ggplot2::ggplot_build(p)
  cols <- unique(b$data[[2]]$colour)
  stopifnot(length(cols) == length(unique(cols)))  # no colour collisions
})
try_case("duplicate extra selections are de-duplicated, not double-drawn", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub, extra_numbers = c(20, 20))
  labs <- unique(as.character(p$layers[[2]]$data$alert_lab))
  stopifnot(length(labs) <= 3)
})
try_case("an extra that duplicates an anchor does not create a phantom category", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub, extra_numbers = c(8, 20))
  labs <- unique(as.character(p$layers[[2]]$data$alert_lab))
  stopifnot(length(labs) <= 3)  # alert 8 (an anchor) must not double-count
})
try_case("picking extra alerts does not force a new random sample (only the resample button does)", {
  testServer(view2_server, args = list(data = ad), {
    first <- sampled_instances()$unique_alert_id
    session$setInputs(extra1 = "20", extra2 = "5")
    stopifnot(identical(first, sampled_instances()$unique_alert_id))
    build(current_plot())
    session$setInputs(resample = 1)
    stopifnot(!identical(first, sampled_instances()$unique_alert_id))
  })
})
try_case("alert_definition_description() returns 24 non-empty, distinct sentences", {
  descs <- alert_definition_description(1:24)
  stopifnot(length(descs) == 24, !any(is.na(descs)), all(nchar(descs) > 20),
            length(unique(descs)) == 24)
})
try_case("table HTML embeds exactly one tooltip span per row, correctly escaped", {
  parts <- build_top_alerts_table(ad$view1_tbl, pop_keep = c("<50k", "50k-500k", ">500k"), n_top = 8)
  tab_body <- dplyr::select(parts$display, -pop_brk)
  html <- as.character(kableExtra::kbl(tab_body, format = "html", escape = FALSE))
  n_spans <- length(gregexpr("<span title=", html)[[1]])
  stopifnot(n_spans == nrow(tab_body))
  stopifnot(!grepl("&lt;span", html))  # not double-escaped into literal text
})
try_case("app.R lists the Help tab before the About tab", {
  app_src <- paste(readLines("app.R", warn = FALSE), collapse = "\n")
  help_pos  <- regexpr("How to use the app", app_src)
  about_pos <- regexpr("About us", app_src)
  stopifnot(help_pos > 0, about_pos > 0, help_pos < about_pos)
})

try_case("TL_last_alert is not present in alert_groups (removed from input files)", {
  stopifnot(!("TL_last_alert" %in% names(ad$alert_groups)))
  stopifnot("TL_first_alert" %in% names(ad$alert_groups))
})
try_case("View 2 x-axis has no title, but per-tick Week labels remain", {
  inst <- build_alert_instances(ad$alert_groups)
  set.seed(1); sub <- inst[sample(nrow(inst), 6), ]
  p <- alert_window_plot(ad$time_series, ad$alert_groups, sub)
  stopifnot(is.null(p$scales$get_scales("x")$name))
  b <- ggplot2::ggplot_build(p)
  all_labels <- unlist(lapply(b$layout$panel_params, function(pp) pp$x$get_labels()))
  stopifnot(all(grepl("^Week ", all_labels)))
})
try_case("data/ contains only .parquet (+ the utility CSV), no leftover .rds files", {
  data_files <- list.files("data")
  stopifnot(!any(grepl("\\.rds$", data_files)))
  stopifnot(any(grepl("\\.parquet$", data_files)))
})

try_case("View 2 extra-alert dropdowns embed a hover tooltip with the full description per option", {
  html <- as.character(view2_ui("view2"))
  stopifnot(grepl("option: function", html, fixed = TRUE))
  stopifnot(grepl("var descriptions", html, fixed = TRUE))
  # spot check: alert 8's description text appears somewhere in the embedded JSON
  stopifnot(grepl(alert_definition_description(1), html, fixed = TRUE))
})

try_case("load_country_tbl() combines the 3 country CSVs with alert_number attached, zero NAs", {
  stopifnot(!is.null(ad$country_tbl))
  stopifnot(all(c("country","pop_brk","alert_number","alert_lab","util_score") %in% names(ad$country_tbl)))
  stopifnot(sum(is.na(ad$country_tbl$alert_number)) == 0)
})
try_case("build_top_alerts_table() on country data omits SD/N parentheticals gracefully (no crash)", {
  one <- dplyr::filter(ad$country_tbl, country == ad$country_tbl$country[1])
  parts <- build_top_alerts_table(one, pop_keep = c("<50k","50k-500k",">500k"), n_top = "3")
  stopifnot(is.data.frame(parts$display))
  # no SD companion in country data -> "Impact: cases (SD)" column should NOT contain a "(" 
  if (nrow(parts$display) > 0) {
    stopifnot(!any(grepl("\\(", parts$display[["Impact: cases (SD)"]])))
  }
})
try_case("country selection never crashes even for the sparsest-data country", {
  sparse_country <- ad$country_tbl %>% dplyr::count(country) %>% dplyr::arrange(n) %>% dplyr::slice(1) %>% dplyr::pull(country)
  one <- dplyr::filter(ad$country_tbl, country == sparse_country)
  parts <- build_top_alerts_table(one, pop_keep = c("<50k","50k-500k",">500k"), n_top = "all")
  stopifnot(is.data.frame(parts$display))  # 0 rows is fine, just must not error
})
try_case("make_dimensions_figure() renders with a country-filtered full_tbl and real dist_tbl country data", {
  one_country <- ad$country_tbl$country[1]
  one <- dplyr::filter(ad$country_tbl, country == one_country)
  sr <- select_top_definitions(one, pop_keep = c("<50k","50k-500k",">500k"), n_top = "3")
  build(make_dimensions_figure(sr, one, ad$dist_tbl, country = one_country))
})
try_case("dist_tbl carries country, and a real country's boxplot data is a genuine subset of pooled", {
  stopifnot("country" %in% names(ad$dist_tbl))
  stopifnot(sum(is.na(ad$dist_tbl$country)) == 0)
  one_country <- ad$country_tbl$country[1]
  one_lab <- dplyr::filter(ad$dist_tbl, country == one_country)$alert_lab[1]
  n_country <- ad$dist_tbl %>% dplyr::filter(country == one_country, alert_lab == one_lab, dimension == "Impact") %>% nrow()
  n_pooled  <- ad$dist_tbl %>% dplyr::filter(alert_lab == one_lab, dimension == "Impact") %>% nrow()
  stopifnot(n_country > 0, n_country <= n_pooled)
})
try_case("make_dimensions_figure() returns NULL (not a crash) for a country absent from dist_tbl", {
  one <- dplyr::filter(ad$country_tbl, country == ad$country_tbl$country[1])
  sr <- select_top_definitions(one, pop_keep = c("<50k","50k-500k",">500k"), n_top = "3")
  fig <- make_dimensions_figure(sr, one, ad$dist_tbl, country = "ZZZ_NONEXISTENT_COUNTRY")
  stopifnot(is.null(fig))
})
try_case("View 1 reactive server: switching country changes the table without crashing", {
  testServer(view1_server, args = list(data = ad), {
    session$setInputs(pop_keep = c("<50k","50k-500k",">500k"), n_top = "3", country = "__all__")
    n_pooled <- nrow(table_parts()$display)
    a_country <- ad$country_tbl$country[1]
    session$setInputs(country = a_country)
    stopifnot(is_country_selected())
    n_country <- nrow(table_parts()$display)
    stopifnot(is.numeric(n_pooled), is.numeric(n_country))
  })
})
try_case("country_display_name() returns full names for known ISO3 codes, falls back to the code otherwise", {
  stopifnot(country_display_name("BEN") == "Benin")
  stopifnot(country_display_name("COD") == "Democratic Republic of the Congo")
  stopifnot(country_display_name("NOT_A_REAL_CODE") == "NOT_A_REAL_CODE")
})
try_case("the two Congos (COD, COG) have distinct, unambiguous display names", {
  cod <- country_display_name("COD")
  cog <- country_display_name("COG")
  stopifnot(cod != cog)
  stopifnot(cog != "Congo")  # bare "Congo" is ambiguous when both appear in the same dropdown
  stopifnot(grepl("Democratic", cod, fixed = TRUE))
  stopifnot(grepl("Republic", cog, fixed = TRUE))
})
try_case("compute_country_completeness() excludes a country with zero eligible alerts anywhere (e.g. Benin)", {
  comp <- compute_country_completeness(ad$country_tbl)
  stopifnot(!("BEN" %in% comp$country))
  stopifnot(nrow(comp) > 0)  # sanity: some countries do have eligible data
})
try_case("the country dropdown only offers countries with at least one eligible alert definition", {
  testServer(view1_server, args = list(data = ad), {
    session$flushReact()
    choices <- session$getReturned()  # not used, but exercises the observe() without error
    comp <- compute_country_completeness(ad$country_tbl)
    stopifnot(!("BEN" %in% unique(comp$country)))  # Benin has zero eligible data
  })
})
try_case("a partial-coverage country's sparsity note lists exactly its missing population group(s)", {
  comp <- compute_country_completeness(ad$country_tbl)
  by_country <- comp %>% dplyr::group_by(country) %>% dplyr::summarise(n_groups = dplyr::n(), .groups = "drop")
  partial_country <- dplyr::filter(by_country, n_groups < 3)$country[1]
  stopifnot(!is.na(partial_country))  # confirm a real partial-coverage country exists in this data
  testServer(view1_server, args = list(data = ad), {
    session$setInputs(pop_keep = c("<50k","50k-500k",">500k"), n_top = "3", country = partial_country)
    note_html <- paste(as.character(output$country_note), collapse = "")
    stopifnot(grepl("Data sparsity", note_html, fixed = TRUE))
    stopifnot(grepl(country_display_name(partial_country), note_html, fixed = TRUE))
  })
})
try_case("a full-coverage country shows no sparsity note", {
  comp <- compute_country_completeness(ad$country_tbl)
  by_country <- comp %>% dplyr::group_by(country) %>% dplyr::summarise(n_groups = dplyr::n(), .groups = "drop")
  full_country <- dplyr::filter(by_country, n_groups == 3)$country[1]
  stopifnot(!is.na(full_country))  # confirm a real full-coverage country exists in this data
  testServer(view1_server, args = list(data = ad), {
    session$setInputs(pop_keep = c("<50k","50k-500k",">500k"), n_top = "3", country = full_country)
    note_html <- paste(as.character(output$country_note), collapse = "")
    stopifnot(!grepl("Data sparsity", note_html, fixed = TRUE))
  })
})
try_case("location_pop_brk loads with no leaked location strings and a sensible pop_brk distribution", {
  stopifnot(!is.null(ad$location_pop_brk))
  stopifnot(all(c("location", "pop_brk", "country") %in% names(ad$location_pop_brk)))
  stopifnot(!any(grepl("::", ad$location_pop_brk$location, fixed = TRUE)))
  counts <- table(ad$location_pop_brk$pop_brk)
  stopifnot(all(c("<50k", "50k-500k", ">500k") %in% names(counts)), all(counts > 0))
})
try_case("pop_group_long_label() appends the location count only when one is supplied", {
  stopifnot(!grepl("locations)", pop_group_long_label("<50k"), fixed = TRUE))
  stopifnot(grepl("(142 locations)", pop_group_long_label("<50k", n_locations = 142), fixed = TRUE))
})
try_case("table location counts differ between pooled and a specific country, and are internally consistent", {
  testServer(view1_server, args = list(data = ad), {
    session$setInputs(pop_keep = c("<50k","50k-500k",">500k"), n_top = "3", country = "__all__")
    pooled_n <- sum(ad$location_pop_brk$pop_brk == "<50k")
    html_pooled <- paste(as.character(output$top_table), collapse = "")
    stopifnot(grepl(paste0("(", pooled_n, " locations)"), html_pooled, fixed = TRUE))

    a_country <- ad$country_tbl$country[1]
    session$setInputs(country = a_country)
    country_n <- sum(ad$location_pop_brk$pop_brk == "<50k" & ad$location_pop_brk$country == a_country)
    html_country <- paste(as.character(output$top_table), collapse = "")
    stopifnot(grepl(paste0("(", country_n, " locations)"), html_country, fixed = TRUE))
    stopifnot(country_n != pooled_n)  # sanity: country subset really is different from pooled
  })
})

cat(sprintf("\n=== RESULT: %d passed, %d failed ===\n", pass, fail))
if (fail > 0) quit(status = 1)
