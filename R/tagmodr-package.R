#' tagmodr: Iterative Codebook Development for Taguette QDA Projects
#'
#' An R pipeline for iterative codebook development on Taguette qualitative
#' analysis projects. Read a Taguette SQLite export, materialise the tag
#' hierarchy into a per-highlight review table, apply user-authored
#' rename / merge / unlink / add / apply operations from an Excel workbook,
#' and write a new SQLite for re-import.
#'
#' The typical iteration is:
#' \enumerate{
#'   \item \code{\link{read_taguette_sqlite}} to load a Taguette SQLite export.
#'   \item \code{\link{build_review_table}} to materialise the tag hierarchy
#'         into a per-highlight review table.
#'   \item Export the review table to Excel, edit the mod columns, save.
#'   \item \code{\link{create_tagmod_list}} to parse the edited Excel.
#'   \item \code{\link{normalize_tag_paths}} then
#'         \code{\link{apply_tagmod_ops}} to apply the operations.
#'   \item \code{\link{write_taguette_sqlite}} to write a fresh
#'         \code{*_updated.sqlite3} for re-import.
#' }
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom magrittr %>%
#' @importFrom plyr ddply dlply
#' @importFrom dplyr copy_to left_join
#' @importFrom tidyr pivot_wider
#' @importFrom readxl read_excel
#' @importFrom readr write_excel_csv
#' @importFrom RSQLite SQLite
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery dbListTables
NULL
