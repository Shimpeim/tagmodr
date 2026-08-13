#' Normalise the tag-path separator in-place on a tag_table data frame.
#'
#' Canonicalises \code{df.tag_table$path} to the \code{Domain\\\\ Section\\\\
#' Key\\\\ Subkey} form:
#' \enumerate{
#'   \item Strip a trailing \code{\\\\} left over from a malformed path.
#'   \item Insert a space after \code{\\\\} when it sits between two Unicode
#'         letters/digits -- so both ASCII and Japanese segment boundaries
#'         get the space they need to split cleanly in
#'         \code{\link{build_review_table}}.
#' }
#'
#' The regex uses PCRE Unicode character classes (\code{\\p{L}}, \code{\\p{N}})
#' so non-ASCII paths (Japanese, etc.) are normalised the same way as ASCII.
#' The operation is idempotent: running it against an already-normal path is
#' a no-op.
#'
#' @param df.tag_table Data frame of the \code{tag_table} table.
#' @param path_col Character. Column name to normalise. Default \code{"path"}.
#' @param length.path Integer. How many iterations of the space-insertion
#'   regex to run. Idempotent for ASCII; a no-op for non-ASCII beyond the
#'   first iteration. Default \code{4L}.
#'
#' @return \code{df.tag_table} with the normalised \code{path} column.
#' @export
normalize_tag_paths <- function(df.tag_table, path_col = "path", length.path = 4L) {
  df.tag_table %>%
    plyr::ddply(
      "id",
      function(d) {
        for (i in seq_len(length.path)) {
          d[[path_col]] <-
            gsub(
              "(?<=[\\p{L}\\p{N}\\)])\\\\\\\\$",
              "\\1",
              d[[path_col]],
              perl = TRUE
            )
          d[[path_col]] <-
            gsub(
              "(?<=[\\p{L}\\p{N}\\)])\\\\\\\\(?=[\\p{L}\\p{N}\\(])",
              "\\1\\\\\\\\ \\2",
              d[[path_col]],
              perl = TRUE
            )
        }
        d
      }
    )
}
