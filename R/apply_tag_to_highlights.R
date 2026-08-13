#' Attach an already-existing tag to highlights.
#'
#' Look up the tag id for \code{path} in \code{df.tag_table} (must already
#' exist exactly once) and append one row per requested \code{highlight_id}
#' to \code{df.highlights}, pointing at that tag id. \code{df.tag_table} is
#' passed through unchanged.
#'
#' Errors if \code{path} is not present in \code{df.tag_table} (use
#' \code{\link{add_tag_with_highlights}} in that case), if \code{path}
#' matches more than one row (codebook integrity issue -- resolve first),
#' on duplicate \code{highlight_ids} in the batch, or if any
#' \code{(highlight_id, tag_id)} pair being inserted already exists.
#' Errors leave both frames untouched.
#'
#' @inheritParams add_tag_with_highlights
#' @param highlight_ids Integer vector, length >= 1.
#'
#' @return List of length 2: unchanged \code{tag_table}, updated
#'   \code{highlights}.
#' @export
apply_tag_to_highlights <- function(
    path,
    highlight_ids,
    df.tag_table,
    df.highlights,
    colname.tag_path = list(id = "id", path = "path"),
    colname.tag_id = "tag_id",
    colname.highlight_id = "highlight_id"
) {
  stopifnot(is.character(path), length(path) == 1L, !is.na(path),
            length(highlight_ids) >= 1L)

  id_col <- colname.tag_path[["id"]]
  path_col <- colname.tag_path[["path"]]

  df.tag_table <- as.data.frame(df.tag_table)
  df.highlights <- as.data.frame(df.highlights)

  idx <- which(df.tag_table[[path_col]] == path)
  if (length(idx) == 0L) {
    stop(sprintf(
      "apply_tag_to_highlights: path not found in df.tag_table$%s: '%s'. Use add_tag_with_highlights() to create it first.",
      path_col, path
    ))
  }
  if (length(idx) > 1L) {
    stop(sprintf(
      "apply_tag_to_highlights: multiple rows in df.tag_table$%s match '%s' (tag_ids: %s). Codebook has a duplicate -- resolve before applying.",
      path_col, path, paste(df.tag_table[[id_col]][idx], collapse = ", ")
    ))
  }
  existing_id <- df.tag_table[[id_col]][idx]

  if (anyDuplicated(highlight_ids) > 0L) {
    stop(sprintf(
      "apply_tag_to_highlights: duplicate highlight_ids in batch: %s",
      paste(highlight_ids[duplicated(highlight_ids)], collapse = ", ")
    ))
  }

  key_have <- paste(df.highlights[[colname.highlight_id]],
                    df.highlights[[colname.tag_id]], sep = "|")
  key_new <- paste(highlight_ids, existing_id, sep = "|")
  dup <- intersect(key_new, key_have)
  if (length(dup) > 0L) {
    stop(sprintf(
      "apply_tag_to_highlights: (highlight_id, tag_id) pair(s) already present: %s",
      paste(dup, collapse = ", ")
    ))
  }

  new_hl_rows <- df.highlights[rep(NA_integer_, length(highlight_ids)), , drop = FALSE]
  new_hl_rows[[colname.highlight_id]] <- as.integer(highlight_ids)
  new_hl_rows[[colname.tag_id]] <- rep(existing_id, length(highlight_ids))
  df.highlights.updated <- rbind(df.highlights, new_hl_rows)

  list(df.tag_table, df.highlights.updated)
}
