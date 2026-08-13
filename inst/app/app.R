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
      tags$strong("Step 2. Edit codebook offline"),
      tags$p(
        style = "font-size: 90%; margin-top: 6px;",
        "Open the ", tags$em("Review table"), " tab, click ",
        tags$strong("Download review CSV"), ", open it in Excel, ",
        "save-as with a ", tags$code("..mod.xlsx"), " suffix, then fill in the ",
        tags$code("Old_New"), " and ", tags$code("from_to"), " columns to ",
        "describe rename / merge / add / apply / unlink operations. ",
        "See the ", tags$em("Instructions"), " tab for the full recipe."
      ),
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
          div(
            style = "background:#f5f7fa; border-left:4px solid #337ab7; padding:10px 14px; margin-bottom:12px;",
            tags$strong("What to do next:"),
            tags$ol(
              tags$li("Click ", tags$strong("Download review CSV"), " above."),
              tags$li(
                "Open the CSV in Excel and ", tags$em("Save As"),
                " with a ", tags$code("..mod.xlsx"), " suffix (e.g. ",
                tags$code("my_project_tag_review..mod.xlsx"), ")."
              ),
              tags$li(
                "Add a numeric ", tags$code("Old_New"),
                " value to each row you want to modify (rows sharing an ",
                tags$code("Old_New"), " form one operation)."
              ),
              tags$li(
                "Add a ", tags$code("from_to"),
                " value on each of those rows: ",
                tags$code("from"), " + ", tags$code("to"), " for rename/merge; ",
                tags$code("add"), " for a new tag; ",
                tags$code("apply"), " for an existing tag; ",
                tags$code("unlink"), " to remove a (highlight, tag) pair."
              ),
              tags$li(
                "Come back here and upload the workbook via ",
                tags$strong("Step 3"), " in the sidebar, then click ",
                tags$strong("Apply"), "."
              )
            ),
            tags$p(
              style = "margin-bottom:0;",
              "Full recipe for each op type is on the ",
              tags$em("Instructions"), " tab."
            )
          ),
          DT::DTOutput("review_dt")
        ),
        tabPanel(
          "3. Instructions",
          value = "help",
          h4("How to annotate the mod-Excel"),
          tags$p(
            "Each operation is one or more rows in the mod-Excel sharing one ",
            tags$code("Old_New"), " integer. Different operations use different ",
            tags$code("Old_New"), " values. The available ",
            tags$code("from_to"), " values are: ",
            tags$code("from"), ", ", tags$code("to"), ", ",
            tags$code("add"), ", ", tags$code("apply"), ", ",
            tags$code("unlink"), "."
          ),
          h5("Rename a tag  (path_change)"),
          tags$p("Two rows sharing one Old_New. Target path must ",
                 tags$em("not"), " already exist in the codebook."),
          tags$table(class = "table table-bordered table-sm",
            tags$thead(tags$tr(tags$th("Old_New"), tags$th("from_to"), tags$th("path"))),
            tags$tbody(
              tags$tr(tags$td("1"), tags$td("from"), tags$td("Character\\\\ Grief\\\\ Rituals")),
              tags$tr(tags$td("1"), tags$td("to"),   tags$td("Character\\\\ Small Rituals"))
            )
          ),
          h5("Merge two tags  (path_change)"),
          tags$p("Two rows. Target path must ", tags$em("already"),
                 " exist. Highlights on the from-tag are re-pointed to the to-tag; the from-tag becomes DEMOTED_."),
          tags$table(class = "table table-bordered table-sm",
            tags$thead(tags$tr(tags$th("Old_New"), tags$th("from_to"), tags$th("path"))),
            tags$tbody(
              tags$tr(tags$td("2"), tags$td("from"), tags$td("Style\\\\ Voice")),
              tags$tr(tags$td("2"), tags$td("to"),   tags$td("Style\\\\ Sentence Length"))
            )
          ),
          h5("Add a new tag  (add)"),
          tags$p("One row per highlight to attach the new tag to. All rows share the same path. Path must ",
                 tags$em("not"), " already exist. Highlight cells can be blank for a vocabulary-only add."),
          tags$table(class = "table table-bordered table-sm",
            tags$thead(tags$tr(tags$th("Old_New"), tags$th("from_to"), tags$th("highlight_id"), tags$th("path"))),
            tags$tbody(
              tags$tr(tags$td("3"), tags$td("add"), tags$td("42"), tags$td("Character\\\\ Silence")),
              tags$tr(tags$td("3"), tags$td("add"), tags$td("57"), tags$td("Character\\\\ Silence"))
            )
          ),
          h5("Apply an existing tag  (apply)"),
          tags$p("Mirror of add. Path must ", tags$em("already"), " exist -- exactly once."),
          tags$table(class = "table table-bordered table-sm",
            tags$thead(tags$tr(tags$th("Old_New"), tags$th("from_to"), tags$th("highlight_id"), tags$th("path"))),
            tags$tbody(
              tags$tr(tags$td("4"), tags$td("apply"), tags$td("88"), tags$td("Setting\\\\ Domestic")),
              tags$tr(tags$td("4"), tags$td("apply"), tags$td("91"), tags$td("Setting\\\\ Domestic"))
            )
          ),
          h5("Unlink a (highlight, tag) pair  (unlink)"),
          tags$p("One row per pair to remove. Other rows with the same tag or highlight are untouched. Path column is ignored."),
          tags$table(class = "table table-bordered table-sm",
            tags$thead(tags$tr(tags$th("Old_New"), tags$th("from_to"), tags$th("highlight_id"), tags$th("tag_id"))),
            tags$tbody(
              tags$tr(tags$td("5"), tags$td("unlink"), tags$td("100"), tags$td("3")),
              tags$tr(tags$td("5"), tags$td("unlink"), tags$td("101"), tags$td("3"))
            )
          ),
          h5("Order of application"),
          tags$p("The Apply step re-orders operations by class before running: ",
                 tags$code("path_change"), " -> ", tags$code("add"), " -> ",
                 tags$code("apply"), " -> ", tags$code("unlink"),
                 ". Ordering within Old_New numbers is preserved within each class.")
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
