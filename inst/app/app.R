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
      downloadButton("download_updated", "Download _updated.sqlite3"),
      tags$hr(),
      tags$strong("Tag Viewer"),
      uiOutput("viewer_strat_ui"),
      uiOutput("strat_role_ui"),
      uiOutput("viewer_dist_col_ui"),
      conditionalPanel(
        condition = "input.dist_col == 'path'",
        radioButtons("path_part", "Path part:",
                     choices  = c("Full path" = "full", "Leaf label only" = "leaf"),
                     selected = "full", inline = TRUE)
      ),
      uiOutput("viewer_centroid_ui"),
      actionButton("compute_clusters", "Compute viewer",
                   class = "btn-info btn-sm", style = "margin-top:6px;"),
      tags$hr(),
      uiOutput("viewer_wide_display_ui"),
      uiOutput("viewer_display_cols_ui")
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
        ),
        tabPanel(
          "5. Tag Viewer",
          value = "viewer",
          tabsetPanel(
            tabPanel(
              "Side-by-side (within)",
              h4("Tags ordered within strata"),
              div(style = "color:#666; font-size:90%; margin-bottom:8px;",
                  "Click a cell to view its highlight detail below."),
              DT::DTOutput("wide_dt"),
              tags$hr(),
              h5("Highlight detail"),
              DT::DTOutput("highlight_detail_dt")
            ),
            tabPanel(
              "Across strata",
              h4("Tags ordered across all strata"),
              DT::DTOutput("across_dt")
            )
          )
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
      nm <- isolate(input$sqlite$name)
      if (is.null(nm)) return("updated.sqlite3")
      base <- sub("\\.(sqlite3?|db)$", "", nm)
      sprintf("%s_updated.sqlite3", base)
    },
    content = function(file) {
      sq <- isolate(sqlite_data())
      if (is.null(sq)) {
        showNotification("Upload a SQLite export first.", type = "warning")
        return(invisible(NULL))
      }
      st <- isolate(applied_state())
      if (is.null(st)) {
        showNotification("Click Apply before downloading.", type = "warning")
        return(invisible(NULL))
      }
      sq$tags           <- st[[1]]
      sq$highlight_tags <- st[[2]]
      tryCatch(
        write_taguette_sqlite(sq, file),
        error = function(e) {
          showNotification(paste("Write failed:", conditionMessage(e)),
                           type = "error", duration = NULL)
        }
      )
    }
  )

  # ------------------------------------------------------------------
  # Tag Viewer: dynamic sidebar UI
  # ------------------------------------------------------------------
  output$viewer_strat_ui <- renderUI({
    req(review_tbl())
    cols    <- colnames(review_tbl())
    default <- intersect(c("1", "document_id"), cols)
    if (length(default) == 0L) default <- cols[1L]
    selectizeInput("strat_vars", "Stratify by:",
                   choices  = cols,
                   selected = default,
                   multiple = TRUE)
  })

  output$strat_role_ui <- renderUI({
    vars <- input$strat_vars
    if (is.null(vars) || length(vars) == 0L) return(NULL)
    do.call(tagList, lapply(vars, function(v) {
      rid <- paste0("role_", gsub("[^A-Za-z0-9_]", "_", v))
      radioButtons(
        inputId  = rid,
        label    = v,
        choices  = c("Column" = "col", "Row" = "row"),
        selected = "col",
        inline   = TRUE
      )
    }))
  })

  col_vars_r <- reactive({
    vars <- input$strat_vars
    req(vars)
    Filter(function(v) {
      rid  <- paste0("role_", gsub("[^A-Za-z0-9_]", "_", v))
      role <- input[[rid]]
      is.null(role) || role == "col"
    }, vars)
  })

  row_vars_r <- reactive({
    vars <- input$strat_vars
    req(vars)
    Filter(function(v) {
      rid  <- paste0("role_", gsub("[^A-Za-z0-9_]", "_", v))
      role <- input[[rid]]
      !is.null(role) && role == "row"
    }, vars)
  })

  col_keys_r <- reactive({
    req(review_tbl())
    cv <- col_vars_r()
    if (length(cv) == 0L) return(character(0))
    df   <- review_tbl()
    keys <- apply(
      as.data.frame(df[, cv, drop = FALSE]),
      1L, paste, collapse = "\x1f"
    )
    sort(unique(keys[!is.na(keys)]))
  })

  output$viewer_dist_col_ui <- renderUI({
    req(review_tbl())
    cols <- colnames(review_tbl())
    selectInput("dist_col", "Distance on:",
                choices  = cols,
                selected = if ("path" %in% cols) "path" else cols[1L])
  })

  output$viewer_wide_display_ui <- renderUI({
    req(review_tbl())
    cols <- colnames(review_tbl())
    selectInput("wide_display_col", "Cell content (side-by-side):",
                choices  = cols,
                selected = if ("path" %in% cols) "path" else cols[1L])
  })

  output$viewer_display_cols_ui <- renderUI({
    req(review_tbl())
    review_cols   <- colnames(review_tbl())
    computed_cols <- c("col_key", "row_key",
                       "order_within",  "dist_to_prev_within",
                       "order_across",  "dist_to_prev_across")
    all_choices <- unique(c(review_cols, computed_cols))
    default <- intersect(
      c("path", "highlight_id", "document_id", "snippet",
        "col_key", "row_key",
        "order_within",  "dist_to_prev_within",
        "order_across",  "dist_to_prev_across"),
      all_choices
    )
    selectizeInput("display_cols", "Show columns:",
                   choices  = all_choices,
                   selected = default,
                   multiple = TRUE,
                   options  = list(plugins = list("remove_button")))
  })

  output$viewer_centroid_ui <- renderUI({
    ck <- col_keys_r()
    if (length(ck) == 0L) return(NULL)
    ck_labels <- gsub("\x1f", " × ", ck)
    tagList(
      selectInput("centroid_strata", "Centroid column:",
                  choices = c("(none)" = "(none)",
                              setNames(ck, ck_labels))),
      conditionalPanel(
        condition = "input.centroid_strata != '(none)'",
        sliderInput("centroid_weight", "Centroid weight (w):",
                    min = 0, max = 1, value = 0.5, step = 0.05),
        sliderInput("neighbourhood_r",
                    "Neighbourhood radius (τ):",
                    min = 0, max = 1, value = 0.5, step = 0.05),
        sliderInput("pull_sharpness",
                    "Pull sharpness (α):",
                    min = 1, max = 50, value = 5, step = 1)
      )
    )
  })

  # ------------------------------------------------------------------
  # Tag Viewer: compute on button click
  # ------------------------------------------------------------------
  viewer_data <- eventReactive(input$compute_clusters, {
    req(review_tbl())
    cv <- col_vars_r()
    req(length(cv) > 0L)
    rv  <- row_vars_r()
    centroid_strata <- NULL
    cs <- input$centroid_strata
    if (!is.null(cs) && nzchar(cs) && cs != "(none)") {
      parts           <- strsplit(cs, "\x1f")[[1L]]
      centroid_strata <- setNames(as.list(parts), cv)
    }
    dc  <- if (!is.null(input$dist_col))       input$dist_col        else "path"
    w   <- if (!is.null(input$centroid_weight)) input$centroid_weight else 0.5
    tau <- if (!is.null(input$neighbourhood_r)) input$neighbourhood_r else 0.5
    alp <- if (!is.null(input$pull_sharpness))  input$pull_sharpness  else 5
    pp  <- if (!is.null(input$path_part))        input$path_part       else "full"
    tryCatch(
      compute_tag_clusters(
        df              = review_tbl(),
        col_vars        = cv,
        row_vars        = rv,
        dist_col        = dc,
        centroid_strata = centroid_strata,
        centroid_weight = w,
        neighbourhood_r = tau,
        pull_sharpness  = alp,
        path_part       = pp
      ),
      error = function(e) {
        showNotification(paste("Tag Viewer error:", conditionMessage(e)),
                         type = "error", duration = NULL)
        NULL
      }
    )
  })

  # ------------------------------------------------------------------
  # Tag Viewer: side-by-side DT
  # ------------------------------------------------------------------
  output$wide_dt <- DT::renderDT({
    req(viewer_data())
    wide <- viewer_data()$wide   # original (always path-valued; used by click handler)
    ann  <- viewer_data()$annotated

    # Build a display copy with substituted cell content if needed
    wdc <- input$wide_display_col
    if (!is.null(wdc) && wdc != "path" && wdc %in% colnames(ann)) {
      wide_disp  <- wide
      structural <- intersect(c("is_separator", "row_label", "pos"), colnames(wide_disp))
      tag_cols   <- setdiff(colnames(wide_disp), structural)
      has_sep_w  <- "is_separator" %in% colnames(wide_disp)

      # Dedup lookup: (path, strat_key) -> first non-NA display value
      av      <- ann[!is.na(ann$path), , drop = FALSE]
      av$dv   <- as.character(av[[wdc]])
      av$lk   <- paste0(av$path, "\x02", av$strat_key)
      av      <- av[!duplicated(av$lk), c("lk", "dv"), drop = FALSE]

      # Precompute row_key per row (needed to reconstruct strat_key)
      if (has_sep_w) {
        rk_vec <- character(nrow(wide_disp))
        cur_rk <- ""
        for (i in seq_len(nrow(wide_disp))) {
          rl <- wide_disp$row_label[i]
          if (!is.na(rl)) cur_rk <- gsub(" × ", "\x1f", gsub(" × ", "\x1f", rl))
          rk_vec[i] <- cur_rk
        }
      } else {
        rk_vec <- rep("", nrow(wide_disp))
      }

      for (col_label in tag_cols) {
        ck        <- gsub(" × ", "\x1f", gsub(" × ", "\x1f", col_label))
        path_vals <- wide_disp[[col_label]]
        sk_vals   <- paste(ck, rk_vec, sep = "\x1e")
        lk_vals   <- paste0(path_vals, "\x02", sk_vals)
        idx       <- match(lk_vals, av$lk)
        not_na    <- !is.na(path_vals)
        wide_disp[[col_label]][not_na] <- av$dv[idx[not_na]]
      }
    } else {
      wide_disp <- wide
    }

    has_sep <- "is_separator" %in% colnames(wide_disp)
    dt_opts <- list(pageLength = 50, scrollX = TRUE,
                    dom = "tip", ordering = FALSE)
    if (has_sep) {
      dt_opts$columnDefs <- list(list(visible = FALSE, targets = 0))
      dt_opts$rowCallback <- DT::JS(
        "function(row, data) {",
        "  if (data[0] === true) {",
        "    $(row).css({'background-color':'#dde4ec','font-weight':'bold'});",
        "  }",
        "}"
      )
    }

    DT::datatable(
      wide_disp,
      options   = dt_opts,
      rownames  = FALSE,
      selection = list(mode = "single", target = "cell")
    )
  })

  output$highlight_detail_dt <- DT::renderDT({
    req(viewer_data())
    click <- input$wide_dt_cell_clicked
    if (is.null(click) || length(click) == 0L) return(NULL)

    # Always use the ORIGINAL $wide (path-valued) for lookup, regardless of
    # which display column is shown — click$value may contain substituted text.
    wide    <- viewer_data()$wide
    ann     <- viewer_data()$annotated
    has_sep <- "is_separator" %in% colnames(wide)

    non_data       <- intersect(c("is_separator", "row_label", "pos"), colnames(wide))
    first_data_col <- length(non_data)
    if (click$col < first_data_col) return(NULL)

    # Path from original $wide by row/col index
    col_name     <- colnames(wide)[click$col + 1L]
    clicked_path <- as.character(wide[click$row, col_name])
    if (is.null(clicked_path) || is.na(clicked_path) || !nzchar(clicked_path)) return(NULL)

    col_key <- gsub(" × ", "\x1f", col_name)

    if (has_sep) {
      labels    <- wide$row_label
      last_idx  <- tail(which(!is.na(labels[seq_len(click$row)])), 1L)
      pretty_rk <- if (length(last_idx) > 0L) labels[last_idx] else ""
      row_key   <- gsub(" × ", "\x1f", pretty_rk)
    } else {
      row_key <- ""
    }

    detail <- ann[
      !is.na(ann$path) &
        ann$path    == clicked_path &
        ann$col_key == col_key &
        ann$row_key == row_key, ]

    dc_sel    <- if (!is.null(input$display_cols) && length(input$display_cols) > 0L)
                   input$display_cols
                 else
                   c("highlight_id", "document_id", "snippet",
                     "order_within", "dist_to_prev_within")
    show_cols <- intersect(dc_sel, colnames(detail))
    if (length(show_cols) == 0L) show_cols <- colnames(detail)[1L]
    DT::datatable(
      detail[, show_cols, drop = FALSE],
      options  = list(scrollX = TRUE, dom = "tip"),
      rownames = FALSE
    )
  })

  # ------------------------------------------------------------------
  # Tag Viewer: across-strata DT
  # ------------------------------------------------------------------
  output$across_dt <- DT::renderDT({
    req(viewer_data())
    ann <- viewer_data()$annotated
    ann <- ann[order(ann$order_across, na.last = TRUE), ]
    dc_sel    <- if (!is.null(input$display_cols) && length(input$display_cols) > 0L)
                   input$display_cols
                 else
                   c("path", "col_key", "row_key", "order_across",
                     "dist_to_prev_across", "highlight_id", "document_id")
    show_cols <- intersect(dc_sel, colnames(ann))
    if (length(show_cols) == 0L) show_cols <- colnames(ann)[1L]
    dt <- DT::datatable(
      ann[, show_cols, drop = FALSE],
      options  = list(pageLength = 50, scrollX = TRUE),
      filter   = "top",
      rownames = FALSE
    )
    if ("dist_to_prev_across" %in% show_cols) {
      dt <- DT::formatRound(dt, "dist_to_prev_across", digits = 3)
      dt <- DT::formatStyle(
        dt,
        "dist_to_prev_across",
        background         = DT::styleColorBar(c(0, 1), "lightcoral"),
        backgroundSize     = "98% 88%",
        backgroundRepeat   = "no-repeat",
        backgroundPosition = "center"
      )
    }
    dt
  })
}

shinyApp(ui, server)
