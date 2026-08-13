#' Build the per-highlight review table for the review pass.
#'
#' Materialises the tag hierarchy from \code{df.tag_table$path} (splitting
#' on \code{\\\\ ?}, tolerant of pre-existing malformed Japanese paths that
#' lack the space) and joins it to \code{df.highlights} and
#' \code{df.snippets} so every coded excerpt gets its tag path, split
#' hierarchy, character offsets, and snippet text on a single row.
#'
#' Tags whose first hierarchy segment starts with \code{"DEMOTED_"} are
#' filtered out of the analytical view; highlights previously assigned to
#' them appear in the result with \code{NA} in the hierarchy columns, so
#' they surface for re-tagging in the next iteration.
#'
#' @param df.tag_table Data frame of the \code{tag_table} table.
#' @param df.highlights Data frame of the \code{highlights} table.
#' @param df.snippets Data frame of the \code{snippets} table.
#'
#' @return Data frame of the review-pass CSV shape: one row per highlight,
#'   with the tag path split across ranks, plus offsets and snippet text.
#' @export
build_review_table <- function(df.tag_table, df.highlights, df.snippets) {
  df.tag_table.hieralchical <-
    df.tag_table %>%
    plyr::ddply(
      c("id", "path"),
      function(d) {
        hieralchical <- unlist(strsplit(d$path, "\\\\\\\\ ?"))
        if (substr(hieralchical[1], 1, 8) != "DEMOTED_") {
          return(data.frame(rank = seq_along(hieralchical), codes = hieralchical))
        }
      }
    ) %>%
    tidyr::pivot_wider(id_cols = c("id", "path"), names_from = "rank", values_from = "codes")

  df.highlights %>%
    dplyr::left_join(df.tag_table.hieralchical, by = c("tag_id" = "id")) %>%
    dplyr::left_join(df.snippets, by = c("highlight_id" = "id"))
}
