# tagmodr Shiny app: single-file, five-step flow.
#
# 1. Upload a Taguette SQLite export.
# 2. Preview the per-highlight review table; download it as CSV.
# 3. Upload an edited mod-Excel workbook (`*..mod.xlsx`).
# 4. Preview the parsed operations; click Apply.
# 5. Download the updated SQLite for re-import into Taguette.

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop("The `shiny` package is required. Install it via install.packages('shiny').")
}
if (!requireNamespace("DT", quietly = TRUE)) {
  stop("The `DT` package is required. Install it via install.packages('DT').")
}

library(shiny)
library(tagmodr)

# Raise the max upload size so real Taguette exports (multi-MB) don't hit
# Shiny's 5 MB default.
options(shiny.maxRequestSize = 200 * 1024^2)

ui <- fluidPage(
  titlePanel("tagmodr - Taguette codebook editor"),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      helpText(
        "Iterative codebook development for Taguette QDA projects. ",
        "Upload a SQLite export, download the review CSV, edit the mod-Excel ",
        "offline, upload it back, apply, download the updated SQLite."
      ),
      tags$hr(),
      tags$strong("Step 1. Upload SQLite"),
      fileInput("sqlite", NULL, accept = c(".sqlite3", ".sqlite", ".db")),
      tags$hr(),
      tags$strong("Step 3. Upload mod-Excel"),
      fileInput("modxlsx", NULL, accept = c(".xlsx")),
      numericInput("length_path", "Hierarchy depth (length.path)",
                   value = 4, min = 1, max = 10, step = 1),
      tags$hr(),
      tags$strong("Step 4. Apply operations"),
      actionButton("apply_ops", "Apply", class = "btn-primary"),
      tags$hr(),
      tags$strong("Step 5. Download updated SQLite"),
      downloadButton("download_updated", "Download _updated.sqlite3")
    ),

    mainPanel(
      width = 9,
      tabsetPanel(
        id = "tabs",
        tabPanel(
          "1. Source SQLite",
          value = "src",
          h4("Tables in the SQLite export"),
          verbatimTextOutput("sqlite_summary")
        ),
        tabPanel(
          "2. Review table",
          value = "review",
          h4("Per-highlight review table"),
          downloadButton("download_review", "Download review CSV"),
          br(), br(),
          DT::DTOutput("review_dt")
        ),
        tabPanel(
          "4. Parsed operations",
          value = "ops",
          h4("Operations parsed from mod-Excel"),
          verbatimTextOutput("ops_summary"),
          h4("After Apply: updated tag_table (first 200 rows)"),
          DT::DTOutput("updated_tags_dt"),
          h4("After Apply: updated highlight_tags (first 200 rows)"),
          DT::DTOutput("updated_hl_dt")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  # ------------------------------------------------------------------
  # Step 1: read the uploaded SQLite into a named list.
  # ------------------------------------------------------------------
  sqlite_data <- reactive({
    req(input$sqlite)
    tryCatch(
      read_taguette_sqlite(input$sqlite$datapath),
      error = function(e) {
        showNotification(paste("Failed to read SQLite:", conditionMessage(e)),
                         type = "error", duration = NULL)
        NULL
      }
    )
  })

  output$sqlite_summary <- renderPrint({
    req(sqlite_data())
    sq <- sqlite_data()
    cat(sprintf("File: %s\n\n", input$sqlite$name))
    cat("Tables and row counts:\n")
    for (nm in names(sq)) cat(sprintf("  %-20s %d rows\n", nm, nrow(sq[[nm]])))
  })

  # ------------------------------------------------------------------
  # Step 2: build the review table.
  # ------------------------------------------------------------------
  review_tbl <- reactive({
    sq <- sqlite_data()
    req(sq)
    validate(
      need("tags" %in% names(sq),          "SQLite has no `tags` table."),
      need("highlight_tags" %in% names(sq), "SQLite has no `highlight_tags` table."),
      need("highlights" %in% names(sq),    "SQLite has no `highlights` table.")
    )
    tryCatch({
      tags_norm <- normalize_tag_paths(sq$tags)
      build_review_table(
        df.tag_table  = tags_norm,
        df.highlights = sq$highlight_tags,
        df.snippets   = sq$highlights
      )
    }, error = function(e) {
      showNotification(paste("Failed to build review table:", conditionMessage(e)),
                       type = "error", duration = NULL)
      NULL
    })
  })

  output$review_dt <- DT::renderDT({
    req(review_tbl())
    DT::datatable(
      review_tbl(),
      options = list(pageLength = 25, scrollX = TRUE),
      filter = "top",
      rownames = FALSE
    )
  })

  output$download_review <- downloadHandler(
    filename = function() {
      req(input$sqlite)
      base <- sub("\\.(sqlite3?|db)$", "", input$sqlite$name)
      sprintf("%s_tag_review.csv", base)
    },
    content = function(file) {
      req(review_tbl())
      readr::write_excel_csv(review_tbl(), file)
    }
  )

  # ------------------------------------------------------------------
  # Step 3: parse the uploaded mod-Excel.
  # ------------------------------------------------------------------
  ops <- reactive({
    req(input$modxlsx)
    tryCatch(
      create_tagmod_list(
        path = input$modxlsx$datapath,
        length.path = as.integer(input$length_path)
      ),
      error = function(e) {
        showNotification(paste("Failed to parse mod-Excel:", conditionMessage(e)),
                         type = "error", duration = NULL)
        NULL
      }
    )
  })

  output$ops_summary <- renderPrint({
    o <- ops()
    req(o)
    cat(sprintf("Mod-Excel: %s\n", input$modxlsx$name))
    cat(sprintf("Total operation groups: %d\n\n", length(o)))
    classes <- vapply(o, function(x) class(x)[1], character(1))
    tab <- table(classes)
    cat("By op class:\n")
    for (nm in names(tab)) cat(sprintf("  %-14s %d\n", nm, tab[[nm]]))
    cat("\nFirst 20 ops:\n")
    for (i in seq_len(min(length(o), 20))) {
      op <- o[[i]]
      cls <- class(op)[1]
      preview <- switch(cls,
        "path_change" = sprintf("%s  ->  %s", op$str_from, op$str_to),
        "unlink"      = sprintf("%d pair(s)", length(op$highlight_ids)),
        "add"         = sprintf("path='%s' (%d highlight(s))", op$path, length(op$highlight_ids)),
        "apply"       = sprintf("path='%s' (%d highlight(s))", op$path, length(op$highlight_ids)),
        "??"
      )
      cat(sprintf("  [%s]  Old_New=%s  %s  %s\n",
                  cls, names(o)[i], strrep(" ", max(0, 11 - nchar(cls))), preview))
    }
  })

  # ------------------------------------------------------------------
  # Step 4: apply.
  # ------------------------------------------------------------------
  applied_state <- reactiveVal(NULL)

  observeEvent(input$apply_ops, {
    sq <- sqlite_data(); req(sq)
    o <- ops(); req(o)
    tryCatch({
      tags_norm <- normalize_tag_paths(sq$tags)
      state <- apply_tagmod_ops(o,
                                df.tag_table  = tags_norm,
                                df.highlights = sq$highlight_tags)
      applied_state(state)
      showNotification(
        sprintf("Applied %d op(s). tag_table: %d rows. highlight_tags: %d rows.",
                length(o), nrow(state[[1]]), nrow(state[[2]])),
        type = "message", duration = 6
      )
    }, error = function(e) {
      applied_state(NULL)
      showNotification(paste("Apply failed:", conditionMessage(e)),
                       type = "error", duration = NULL)
    })
  })

  output$updated_tags_dt <- DT::renderDT({
    st <- applied_state(); req(st)
    DT::datatable(head(st[[1]], 200), options = list(scrollX = TRUE), rownames = FALSE)
  })

  output$updated_hl_dt <- DT::renderDT({
    st <- applied_state(); req(st)
    DT::datatable(head(st[[2]], 200), options = list(scrollX = TRUE), rownames = FALSE)
  })

  # ------------------------------------------------------------------
  # Step 5: download the updated SQLite.
  # ------------------------------------------------------------------
  output$download_updated <- downloadHandler(
    filename = function() {
      req(input$sqlite)
      base <- sub("\\.(sqlite3?|db)$", "", input$sqlite$name)
      sprintf("%s_updated.sqlite3", base)
    },
    content = function(file) {
      sq <- sqlite_data(); req(sq)
      st <- applied_state()
      validate(need(!is.null(st), "Click Apply first before downloading."))
      sq$tags <- st[[1]]
      sq$highlight_tags <- st[[2]]
      write_taguette_sqlite(sq, file)
    }
  )
}

shinyApp(ui, server)
