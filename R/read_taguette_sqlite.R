#' Read a Taguette SQLite export into a named list of data frames.
#'
#' Connects to the Taguette SQLite export, reads every non-system table into
#' a data frame, and returns them as a named list keyed by table name. The
#' connection is opened and closed within the call.
#'
#' The returned list is what the rest of the pipeline consumes:
#' \code{$tag_table} carries the tag hierarchy, \code{$highlights} carries
#' the coded excerpts, \code{$snippets} carries the extracted text.
#'
#' @param path Path to the Taguette \code{.sqlite3} file.
#'
#' @return Named list of data frames, one per non-system table in the
#'   SQLite. Also carries the \code{"table_names"} attribute -- an ordered
#'   character vector of table names, in the order they were read. This
#'   preserves the order needed by \code{\link{write_taguette_sqlite}} to
#'   round-trip the SQLite without reordering tables.
#' @export
read_taguette_sqlite <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("read_taguette_sqlite: file not found: %s", path))
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)
  tables <- tables[tables != "sqlite_sequence"]

  out <- vector("list", length = length(tables))
  names(out) <- tables
  for (i in seq_along(tables)) {
    out[[i]] <- DBI::dbGetQuery(
      conn = con,
      statement = sprintf("SELECT * FROM '%s'", tables[i])
    )
  }
  attr(out, "table_names") <- tables
  out
}
