## ---------------------------------------------------------------------------
## view_help.R
## "How to use the app": user-facing documentation panel explaining
## inputs, outputs, and interpretation of View 1 (utility + figures).
## ---------------------------------------------------------------------------

#' The five alert-utility dimensions, as a data structure (not an image) so
#' the table can be styled and maintained like the rest of the app. Content
#' matches the manuscript's Table 1: dimension, motivation, quantitative
#' metric.
ALERT_UTILITY_DIMENSIONS_TABLE <- list(
  list(
    dimension = "Potential Impact",
    motivation = paste(
      "A useful alert helps to maximize the public health impact of outbreak",
      "control measures like reactive OCV campaigns."
    ),
    metric = paste(
      "Mean suspected cases observed in the 52-week evaluation period",
      "after alert."
    )
  ),
  list(
    dimension = "Potential Efficiency",
    motivation = paste(
      "A useful alert helps to maximize the impact per target population",
      "(here, per dose of reactive OCV campaigns)."
    ),
    metric = paste(
      "Mean suspected cases per target population in the 52-week",
      "evaluation period after alert."
    )
  ),
  list(
    dimension = "Positive Predictive Value (PPV)",
    motivation = paste(
      "A useful alert has a high probability of being followed by a large",
      "number of cases."
    ),
    metric = paste(
      "Proportion of alerts preceding at least 300 suspected cases in the",
      "52-week evaluation period after alert."
    )
  ),
  list(
    dimension = "Missed Outbreaks",
    motivation = "A useful alert minimizes the proportion of large outbreaks missed.",
    metric = paste(
      "Proportion of outbreaks of at least 300 suspected cases missed by",
      "the alert."
    )
  ),
  list(
    dimension = "Timeliness",
    motivation = "A useful alert is triggered as early in a large outbreak as possible.",
    metric = paste(
      "Mean lag in weeks between outbreak start and alert trigger for",
      "outbreaks of at least 300 suspected cases."
    )
  )
)

#' Render ALERT_UTILITY_DIMENSIONS_TABLE as a plain HTML table (no image).
alert_utility_dimensions_html_table <- function() {
  header <- shiny::tags$tr(
    shiny::tags$th("Alert utility dimension", style = "text-align:left; padding:10px 14px; border-bottom:2px solid #999;"),
    shiny::tags$th("Motivation", style = "text-align:left; padding:10px 14px; border-bottom:2px solid #999;"),
    shiny::tags$th("Quantitative metric", style = "text-align:left; padding:10px 14px; border-bottom:2px solid #999;")
  )
  
  rows <- lapply(ALERT_UTILITY_DIMENSIONS_TABLE, function(row) {
    shiny::tags$tr(
      shiny::tags$td(shiny::strong(row$dimension), style = "padding:10px 14px; border-bottom:1px solid #ddd; vertical-align:top; white-space:nowrap;"),
      shiny::tags$td(row$motivation, style = "padding:10px 14px; border-bottom:1px solid #ddd; vertical-align:top;"),
      shiny::tags$td(row$metric, style = "padding:10px 14px; border-bottom:1px solid #ddd; vertical-align:top;")
    )
  })
  
  shiny::tags$table(
    style = "width:100%; border-collapse:collapse; margin: 10px 0 15px 0;",
    shiny::tags$thead(header),
    shiny::tags$tbody(rows)
  )
}

view_help_ui <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::fluidPage(
    
    shiny::fluidRow(
      shiny::column(
        width = 10,
        offset = 1,
        
        ## slightly larger base font/line-height for the whole page
        shiny::tags$div(
          style = "font-size: 17px; line-height: 1.65;",
          
          shiny::tags$h3("How to use the app", style = "font-size: 30px;"),
          
          shiny::p(
            "The Cholera Alert Explorer provides insights about what to expect after suspected cholera cases appear in a potential outbreak-prone location (i.e., \u201can alert is triggered\u201d) in two different ways:"
          ),
          
          shiny::tags$ul(
            
            shiny::tags$li(
              shiny::strong("Top Alert Definitions: "),
              "Examine what happens in the 1-year period after an alert is triggered across different dimensions of utility relevant to cholera control planning."
            ),
            
            shiny::tags$li(
              shiny::strong("Explore Timelines: "),
              "Explore time series of suspected cholera surveillance before and after an alert is triggered."
            )
          ),
          
          shiny::tags$div(
            style = "margin-top: 14px; margin-bottom: 6px;",
            shiny::p(
              "We compared 24 alert definitions, which have the following types of patterns:"
            )
          ),
          
          shiny::tags$ul(
            
            shiny::tags$li(
              shiny::strong("Trend-based alerts (3): "),
              "Triggered by an upward case trend as compared to the mean number of cases in the previous four weeks."
            ),
            
            shiny::tags$li(
              shiny::strong("Weekly case-based alerts (7): "),
              "Triggered when a threshold number of cases is exceeded weekly for three consecutive weeks."
            ),
            
            shiny::tags$li(
              shiny::strong("Cumulative case-based alerts (7): "),
              "Triggered when a threshold number of cases is exceeded over a three-week period."
            ),
            
            shiny::tags$li(
              shiny::strong("Rate-based alerts (7): "),
              "Triggered when a threshold number of cases per population is exceeded weekly for three consecutive weeks."
            )
          ),
          
          shiny::p("We identified five dimensions of alert utility:"),
          
          ## -------- Table 1, recreated as real HTML (not an image) --------
          alert_utility_dimensions_html_table(),
          
          shiny::tags$div(
            style = "
              border: 1px solid #d0d0d0;
              background-color: #f7f7f7;
              padding: 12px 15px;
              border-radius: 6px;
              margin-top: 1px;
              font-weight: 500;
            ",
            "In most cholera-outbreak-prone locations, we recommend using one of the top-performing alert definitions, identified from an analysis of retrospective data \u2013 \u201c\u2265 50 weekly cases for 3 consecutive weeks\u201d or \u201c\u2265 100 cumulative cases over 3 consecutive weeks\u201d."
          ),
          
          shiny::p("A preprint about this work is coming soon."),
          
          shiny::br()
        )
      )
    )
  )
}

view_help_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    # Static page: no reactive logic needed
  })
}