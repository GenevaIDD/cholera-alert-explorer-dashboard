## ---------------------------------------------------------------------------
## view2_timeseries.R
## "Alert window explorer" (anonymised): each panel is one randomly sampled
## *alert instance* - a unique (location, alert_number, TL_first_alert)
## combination for one of the two "anchor" definitions, >= 50 weekly (alert
## 8) or >= 100 total (alert 15). These anchors define the sampled instance
## and the displayed time window: 4 weeks before the anchor's first-alert
## week through 56 weeks after it.
##
## The user may additionally pick up to two more alert definitions to
## highlight in the same panels (their own first-alert weeks, wherever they
## fall inside the fixed window) - the window itself is always driven only
## by the two anchors, never by the extra picks.
##
## Only a single vertical line marks the first-alert week of each highlighted
## definition (no alert-group duration/span is shown). Panels have no
## titles, no gridlines, and each panel's x-axis is computed and labelled
## independently ("Week 1", "Week 2", ...) rather than sharing one global
## axis. Location is never shown.
## ---------------------------------------------------------------------------

N_SERIES_SHOW  <- 6    ## number of random alert-instance windows to display
WEEKS_BEFORE   <- 4    ## window starts this many weeks before the anchor week
WEEKS_AFTER    <- 56   ## window ends this many weeks after the anchor week
ANCHOR_NUMBERS <- c(8, 15)  ## >= 50 weekly, >= 100 total - always shown, define the window
MAX_EXTRA      <- 2    ## user may add up to this many more definitions to highlight

## four fixed, qualitative, colour-blind-friendly colours (Okabe-Ito): the
## first two are always the anchors; the next two are used for whichever
## extra definitions the user picks, in the order picked (stable per slot,
## not reassigned when the other slot changes)
HIGHLIGHT_COLOURS <- c("#E69F00", "#0072B2", "#009E73", "#CC79A7")

#' Build the table of sampleable "anchor" alert instances: one row per
#' (location, alert_number, TL_first_alert) for the two anchor definitions,
#' with an anonymised unique_alert_id that carries no information about the
#' (already-anonymised) location.
#'
#' @param alert_groups the alert_groups table (location, alert_number,
#'   alert_type, TL_first_alert)
#' @return alert_groups filtered to the anchor definitions, with
#'   unique_alert_id added
build_alert_instances <- function(alert_groups) {
  inst <- alert_groups %>%
    dplyr::filter(alert_number %in% ANCHOR_NUMBERS) %>%
    dplyr::distinct(location, alert_number, TL_first_alert, .keep_all = TRUE) %>%
    dplyr::arrange(location, alert_number, TL_first_alert)

  set.seed(42)  # reproducible shuffle -> ids reveal nothing about order/location
  inst$unique_alert_id <- sample(sprintf("alert-%05d", seq_len(nrow(inst))))
  inst
}

#' Build the anonymised multi-panel window plot: one panel per sampled alert
#' instance, its case-count window, with a single vertical line marking the
#' first-alert week of each highlighted definition (whichever occur in-window
#' at that location) - never the full alert-group duration. The window
#' itself is always defined by the two anchors, regardless of `extra_numbers`.
#'
#' @param time_data time_series (location, TL, sCh)
#' @param group_data alert_groups (location, alert_number, TL_first_alert)
#' @param instances sampled rows of build_alert_instances() (one per panel)
#' @param extra_numbers up to MAX_EXTRA additional alert_number values (other
#'   than the two anchors) to also highlight; duplicates and overlaps with
#'   the anchors are silently de-duplicated
#' @return a ggplot object, or NULL if there is nothing to show
alert_window_plot <- function(time_data, group_data, instances, extra_numbers = integer(0)) {

  if (nrow(instances) == 0) return(NULL)

  panel_levels <- instances$unique_alert_id

  ## anchors first (stable colours 1-2), then extras in the order supplied
  ## (stable colours 3-4); duplicates collapse without disturbing this order
  highlight_numbers <- unique(c(ANCHOR_NUMBERS, extra_numbers))
  highlight_labels  <- alert_definition_label(highlight_numbers)
  palette <- stats::setNames(
    HIGHLIGHT_COLOURS[seq_along(highlight_numbers)],
    highlight_labels
  )

  ## per-panel window bounds, keyed by panel so each panel gets its own dates.
  ## Always driven by the anchor instance itself (TL_first_alert), never by
  ## the extra definitions.
  windows <- instances %>%
    dplyr::transmute(
      unique_alert_id, location,
      window_start = TL_first_alert - WEEKS_BEFORE * 7,
      window_end   = TL_first_alert + WEEKS_AFTER * 7
    )

  ## case-count bars for each panel's window, x expressed as a relative week
  ## index (1 = window_start), so "Week 1" always means the start of that
  ## panel's own window regardless of the real calendar date
  ts <- windows %>%
    dplyr::inner_join(time_data, by = "location", relationship = "many-to-many") %>%
    dplyr::filter(TL >= window_start, TL <= window_end) %>%
    dplyr::mutate(
      week_index = as.numeric(TL - window_start) / 7 + 1,
      unique_alert_id = factor(unique_alert_id, levels = panel_levels)
    )

  ## a single line per highlighted definition per panel: the earliest
  ## occurrence of each highlighted alert_number at that location falling
  ## inside the window. (For the definition that defined the sample, this is
  ## always week WEEKS_BEFORE + 1 by construction; for every other
  ## highlighted definition it may or may not occur in-window.)
  hl <- windows %>%
    dplyr::inner_join(
      dplyr::filter(group_data, alert_number %in% highlight_numbers),
      by = "location", relationship = "many-to-many"
    ) %>%
    dplyr::filter(TL_first_alert >= window_start, TL_first_alert <= window_end) %>%
    dplyr::mutate(week_index = as.numeric(TL_first_alert - window_start) / 7 + 1) %>%
    dplyr::group_by(unique_alert_id, alert_number) %>%
    dplyr::slice_min(week_index, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      unique_alert_id = factor(unique_alert_id, levels = panel_levels),
      alert_lab = factor(alert_definition_label(alert_number), levels = highlight_labels)
    )

  ## geom_vline's legend key glyph renders blank for a highlighted definition
  ## with zero occurrences across all sampled panels (e.g. by chance of the
  ## random draw), even with scale_colour_manual(drop = FALSE) - ggplot needs
  ## at least one data row per level to compute the key glyph, not just a
  ## factor level. Add an invisible phantom row (week_index = NA, so it draws
  ## no line - hence the expected "Removed row(s) containing missing values"
  ## warning) for any highlighted level with no real occurrence, so its
  ## legend swatch always renders in the correct colour.
  missing_labels <- setdiff(highlight_labels, unique(as.character(hl$alert_lab)))
  if (length(missing_labels) > 0) {
    hl <- dplyr::bind_rows(
      hl,
      data.frame(
        unique_alert_id = factor(panel_levels[1], levels = panel_levels),
        week_index = NA_real_,
        alert_lab = factor(missing_labels, levels = highlight_labels)
      )
    )
  }

  ## explicit breaks anchored at week 1 (never "week 0"); with facet
  ## scales = "free", each panel automatically shows only the subset of
  ## these breaks that fall inside its own visible range
  week_breaks <- seq(1, WEEKS_BEFORE + WEEKS_AFTER + 1, by = 10)

  ggplot2::ggplot() +
    ggplot2::geom_col(
      data = ts, ggplot2::aes(x = week_index, y = sCh),
      fill = "grey", width = 1
    ) +
    ggplot2::geom_vline(
      data = hl,
      ggplot2::aes(xintercept = week_index, colour = alert_lab),
      linewidth = 0.6, linetype = "solid"
    ) +
    ggplot2::facet_wrap(ggplot2::vars(unique_alert_id), ncol = 2, scales = "free") +
    ggplot2::scale_colour_manual(values = palette, name = "Alert definition", drop = FALSE) +
    ggplot2::scale_x_continuous(
      name = NULL, breaks = week_breaks, labels = paste("Week", week_breaks)
    ) +
    ggplot2::labs(y = "Suspected cholera cases") +
    ggplot2::theme_bw(base_size = 13) +
    ggplot2::theme(
      legend.position = "top",
      strip.text = ggplot2::element_blank(),
      strip.background = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
}

view2_ui <- function(id) {
  ns <- shiny::NS(id)

  ## dropdown choices for the two "extra" selectors: every definition except
  ## the two fixed anchors, labelled descriptively, keyed by alert_number
  extra_numbers_all <- setdiff(1:24, ANCHOR_NUMBERS)
  extra_choices <- c(
    "(none)" = "none",
    stats::setNames(as.character(extra_numbers_all), alert_definition_label(extra_numbers_all))
  )

  ## full descriptive sentence per dropdown value, for a hover tooltip on
  ## each option - the same text already used as a tooltip on View 1's
  ## table (alert_definition_description(), from utility_calc.R)
  descr_lookup <- c(
    "none" = "No additional alert definition selected.",
    stats::setNames(alert_definition_description(extra_numbers_all), as.character(extra_numbers_all))
  )
  descr_json <- jsonlite::toJSON(as.list(descr_lookup), auto_unbox = TRUE)

  ## selectize render callback: shows each option's full description as a
  ## native browser tooltip (title attribute) when hovering over it in the
  ## open dropdown list, using selectize's own HTML-escaping helper
  tooltip_render_js <- I(sprintf(
    "{
      option: function(item, escape) {
        var descriptions = %s;
        var desc = descriptions[item.value] || '';
        return '<div title=\"' + escape(desc) + '\">' + escape(item.label) + '</div>';
      }
    }",
    descr_json
  ))

  shiny::tagList(

    ## -------------------- DESCRIPTION BANNER (togglable) --------------------
    shiny::checkboxInput(ns("show_banner"), "Show description", value = TRUE),
    shiny::conditionalPanel(
      condition = sprintf("input['%s']", ns("show_banner")),
      shiny::div(
        style = "
          background: #f8f9fa;
          border: 1px solid #e5e5e5;
          padding: 14px 18px;
          border-radius: 6px;
          margin-bottom: 15px;
          font-size: 13px;
          line-height: 1.5;
        ",
        "Visualize a random selection of alerts to see what happens in roughly the 1-month before and the 1-year after an alert is triggered.",
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("N.B. "),
        "Not all selected alert definitions may be triggered in each period.",
        " The time windows for the visualization are fixed to the selection of the top-performing alert definitions."
      )
    ),

    shiny::sidebarLayout(
      shiny::sidebarPanel(
        width = 3,
        shiny::helpText(
          "Each panel is a randomly sampled occurrence of the ",
          shiny::tags$b("\u2265 50 weekly"),
          " or ",
          shiny::tags$b("\u2265 100 total"),
          "alert (the best-performing definitions), showing what happens in the month before and the year after the alert, assuming that action taken after the alert would be delayed by 1 month."
        ),
        shiny::actionButton(
          ns("resample"),
          "Show another random selection",
          icon = shiny::icon("shuffle"),
          width = "100%",
          style = "white-space: normal;"
        ),
        shiny::tags$hr(),
        shiny::helpText(
          "Optionally show up to ", MAX_EXTRA,
          " more definitions in the same panels, wherever they occur inside the fixed window. Hover over a dropdown option to see its full description."
        ),
        shiny::selectizeInput(
          ns("extra1"), "Additional alert definition #1",
          choices = extra_choices, selected = "none",
          options = list(render = tooltip_render_js)
        ),
        shiny::uiOutput(ns("extra1_description")),
        shiny::selectizeInput(
          ns("extra2"), "Additional alert definition #2",
          choices = extra_choices, selected = "none",
          options = list(render = tooltip_render_js)
        ),
        shiny::uiOutput(ns("extra2_description")),
        shiny::tags$hr()
      ),

      shiny::mainPanel(
        width = 9,
        shiny::uiOutput(ns("plot_container"))
      )
    )
  )
}

view2_server <- function(id, data) {
  shiny::moduleServer(id, function(input, output, session) {

    alert_instances <- build_alert_instances(data$alert_groups)

    sampled_instances <- shiny::reactiveVal(NULL)

    draw_sample <- function() {
      n <- min(N_SERIES_SHOW, nrow(alert_instances))
      sampled_instances(alert_instances[sample(nrow(alert_instances), n), ])
    }
    draw_sample()  # initial draw
    shiny::observeEvent(input$resample, draw_sample())

    ## the extra alert numbers the user picked (0, 1 or 2; "none" -> dropped)
    extra_numbers <- shiny::reactive({
      nums <- suppressWarnings(as.numeric(c(input$extra1, input$extra2)))
      nums[!is.na(nums)]
    })

    ## full descriptive sentence shown below each dropdown once a definition
    ## is selected - reuses alert_definition_description() directly, the same
    ## source used for View 1's table tooltips, so the two never diverge
    output$extra1_description <- shiny::renderUI({
      if (is.null(input$extra1) || input$extra1 == "none") return(NULL)
      shiny::helpText(alert_definition_description(as.numeric(input$extra1)))
    })
    output$extra2_description <- shiny::renderUI({
      if (is.null(input$extra2) || input$extra2 == "none") return(NULL)
      shiny::helpText(alert_definition_description(as.numeric(input$extra2)))
    })

    ## changing the extra selections redraws only the highlight overlay -
    ## the randomly sampled panels themselves (and their windows) do not
    ## change, since the anchors alone define the sample and the window
    current_plot <- shiny::reactive({
      shiny::req(sampled_instances())
      alert_window_plot(data$time_series, data$alert_groups, sampled_instances(), extra_numbers())
    })

    plot_height <- shiny::reactive({
      n <- max(nrow(sampled_instances()), 1)
      paste0(max(400, ceiling(n / 2) * 260), "px")
    })

    output$plot_container <- shiny::renderUI({
      shiny::plotOutput(session$ns("window_plot"), height = plot_height())
    })

    output$window_plot <- shiny::renderPlot({
      p <- current_plot()
      shiny::validate(shiny::need(!is.null(p), "Nothing to display."))
      p
    })
  })
}
