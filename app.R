## ---------------------------------------------------------------------------
## Cholera Alert Explorer - Shiny app
##
## Tabs:
##   How to use the app  - static help/documentation page (view_help.R)
##   Top Alert Definitions - loads the precomputed per-definition utility
##         table (data/complete_utility_data_mean_sd.csv, produced by
##         alert_utility_score.qmd) and shows the top-N alert definitions per
##         population group, plus a manuscript-style distribution figure
##         restricted to the selected alerts. No utility calculations run in
##         the app (view1_utility.R).
##   Explore Timelines - anonymised alert-window explorer: random samples of
##         individual "\u2265 50 weekly" / "\u2265 100 total" alert occurrences, each
##         showing a fixed 4-weeks-before/56-weeks-after case window with the
##         first-alert week marked (view2_timeseries.R).
##   About us - static project/research-group information (view_about.R)
## ---------------------------------------------------------------------------

## alert-definition labels contain the "\u2265" (>=) glyph; make sure the
## session runs in a UTF-8 locale so it renders rather than showing <U+2265>.
if (!grepl("UTF-8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE)) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "en_GB.UTF-8")) {
    if (suppressWarnings(Sys.setlocale("LC_CTYPE", loc)) != "") break
  }
}

library(shiny)
library(dplyr)
library(tidyr)
library(ggplot2)
library(kableExtra)
library(patchwork)
library(arrow)

source("R/data_load.R")
source("R/utility_calc.R")
source("R/view1_utility.R")
source("R/view2_timeseries.R")
source("R/view_help.R")
source("R/view_about.R")

app_data <- load_app_data("data")

ui <- navbarPage(
  title = "Cholera Alert Explorer",
  id = "main_nav",
  tabPanel("Top Alert Definitions", view1_ui("view1")),
  tabPanel("Explore Timelines", view2_ui("view2")),
  tabPanel("How to use the app", view_help_ui("help")),
  tabPanel("About us", view_about_ui("about"))
)

server <- function(input, output, session) {
  view1_server("view1", app_data)
  view2_server("view2", app_data)
  view_help_server("help")
  view_about_server("about")
}

shinyApp(ui, server)
