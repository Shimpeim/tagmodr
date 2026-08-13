#' Write a named list of data frames back to a Taguette-shaped SQLite.
#'
#' Companion of \code{\link{read_taguette_sqlite}}. Opens a fresh SQLite at
#' \code{path} and writes each element of \code{tables} as a table of the
#' same name, in the order recorded in \code{attr(tables, "table_names")}
#' (or the list's own names, if the attribute is absent). Overwrites any
#' existing file at \code{path}.
#'
#' @param tables Named list of data frames as returned by
#'   \code{\link{read_taguette_sqlite}}. If the caller has updated
#'   \code{$tag_table} or \code{$highlights}, those updated frames are what
#'   gets written.
#' @param path Path to the destination \code{.sqlite3} file. Convention:
#'   sibling of the source SQLite with an \code{_updated.sqlite3} suffix.
#'
#' @return Invisibly returns \code{path}.
#' @export
write_taguette_sqlite <- function(tables, path) {
  table_names <- attr(tables, "table_names")
  if (is.null(table_names)) table_names <- names(tables)
  if (is.null(table_names) || any(!nzchar(table_names))) {
    stop("write_taguette_sqlite: `tables` must be a named list.")
  }

  if (file.exists(path)) file.remove(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  for (nm in table_names) {
    dplyr::copy_to(
      con, tables[[nm]], name = nm,
      overwrite = TRUE, temporary = FALSE
    )
  }
  invisible(path)
}
