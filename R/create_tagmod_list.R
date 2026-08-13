#' Parse an edited mod-Excel workbook into a class-tagged operations list.
#'
#' Reads a mod-Excel workbook (the review-pass CSV opened in Excel with
#' \code{Old_New} and \code{from_to} columns annotated by the user) and
#' returns a list keyed by \code{Old_New}, one element per operation group.
#' Each element is tagged with an S3 class describing its op type:
#' \code{"path_change"} (rename or merge), \code{"unlink"}, \code{"add"},
#' or \code{"apply"}. \code{apply_tagmod_ops()} dispatches on this class.
#'
#' Rows with NA \code{Old_New} are silently dropped. Mixed \code{from_to}
#' values within one \code{Old_New} group are a hard error.
#'
#' For \code{path_change} groups: the \code{path} cell is regex-escaped
#' (backslashes doubled, parentheses escaped) so it can be used as a
#' \code{gsub} pattern by \code{change_tag()}. For \code{add} and
#' \code{apply}, the \code{path} cell is kept in canonical form (single
#' backslash pair between segments) for exact-match consumption.
#'
#' Path normalisation before regex-escaping:
#' \enumerate{
#'   \item Strip any run of ASCII spaces immediately before \code{\\\\}
#'         (canonicalises user-side format variance).
#'   \item Insert a space after \code{\\\\} when it sits between two Unicode
#'         letters/digits -- so both ASCII and Japanese segment boundaries
#'         get the canonical \code{Domain\\\\ Section} form.
#' }
#'
#' @param path Path to the mod-Excel workbook.
#' @param id_col.Old_New Character. Column name used to group rows into
#'   operations. Default \code{"Old_New"}.
#' @param length.path Integer. Number of hierarchy columns in the mod-Excel
#'   (\code{1 - Domain}, ..., \code{4 - subkey}).
#' @param verbose Logical. If \code{TRUE}, print per-row normalisation
#'   diagnostics via \code{message()}.
#'
#' @return Named list keyed by \code{Old_New}. Each element is a list with
#'   an S3 class attribute (\code{path_change} / \code{unlink} / \code{add}
#'   / \code{apply}) plus \code{"list"}. See details.
#' @export
create_tagmod_list <- function(
    path,
    id_col.Old_New = "Old_New",
    length.path = 4L,
    verbose = FALSE
) {
  df.tagmod_tabler <- readxl::read_excel(path = path) %>% data.frame()
  df.tagmod_tabler <- df.tagmod_tabler[!is.na(df.tagmod_tabler[, id_col.Old_New]), ]

  colnames(df.tagmod_tabler)[grep(id_col.Old_New, colnames(df.tagmod_tabler))] <- "Old_New"

  all_path <-
    df.tagmod_tabler %>%
    plyr::ddply(
      c("Old_New", "from_to", "highlight_id", "tag_id"),
      function(d) {
        if (!is.na(d$from_to) && d$from_to == "unlink") return(d)

        is_add_or_apply <- !is.na(d$from_to) && d$from_to %in% c("add", "apply")

        if (!is.na(d$path)) {
          if (verbose) message(sprintf("PATH: %s, tag ID: %s (orig)", d$path, d$tag_id))
          d$path <- gsub("[ ]+\\\\\\\\", "\\\\\\\\", d$path)
          for (i in seq_len(length.path)) {
            d$path <-
              gsub(
                "(?<=[\\p{L}\\p{N}\\)])\\\\\\\\(?=[\\p{L}\\p{N}\\(])",
                "\\1\\\\\\\\ \\2",
                d$path,
                perl = TRUE
              )
          }
          if (verbose) message(sprintf("  step 1 (canonical): %s", d$path))

          if (!is_add_or_apply) {
            d$path <- gsub("\\\\", "\\\\\\\\", d$path)
            d$path <- gsub("\\(", "\\\\(", d$path)
            d$path <- gsub("\\)", "\\\\)", d$path)
            if (verbose) message(sprintf("  step fin (path_change escape): %s", d$path))
          } else if (verbose) {
            message(sprintf("  step fin (add/apply, no escape): %s", d$path))
          }
          return(d)
        } else {
          hierarchy_vals <- as.character(d[1, colnames(d)[6:(6 + length.path - 1)]])
          hierarchy_vals <- hierarchy_vals[
            !is.na(hierarchy_vals) & hierarchy_vals != "NA" & hierarchy_vals != ""
          ]
          if (is_add_or_apply) {
            d$path <- paste(hierarchy_vals, collapse = "\\\\ ")
          } else {
            d$path <- paste(hierarchy_vals, collapse = "\\\\\\\\ ")
            d$path <- gsub("\\(", "\\\\(", d$path)
            d$path <- gsub("\\)", "\\\\)", d$path)
          }
          return(d)
        }
      }
    )

  list.str_from_to <-
    all_path %>%
    plyr::dlply(
      "Old_New",
      function(d) {
        ft <- unique(d$from_to)
        if (setequal(ft, c("from", "to"))) {
          obj <- list(
            str_from = d[d$from_to == "from", "path"],
            str_to = d[d$from_to == "to", "path"]
          )
          class(obj) <- c("path_change", "list")
          return(obj)
        }
        if (setequal(ft, "unlink")) {
          obj <- list(
            highlight_ids = as.integer(d$highlight_id),
            tag_ids = as.integer(d$tag_id)
          )
          class(obj) <- c("unlink", "list")
          return(obj)
        }
        if (setequal(ft, "add") || setequal(ft, "apply")) {
          paths <- unique(d$path)
          if (length(paths) != 1L) {
            stop(sprintf(
              "mod-Excel Old_New=%s: '%s' rows must share the same path; found %d distinct paths.",
              unique(d$Old_New), ft, length(paths)
            ))
          }
          hids <- d$highlight_id[!is.na(d$highlight_id)]
          obj <- list(
            path = paths,
            highlight_ids = if (length(hids) == 0L) integer(0) else as.integer(hids)
          )
          class(obj) <- c(ft, "list")
          return(obj)
        }
        stop(sprintf(
          "mod-Excel Old_New=%s: unrecognised or mixed from_to values: %s. Expected one of: both {'from','to'} for path_change; 'unlink' only; 'add' only; 'apply' only.",
          unique(d$Old_New), paste(ft, collapse = ", ")
        ))
      }
    )

  list.str_from_to
}
