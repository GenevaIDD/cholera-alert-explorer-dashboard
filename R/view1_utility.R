## ---------------------------------------------------------------------------
## view1_utility.R
## "Top alerts by utility score": loads the precomputed per-definition utility
## table and shows the top-N alert definitions per population group as (a) a
## grouped table and (b) a Figure-2-style dimension panel restricted to the
## selected alerts. No utility calculations run in the app - it only filters,
## ranks and formats.
##
## A country selector switches between the pooled (all-country) table
## (data/complete_utility_data_mean_sd.csv) and country-specific estimates
## (data/country_utility_*.csv). Selecting a country also filters the
## dimension figure's boxplots to that country's own distributions
## (data/compare_significant_*.parquet), so the table, ranking and figure are
## all consistently country-specific together.
##
## The country tables don't carry the pooled table's SD/N companion columns
## (sd_impact, sd_eff, sd_delay, n_alerts, n_outbreaks) - the table formatter
## shows those in parentheses only when present, and just the mean otherwise.
## ---------------------------------------------------------------------------

## Single source of truth for the five utility-dimension descriptions, used
## both in the description banner and as hover tooltips on the table's
## dimension column headers, so the two can never drift out of sync.
DIMENSION_DESCRIPTIONS <- c(
  "Impact" = "How many suspected cases will occur over the next year?",
  "Efficiency" = "How many suspected cases per target population will occur over the next year?",
  "PPV" = "What proportion of alerts will be followed by a 1-year period with at least 300 suspected cases?",
  "Missed" = "What proportion of outbreaks over 300 cases are missed by this alert?",
  "Timeliness" = paste0(
    "How many weeks before or after the outbreak start is the alert triggered? ",
    "(Negative values indicate the alert was triggered before the official outbreak start.)"
  )
)

#' Wrap header/cell text in a span with a native hover tooltip, matching the
#' dotted-underline style already used for the Alert Definition cells.
dimension_tooltip_html <- function(display_text, description) {
  paste0(
    '<span title="', gsub('"', "&quot;", description, fixed = TRUE), '" ',
    'style="border-bottom: 1px dotted #666; cursor: help;">',
    display_text, "</span>"
  )
}

## sentinel value for the country dropdown's "no specific country" option
POOLED_SENTINEL <- "__all__"

view1_ui <- function(id) {
  ns <- shiny::NS(id)

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
        "Compare top-performing alert definitions and examine what happens in the 1-year period after a cholera surveillance alert is triggered across five dimensions of utility:",
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("Potential impact: "), DIMENSION_DESCRIPTIONS[["Impact"]],
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("Potential efficiency: "), DIMENSION_DESCRIPTIONS[["Efficiency"]],
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("Positive predictive value: "), DIMENSION_DESCRIPTIONS[["PPV"]],
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("Missed outbreaks: "), DIMENSION_DESCRIPTIONS[["Missed"]],
        shiny::tags$br(), shiny::tags$br(),

        shiny::tags$b("Timeliness: "), DIMENSION_DESCRIPTIONS[["Timeliness"]]
      )
    ),

    shiny::sidebarLayout(
      shiny::sidebarPanel(
        width = 3,
        shiny::selectInput(
          ns("country"), "Country",
          choices = c("All countries (pooled)" = POOLED_SENTINEL)
        ),
        shiny::checkboxGroupInput(
          ns("pop_keep"), "Population group",
          choices = c(
            "<50,000"          = "<50k",
            "50,000 - 500,000" = "50k-500k",
            "\u2265500,000"    = ">500k"
          ),
          selected = "50k-500k"
        ),
        shiny::radioButtons(
          ns("n_top"), "Number of alerts to show (per group)",
          choices = c("Top 3" = "3", "Top 5" = "5", "All eligible" = "all"),
          selected = "3"
        ),
        shiny::tags$hr(),
        shiny::uiOutput(ns("param_note")),
        shiny::uiOutput(ns("country_note")),
        shiny::helpText(
          "The utility score is the sum of the standardised dimensions: ",
          "impact, efficiency, PPV, missed outbreaks, and timeliness.",
          "Higher utility scores indicate better performance.",
          "Alert definitions that performed poorly on any dimension were not eligible to be a top alert."
        ),
        shiny::helpText(
          shiny::em("Hover over a dimension's column header in the table for its full description.")
        )
      ),
      shiny::mainPanel(
        width = 9,
        shiny::uiOutput(ns("top_table")),
        shiny::br(),
        shiny::h4("Dimension distributions for the selected alerts"),
        shiny::uiOutput(ns("dimension_plot_container"))
      )
    )
  )
}

view1_server <- function(id, data) {
  shiny::moduleServer(id, function(input, output, session) {

    ## populate the country dropdown once, from whatever countries are
    ## actually present in the country table; degrades to "pooled only" if
    ## data$country_tbl is unavailable (e.g. the CSVs are missing)
    shiny::observe({
      if (is.null(data$country_tbl)) return(NULL)
      country_choices <- sort(unique(data$country_tbl$country))
      shiny::updateSelectInput(
        session, "country",
        choices = c(
          "All countries (pooled)" = POOLED_SENTINEL,
          stats::setNames(country_choices, country_choices)
        )
      )
    })

    ## the table to rank/filter: the pooled table, or the country table
    ## filtered to the selected country
    active_tbl <- shiny::reactive({
      if (is.null(input$country) || input$country == POOLED_SENTINEL || is.null(data$country_tbl)) {
        data$view1_tbl
      } else {
        dplyr::filter(data$country_tbl, country == input$country)
      }
    })

    is_country_selected <- shiny::reactive({
      !is.null(input$country) && input$country != POOLED_SENTINEL && !is.null(data$country_tbl)
    })

    output$param_note <- shiny::renderUI({
      tbl <- data$view1_tbl
      if (is.null(tbl)) return(NULL)
      it <- attr(tbl, "impact_thresh")
      ev <- attr(tbl, "evalperiod_weeks")
      if (is.null(it) && is.null(ev)) return(NULL)
      shiny::helpText(
        shiny::tags$b("Precomputed with: "),
        if (!is.null(ev)) paste0(ev, "-week evaluation period") else NULL,
        if (!is.null(it) && !is.null(ev)) "; " else NULL,
        if (!is.null(it)) paste0("impact/outbreak threshold = ", it, " cases.") else NULL
      )
    })

    output$country_note <- shiny::renderUI({
      shiny::req(is_country_selected())
      shiny::helpText(
        "Showing estimates for ", shiny::tags$b(input$country), " only. ",
        "The table, ranking and dimension figure below are all specific to ",
        input$country, "."
      )
    })

    selected_rows <- shiny::reactive({
      shiny::validate(shiny::need(
        !is.null(active_tbl()),
        "Precomputed utility table not found (data/complete_utility_data_mean_sd.csv)."
      ))
      shiny::validate(shiny::need(length(input$pop_keep) > 0, "Select at least one population group."))
      select_top_definitions(active_tbl(), pop_keep = input$pop_keep, n_top = input$n_top)
    })

    table_parts <- shiny::reactive({
      build_top_alerts_table(active_tbl(), pop_keep = input$pop_keep, n_top = input$n_top)
    })

    output$top_table <- shiny::renderUI({
      parts <- table_parts()
      shiny::validate(shiny::need(
        nrow(parts$display) > 0,
        "No alerts to display for this selection (this country/population group combination may have too little data)."
      ))

      tab_body <- dplyr::select(parts$display, -pop_brk)

      ## header text for the five utility-dimension columns gets a hover
      ## tooltip (the same description shown in the banner above); the
      ## other columns (Alert Definition, Alert Type, Utility Score) are
      ## left as plain text.
      plain_names <- names(tab_body)
      header_names <- dplyr::case_when(
        startsWith(plain_names, "Impact")     ~ dimension_tooltip_html(plain_names, DIMENSION_DESCRIPTIONS[["Impact"]]),
        startsWith(plain_names, "Efficiency") ~ dimension_tooltip_html(plain_names, DIMENSION_DESCRIPTIONS[["Efficiency"]]),
        startsWith(plain_names, "PPV")        ~ dimension_tooltip_html(plain_names, DIMENSION_DESCRIPTIONS[["PPV"]]),
        startsWith(plain_names, "Missed")     ~ dimension_tooltip_html(plain_names, DIMENSION_DESCRIPTIONS[["Missed"]]),
        startsWith(plain_names, "Timeliness") ~ dimension_tooltip_html(plain_names, DIMENSION_DESCRIPTIONS[["Timeliness"]]),
        TRUE ~ plain_names
      )

      caption_scope <- if (is_country_selected()) paste0(" \u2014 ", input$country) else ""

      kbl <- tab_body %>%
        kableExtra::kbl(
          format = "html",
          caption = if (identical(input$n_top, "all")) {
            paste0("All eligible alert definitions by utility score per population group", caption_scope)
          } else {
            paste0(
              "Top ", input$n_top,
              " eligible alert definitions by utility score per population group", caption_scope
            )
          },
          align = c("l", "l", "r", "r", "r", "r", "r", "r"),
          col.names = header_names,
          escape = FALSE
        ) %>%
        kableExtra::kable_styling(
          bootstrap_options = c("striped", "hover", "condensed"),
          full_width = TRUE, position = "center"
        )

      start <- 1
      for (i in seq_along(parts$group_counts)) {
        n_i <- parts$group_counts[i]
        kbl <- kableExtra::group_rows(
          kbl,
          group_label = pop_group_long_label(parts$pop_keep[i]),
          start_row = start,
          end_row = start + n_i - 1
        )
        start <- start + n_i
      }

      kbl <- kableExtra::row_spec(kbl, parts$top_row_index, bold = FALSE, background = "white")
      shiny::HTML(kbl)
    })

    fig_height <- shiny::reactive({
      sr <- selected_rows()
      n_rows <- nrow(sr)
      n_grp  <- dplyr::n_distinct(sr$pop_brk)
      paste0(max(320, 140 + n_grp * 30 + n_rows * 26), "px")
    })

    output$dimension_plot_container <- shiny::renderUI({
      shiny::plotOutput(session$ns("dimension_figure"), height = fig_height())
    })

    output$dimension_figure <- shiny::renderPlot({
      sr <- selected_rows()
      shiny::validate(shiny::need(nrow(sr) > 0, "No alerts to plot for this selection."))
      shiny::validate(shiny::need(
        !is.null(data$dist_tbl),
        paste0("Distribution files not found. Add the ",
               "compare_significant_*_testmeans_epidemic.parquet exports to data/.")
      ))
      fig <- make_dimensions_figure(
        sr, active_tbl(), data$dist_tbl,
        country = if (is_country_selected()) input$country else NULL
      )
      shiny::validate(shiny::need(
        !is.null(fig),
        "No distribution data available for this selection."
      ))
      fig
    })
  })
}
