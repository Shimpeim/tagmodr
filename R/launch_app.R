#' Launch the tagmodr Shiny app.
#'
#' Interactive UI over the pipeline: upload a Taguette SQLite, preview and
#' download the per-highlight review CSV, upload an edited mod-Excel
#' workbook, apply the operations, and download the updated SQLite for
#' re-import.
#'
#' The app requires \pkg{shiny} and \pkg{DT}, both listed under
#' \code{Suggests}. Install them explicitly if they are missing.
#'
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}
#'   (e.g. \code{port}, \code{host}, \code{launch.browser}).
#'
#' @return Called for its side effect (starts a Shiny app). Does not return.
#' @export
launch_app <- function(...) {
  for (pkg in c("shiny", "DT")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "The `%s` package is required to launch the app. Install it with install.packages('%s').",
        pkg, pkg
      ))
    }
  }
  app_dir <- system.file("app", package = "tagmodr")
  if (!nzchar(app_dir)) {
    stop("Could not find the app directory. Reinstall tagmodr.")
  }
  shiny::runApp(app_dir, ...)
}
