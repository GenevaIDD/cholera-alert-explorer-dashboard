## ---------------------------------------------------------------------------
## utility_calc.R
## Helpers for View 1. The utility metrics themselves are NOT computed here -
## they are precomputed in alert_utility_score.qmd and loaded from
## data/complete_utility_data_mean_sd.csv. This file only provides:
##   - the alert-definition label lookups (ported from OutbreakExtractR), and
##   - the formatter that turns the precomputed table into the top-N display
##     table for a chosen set of population groups.
## ---------------------------------------------------------------------------

#' label_alerts_long
#'
#' Adds descriptive labels to alert numbers. Ported from OutbreakExtractR.
#'
#' @param basedf a data frame with an `alert_number` column
#' @param is_ordered logical (default FALSE); whether the factor is ordered
#' @return the data frame with an added `alert_lab` factor column
label_alerts_long <- function(basedf, is_ordered = FALSE) {
  dplyr::mutate(basedf, alert_lab = factor(
    alert_number, levels = 1:24,
    labels = c(
      "1 week trend", "2 week trend", "3 week trend",
      "\U2265 2 weekly cases", "\U2265 5 weekly cases", "\U2265 10 weekly cases",
      "\U2265 25 weekly cases", "\U2265 50 weekly cases", "\U2265 100 weekly cases",
      "\U2265 250 weekly cases",
      "\U2265 5 cum cases", "\U2265 10 cum cases", "\U2265 25 cum cases",
      "\U2265 50 cum cases", "\U2265 100 cum cases", "\U2265 500 cum cases",
      "\U2265 1000 cum cases",
      "\U2265 .25 per 10K pop", "\U2265 .5 per 10K pop", "\U2265 1 per 10K pop",
      "\U2265 1.5 per 10K pop", "\U2265 2.5 per 10K pop", "\U2265 5 per 10K pop",
      "\U2265 7.5 per 10K pop"
    ),
    ordered = is_ordered
  ))
}

#' label_alerts_short
#'
#' Adds short descriptive labels to alert numbers. Ported from OutbreakExtractR.
#'
#' @param basedf a data frame with an `alert_number` column
#' @param is_ordered logical (default FALSE); whether the factor is ordered
#' @return the data frame with an added `alert_lab` factor column
label_alerts_short <- function(basedf, is_ordered = FALSE) {
  dplyr::mutate(basedf, alert_lab = factor(
    alert_number, levels = 1:24,
    labels = c(
      paste0(c("1", "2", "3"), "-week"),
      paste(c("\U2265 2", "\U2265 5", "\U2265 10", "\U2265 25", "\U2265 50", "\U2265 100", "\U2265 250"), "weekly"),
      paste(c("\U2265 5", "\U2265 10", "\U2265 25", "\U2265 50", "\U2265 100", "\U2265 500", "\U2265 1000"), "total"),
      paste(c("\U2265 .25", "\U2265 .5", "\U2265 1", "\U2265 1.5", "\U2265 2.5", "\U2265 5", "\U2265 7.5"), "per 10K")
    ),
    ordered = is_ordered
  ))
}

#' Human-readable alert-definition label (short form), using the ported
#' OutbreakExtractR mapping from alert_number to a threshold label. Used only
#' as a fallback when the precomputed table lacks an `alert_lab` column.
alert_definition_label <- function(alert_number) {
  as.character(label_alerts_short(data.frame(alert_number = alert_number))$alert_lab)
}

#' Full descriptive sentence for each alert definition (tooltip content),
#' following the four alert-definition families as described in the
#' manuscript: trend-based, weekly case-based, cumulative case-based, and
#' weekly rate-based alerts. Indexed 1:24, matching label_alerts_short()/
#' label_alerts_long()'s ordering and thresholds exactly.
#'
#' @param alert_number integer vector of alert numbers (1-24)
#' @return character vector of full descriptive sentences
alert_definition_description <- function(alert_number) {
  descriptions <- c(
    ## 1-3: trend-based alerts
    paste0(
      "Trend-based alert: triggered by an upward case trend of ", 1:3,
      ifelse(1:3 == 1, " week", " weeks"),
      " relative to the mean of the previous four weeks."
    ),
    ## 4-10: weekly case-based alerts
    local({
      x <- c(2, 5, 10, 25, 50, 100, 250)
      paste0(
        "Weekly case-based alert: triggered when at least ", x, " suspected ",
        ifelse(x == 1, "case is", "cases are"),
        " observed for three consecutive weeks."
      )
    }),
    ## 11-17: cumulative case-based alerts
    local({
      x <- c(5, 10, 25, 50, 100, 500, 1000)
      paste0(
        "Cumulative case-based alert: triggered when at least ", x, " suspected ",
        ifelse(x == 1, "case is", "cases are"),
        " observed over a three-week period."
      )
    }),
    ## 18-24: weekly rate-based alerts
    local({
      x <- c(.25, .5, 1, 1.5, 2.5, 5, 7.5)
      paste0(
        "Weekly rate-based alert: triggered when at least ", x, " suspected ",
        ifelse(x == 1, "case", "cases"),
        " per 10,000 people ", ifelse(x == 1, "is", "are"),
        " observed for three consecutive weeks."
      )
    })
  )
  descriptions[alert_number]
}

#' Descriptive population-group labels (matching the manuscript table).
pop_group_long_label <- function(pop_brk) {
  dplyr::case_when(
    pop_brk == "<50k"     ~ "Administrative units with <50,000 people",
    pop_brk == "50k-500k" ~ "Administrative units with 50,000 to 500,000 people",
    pop_brk == ">500k"    ~ "Administrative units with \u2265500,000 people",
    TRUE ~ as.character(pop_brk)
  )
}

#' Look up alert_number for rows that only carry alert_lab (e.g. the CSV),
#' by matching against the OutbreakExtractR short labels.
add_alert_number <- function(df) {
  if ("alert_number" %in% names(df)) return(df)
  lut <- label_alerts_short(data.frame(alert_number = 1:24)) %>%
    dplyr::transmute(alert_number, alert_lab = as.character(alert_lab))
  dplyr::left_join(df, lut, by = "alert_lab")
}

#' Select the top-N alert definitions per population group from the
#' precomputed table, applying the manuscript's min-dimension exclusion.
#' Returns the raw (unformatted) rows, ordered by pop group then utility.
#'
#' @param n_top a positive integer, or the string "all" to return every
#'   eligible definition per population group (no cap)
#' @inheritParams build_top_alerts_table
#' @return a data frame of the selected rows with pop_brk as an ordered factor
select_top_definitions <- function(view1_tbl, pop_keep, n_top = 4, cutoff_val = -1) {

  pop_order_codes <- c("<50k", "50k-500k", ">500k")
  pop_keep <- pop_order_codes[pop_order_codes %in% pop_keep]

  df <- view1_tbl
  if (!"alert_lab" %in% names(df)) df$alert_lab <- alert_definition_label(df$alert_number)
  df <- add_alert_number(df)

  ## manuscript min_score >= cutoff exclusion (weakest std dimension) -
  ## always applied (cutoff_val defaults to -1); pass -Inf to disable
  std_cols <- intersect(
    c("std_impact", "std_eff", "std_ppv", "std_missed", "std_delay"), names(df)
  )
  if (length(std_cols) > 0 && is.finite(cutoff_val)) {
    df <- df %>%
      dplyr::rowwise() %>%
      dplyr::mutate(min_score = min(dplyr::c_across(dplyr::all_of(std_cols)), na.rm = TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::filter(min_score >= cutoff_val)
  }

  out <- df %>%
    dplyr::filter(pop_brk %in% pop_keep, !is.na(util_score)) %>%
    dplyr::mutate(pop_brk = factor(pop_brk, levels = pop_keep)) %>%
    dplyr::group_by(pop_brk) %>%
    dplyr::arrange(dplyr::desc(util_score), .by_group = TRUE)

  if (!identical(n_top, "all")) {
    out <- dplyr::slice_head(out, n = as.integer(n_top))
  }

  out %>%
    dplyr::ungroup() %>%
    dplyr::arrange(pop_brk, dplyr::desc(util_score))
}

#' Build the top-N-by-utility-score display table for the selected population
#' groups from the precomputed View 1 table (no calculations - just filter,
#' rank, slice and format).
#'
#' The table always shows the top N definitions by utility score per
#' population group, regardless of the manuscript's -1 min-dimension cutoff
#' (so exactly N rows are shown whenever N definitions exist). Separately,
#' any definition among those N whose weakest standardised dimension is at or
#' above `cutoff_val` is flagged for highlighting (bold + shaded) - so
#' highlighting shows which of the displayed alerts are also "valid" per the
#' manuscript's rule, rather than excluding invalid ones from the table.
#'
#' @param view1_tbl the precomputed per-definition utility table (loaded from
#'   complete_utility_data_mean_sd.csv). Expected columns: pop_brk, alert_lab,
#'   alert_type, impact_mean, sd_impact, eff_mean, sd_eff, ppv, n_alerts,
#'   missed_prop, n_outbreaks, delay_mean, sd_delay, util_score and the five
#'   std_* dimension columns.
#' @param pop_keep character vector of pop_brk codes to include
#' @param n_top a positive integer (e.g. 3 or 5), or "all" to show every
#'   eligible alert definition per population group
#' @param cutoff_val minimum-dimension cutoff (default -1, as selected in the
#'   manuscript). Only definitions passing this cutoff are ever shown - the
#'   table no longer displays ineligible rows at all.
#' @return a list with `display` (formatted, ready to render), `pop_keep`
#'   (only the groups that actually have rows, in display order),
#'   `group_counts` and `top_row_index` (1-based row number of the best
#'   (rank 1) alert per group, for highlighting)
build_top_alerts_table <- function(view1_tbl, pop_keep, n_top = 4, cutoff_val = -1) {

  pop_order_codes <- c("<50k", "50k-500k", ">500k")
  pop_keep <- pop_order_codes[pop_order_codes %in% pop_keep]

  has_missed <- "missed_prop" %in% names(view1_tbl)
  has_delay  <- "delay_mean"  %in% names(view1_tbl)

  ## every row returned is already eligible (passes the -1 cutoff) and
  ## already within the requested top N (or "all" eligible) per group
  combined <- select_top_definitions(
    view1_tbl, pop_keep = pop_keep, n_top = n_top, cutoff_val = cutoff_val
  )

  display <- combined %>%
    dplyr::mutate(
      .alert_def_html = paste0(
        '<span title="',
        gsub('"', "&quot;", alert_definition_description(alert_number), fixed = TRUE),
        '" style="border-bottom: 1px dotted #666; cursor: help;">',
        as.character(alert_lab),
        "</span>"
      )
    ) %>%
    dplyr::transmute(
      pop_brk,
      `Alert Definition` = .alert_def_html,
      `Alert Type`       = tools::toTitleCase(alert_type),
      `Impact: cases (SD)` = paste0(round(impact_mean, 1), " (", round(sd_impact, 1), ")"),
      `Efficiency: cases per 1000 pop (SD)` = paste0(round(eff_mean, 2), " (", round(sd_eff, 2), ")"),
      `PPV: proportion (N alerts)` = paste0(round(ppv, 2), " (", n_alerts, ")"),
      `Missed: proportion (N outbreaks)` = if (has_missed) {
        paste0(round(missed_prop, 2), " (", n_outbreaks, ")")
      } else "n/a",
      `Timeliness: weeks from outbreak start (SD)` = if (has_delay) {
        ifelse(is.na(delay_mean), "n/a",
               paste0(round(delay_mean, 1), " (", round(sd_delay, 1), ")"))
      } else "n/a",
      `Utility Score` = round(util_score, 2)
    )

  ## keep only population groups that actually have rows, in display order,
  ## so the grouped-row labels stay aligned with their counts
  counts_all <- table(factor(display$pop_brk, levels = pop_keep))
  present <- names(counts_all)[counts_all > 0]
  group_counts <- as.integer(counts_all[present])

  ## highlight only the single best (rank 1) alert per group - every row
  ## shown is already eligible, so highlighting all of them would be
  ## redundant; this instead draws attention to the top pick
  top_row_index <- if (length(group_counts) > 0) {
    cumsum(c(1, utils::head(group_counts, -1)))
  } else {
    integer(0)
  }

  list(
    display = display,
    pop_keep = present,
    group_counts = group_counts,
    top_row_index = top_row_index
  )
}

#' Colour palette for alert types (matching the manuscript's Figure 2).
alert_type_palette <- function() {
  c("trend"    = "#1B9E77",
    "case"     = "#D95F02",
    "cum case" = "#7570B3",
    "cumsum"   = "#7570B3",
    "rate"     = "#E7298A")
}


make_dimensions_figure <- function(selected_rows, full_tbl, dist_tbl) {
  
  if (is.null(selected_rows) || nrow(selected_rows) == 0) return(NULL)
  if (is.null(dist_tbl)) return(NULL)
  
  pops <- levels(selected_rows$pop_brk)
  pops <- pops[pops %in% unique(as.character(selected_rows$pop_brk))]
  
  pop_labeller <- c(
    "<50k" = "<50k",
    "50k-500k" = "50k\u2013500k",
    ">500k" = "\u2265500k"
  )
  
  ## ------------------------------------------------------------------
  ## Order alerts by alert_number, independently within each population
  ## group. selected_rows already carries a correct alert_number column
  ## (attached upstream by select_top_definitions() -> add_alert_number()).
  ##
  ## A single shared factor for `alert_lab` cannot correctly order every
  ## group at once: when the same alert definition is eligible in more than
  ## one group (common), it would occupy one shared row position across all
  ## facets, dragging that alert - and everything sorted relative to it - out
  ## of order in every group except whichever was resolved first. Instead we
  ## key each row on (pop_brk, alert_lab), so every group gets its own
  ## independent, correctly-ordered set of row positions, and map the keys
  ## back to plain alert-definition text only for display.
  ## ------------------------------------------------------------------

  row_key_of <- function(pop_brk, alert_lab) paste(pop_brk, alert_lab, sep = "\u241F")

  key_order <- selected_rows %>%
    dplyr::distinct(pop_brk, alert_lab, alert_number) %>%
    dplyr::arrange(pop_brk, alert_number) %>%
    dplyr::mutate(row_key = row_key_of(pop_brk, alert_lab))

  row_key_levels <- rev(key_order$row_key)
  row_key_labels <- stats::setNames(as.character(key_order$alert_lab), key_order$row_key)

  sel_keys <- selected_rows %>%
    dplyr::distinct(
      pop_brk = as.character(pop_brk),
      alert_lab = as.character(alert_lab)
    )

  d <- dist_tbl %>%
    dplyr::semi_join(sel_keys, by = c("pop_brk", "alert_lab")) %>%
    dplyr::mutate(
      pop_brk    = factor(pop_brk, levels = pops),
      row_key    = factor(row_key_of(pop_brk, alert_lab), levels = row_key_levels),
      alert_type = as.character(alert_type)
    )

  bars <- selected_rows %>%
    dplyr::transmute(
      pop_brk    = factor(as.character(pop_brk), levels = pops),
      row_key    = factor(row_key_of(as.character(pop_brk), as.character(alert_lab)), levels = row_key_levels),
      alert_type = as.character(alert_type),
      ppv, missed_prop
    )
  
  refs <- full_tbl %>%
    dplyr::filter(pop_brk %in% pops) %>%
    dplyr::group_by(pop_brk) %>%
    dplyr::summarise(
      Impact = stats::median(impact_mean, na.rm = TRUE),
      Efficiency = stats::median(eff_mean, na.rm = TRUE),
      PPV = stats::median(ppv, na.rm = TRUE),
      Missed = stats::median(missed_prop, na.rm = TRUE),
      Timeliness = stats::median(delay_mean, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(pop_brk = factor(as.character(pop_brk), levels = pops))
  
  pal <- alert_type_palette()
  
  cap <- function(dim, p) {
    v <- d$value[d$dimension == dim]
    if (!length(v)) return(NA_real_)
    as.numeric(stats::quantile(v, p, na.rm = TRUE))
  }
  
  box_panel <- function(dim, title_lab, x_lab, xlim, show_y, show_legend = FALSE) {
    
    dd <- dplyr::filter(d, dimension == dim)
    
    rf <- dplyr::transmute(
      refs,
      pop_brk,
      xintercept = .data[[dim]]
    )
    
    ggplot2::ggplot(dd, ggplot2::aes(x = value, y = row_key)) +
      ggplot2::geom_vline(
        data = rf,
        ggplot2::aes(xintercept = xintercept),
        linetype = "dashed",
        colour = "grey40",
        linewidth = 0.4
      ) +
      ggplot2::geom_boxplot(
        ggplot2::aes(fill = alert_type),
        colour = "grey25",
        linewidth = 0.3,
        outlier.shape = 1,
        outlier.size = 0.5,
        outlier.alpha = 0.3
      ) +
      ggplot2::stat_summary(
        fun = mean,
        geom = "point",
        size = 1.7,
        colour = "black"
      ) +
      ggplot2::facet_grid(
        pop_brk ~ .,
        scales = "free_y",
        space = "free_y",
        labeller = ggplot2::labeller(pop_brk = pop_labeller)
      ) +
      ggplot2::scale_y_discrete(drop = TRUE, labels = row_key_labels) +
      ggplot2::scale_fill_manual(
        values = pal,
        name = "Alert type",
        guide = if (show_legend) "legend" else "none"
      ) +
      ggplot2::coord_cartesian(xlim = xlim) +
      ggplot2::labs(x = x_lab, y = NULL, title = title_lab) +
      ggplot2::theme_bw(base_size = 11) +
      ggplot2::theme(
        panel.grid.minor = ggplot2::element_blank(),
        strip.text.y = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
        legend.position = if (show_legend) "bottom" else "none",
        axis.text.y = if (show_y) ggplot2::element_text() else ggplot2::element_blank(),
        axis.ticks.y = if (show_y) ggplot2::element_blank() else ggplot2::element_blank()
      )
  }
  
  bar_panel <- function(value_col, ref_col, title_lab, x_lab, show_strip) {
    
    rf <- dplyr::transmute(
      refs,
      pop_brk,
      xintercept = .data[[ref_col]]
    )
    
    ggplot2::ggplot(
      bars,
      ggplot2::aes(x = .data[[value_col]], y = row_key, fill = alert_type)
    ) +
      ggplot2::geom_vline(
        data = rf,
        ggplot2::aes(xintercept = xintercept),
        linetype = "dashed",
        colour = "grey40",
        linewidth = 0.4
      ) +
      ggplot2::geom_col() +
      ggplot2::facet_grid(
        pop_brk ~ .,
        scales = "free_y",
        space = "free_y",
        labeller = ggplot2::labeller(pop_brk = pop_labeller)
      ) +
      ggplot2::scale_y_discrete(drop = TRUE, labels = row_key_labels) +
      ggplot2::scale_fill_manual(values = pal, guide = "none") +
      ggplot2::scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
      ggplot2::labs(x = x_lab, y = NULL, title = title_lab) +
      ggplot2::theme_bw(base_size = 11) +
      ggplot2::theme(
        panel.grid.minor = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
        axis.text.y = ggplot2::element_blank(),
        axis.ticks.y = ggplot2::element_blank(),
        strip.text.y = if (show_strip)
          ggplot2::element_text(angle = 0)
        else
          ggplot2::element_blank()
      )
  }
  
  imp_hi <- cap("Impact", 0.95); if (!is.finite(imp_hi) || imp_hi <= 0) imp_hi <- 1
  eff_hi <- cap("Efficiency", 0.95); if (!is.finite(eff_hi) || eff_hi <= 0) eff_hi <- 1
  dly_lo <- cap("Timeliness", 0.02); dly_hi <- cap("Timeliness", 0.98)
  if (!is.finite(dly_lo)) dly_lo <- -5
  if (!is.finite(dly_hi)) dly_hi <- 10
  
  p_imp <- box_panel("Impact", "Impact", "Suspected cases", c(0, imp_hi), show_y = TRUE, show_legend = TRUE)
  p_eff <- box_panel("Efficiency", "Efficiency", "Cases/1k pop", c(0, eff_hi), show_y = FALSE)
  p_ppv <- bar_panel("ppv", "PPV", "PPV", "PPV", show_strip = FALSE)
  p_mis <- bar_panel("missed_prop", "Missed", "Missed", "Prop. of outbreaks", show_strip = FALSE)
  p_dly <- box_panel("Timeliness", "Timeliness", "Weeks of delay",
                     c(dly_lo, dly_hi),
                     show_y = FALSE, show_legend = FALSE) +
    ggplot2::theme(strip.text.y = ggplot2::element_text(angle = 0))
  
  patchwork::wrap_plots(
    p_imp, p_eff, p_ppv, p_mis, p_dly,
    nrow = 1,
    widths = c(1.5, 1.15, 0.8, 0.85, 1.2),
    guides = "collect"
  ) +
    patchwork::plot_annotation(
      caption = paste(
        "Boxplots: distribution across alert evaluations (Impact, Efficiency)",
        "or linked outbreaks (Timeliness); black dot = mean.",
        "Bars: PPV and Missed (proportion). Dashed line: median across",
        "definitions. x-axes clipped for readability."
      ),
      theme = ggplot2::theme(
        legend.position = "bottom",
        plot.caption = ggplot2::element_text(hjust = 0, colour = "grey30")
      )
    )
}
