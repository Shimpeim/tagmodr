#' Remove specific (highlight_id, tag_id) rows from highlights.
#'
#' Delete rows from \code{df.highlights} where the \code{(highlight_id, tag_id)}
#' pair matches a requested pair. \code{df.tag_table} is passed through
#' unchanged; this operation is highlight-scoped only and does not modify the
#' tag hierarchy.
#'
#' Errors if any requested pair is not present in \code{df.highlights}. No
#' partial modification on error.
#'
#' @param highlight_ids Integer vector.
#' @param tag_ids Integer vector, same length as \code{highlight_ids}.
#' @param df.tag_table Data frame of the \code{tag_table} table.
#' @param df.highlights Data frame of the \code{highlights} table.
#' @param colname.highlight_id Character. Column name of the highlight id in
#'   \code{df.highlights} (Taguette's \code{highlights} table calls this
#'   \code{highlight_id}).
#' @param colname.tag_id Character. Column name of the tag id in
#'   \code{df.highlights}.
#'
#' @return List of length 2: unchanged \code{tag_table}, updated
#'   \code{highlights}.
#' @export
unlink_tag_from_highlight <- function(
    highlight_ids,
    tag_ids,
    df.tag_table,
    df.highlights,
    colname.highlight_id = "highlight_id",
    colname.tag_id = "tag_id"
) {
  stopifnot(length(highlight_ids) == length(tag_ids),
            length(highlight_ids) >= 1)

  df.highlights <- as.data.frame(df.highlights)

  key_have <- paste(df.highlights[[colname.highlight_id]],
                    df.highlights[[colname.tag_id]], sep = "|")
  key_want <- paste(highlight_ids, tag_ids, sep = "|")

  missing <- setdiff(key_want, key_have)
  if (length(missing) > 0) {
    stop(sprintf(
      "unlink_tag_from_highlight: %d (highlight_id, tag_id) pair(s) not present in df.highlights: %s",
      length(missing), paste(missing, collapse = ", ")
    ))
  }

  hit <- key_have %in% key_want
  df.highlights.updated <- df.highlights[!hit, , drop = FALSE]

  list(df.tag_table, df.highlights.updated)
}
