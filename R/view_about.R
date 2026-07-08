## ---------------------------------------------------------------------------
## view_about.R
## "About us" page (baseline): research group information
## ---------------------------------------------------------------------------

view_about_ui <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::fluidPage(
    
    shiny::titlePanel(""),
    
    shiny::fluidRow(
      shiny::column(
        width = 10,
        offset = 1,
        
        shiny::tags$div(
          
          style = "font-size: 17px; line-height: 1.65;",
          
          shiny::h3("About"),
          
          shiny::p(
            "The Cholera Alert Explorer provides insights about what to expect after suspected cholera cases appear in a potential outbreak-prone location.",
            
            "This application was developed by Christina Alam and Elizabeth Lee from the ",
            
            shiny::tags$a(
              href = "https://www.diseasedynamics.ch/",
              "Geneva Disease Dynamics team",
              target = "_blank"
            ),
            
            " at the University of Geneva."
          ),
          
          shiny::p("A preprint about this work is coming soon."),
          
          shiny::p("Last updated: 8 July 2026"),
          
          shiny::br()
        )
      )
    )
  )
}

view_about_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    # static page (no reactive logic)
  })
}