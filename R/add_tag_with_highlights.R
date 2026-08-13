#' Create a new tag, optionally attaching it to highlights.
#'
#' Append a new row to \code{df.tag_table} with a fresh \code{id} (next
#' integer over existing ids, or \code{1L} if the table is empty) and the
#' given \code{path}. Optionally append one row per requested \code{highlight_id}
#' to \code{df.highlights} pointing at the new tag id.
#'
#' Non-key columns of the new tag row (e.g. \code{project_id},
#' \code{description}) are inherited from existing rows using the modal
#' non-NA value of each column -- so downstream tools like Taguette (which
#' filters tags by \code{project_id}) see the new tag as belonging to the
#' project.
#'
#' Errors if \code{path} already exists in \code{df.tag_table} -- use
#' \code{\link{apply_tag_to_highlights}} in that case. Errors on duplicate
#' \code{highlight_ids} in the batch. Errors leave both frames untouched.
#'
#' @param path Length-1 character. The new tag path.
#' @param highlight_ids Integer vector (may be empty).
#' @param df.tag_table Data frame of the \code{tag_table} table.
#' @param df.highlights Data frame of the \code{highlights} table.
#' @param colname.tag_path Named list with \code{id} and \code{path} column names.
#' @param colname.tag_id Character. Tag-id column in \code{df.highlights}.
#' @param colname.highlight_id Character. Highlight-id column in \code{df.highlights}.
#'
#' @return List of length 2: updated \code{tag_table}, updated
#'   \code{highlights}.
#' @export
add_tag_with_highlights <- function(
    path,
    highlight_ids = integer(0),
    df.tag_table,
    df.highlights,
    colname.tag_path = list(id = "id", path = "path"),
    colname.tag_id = "tag_id",
    colname.highlight_id = "highlight_id"
) {
  stopifnot(is.character(path), length(path) == 1L, !is.na(path))

  id_col <- colname.tag_path[["id"]]
  path_col <- colname.tag_path[["path"]]

  df.tag_table <- as.data.frame(df.tag_table)
  df.highlights <- as.data.frame(df.highlights)

  if (any(df.tag_table[[path_col]] == path, na.rm = TRUE)) {
    stop(sprintf(
      "add_tag_with_highlights: path already exists in df.tag_table$%s: '%s'. Use apply_tag_to_highlights() to attach highlights to an existing tag.",
      path_col, path
    ))
  }

  if (length(highlight_ids) > 0L && anyDuplicated(highlight_ids) > 0L) {
    stop(sprintf(
      "add_tag_with_highlights: duplicate highlight_ids in batch: %s",
      paste(highlight_ids[duplicated(highlight_ids)], collapse = ", ")
    ))
  }

  existing_ids <- df.tag_table[[id_col]]
  new_id <-
    if (length(existing_ids) == 0L || all(is.na(existing_ids))) 1L
    else as.integer(max(existing_ids, na.rm = TRUE) + 1L)

  new_tag_row <- df.tag_table[NA_integer_, , drop = FALSE][1L, , drop = FALSE]
  new_tag_row[[id_col]] <- new_id
  new_tag_row[[path_col]] <- path
  other_cols <- setdiff(colnames(df.tag_table), c(id_col, path_col))
  if (length(other_cols) > 0L && nrow(df.tag_table) > 0L) {
    for (col in other_cols) {
      vals <- df.tag_table[[col]][!is.na(df.tag_table[[col]])]
      if (length(vals) > 0L) {
        tab <- table(vals)
        mode_val <- names(sort(tab, decreasing = TRUE))[1L]
        if (is.integer(df.tag_table[[col]])) mode_val <- as.integer(mode_val)
        else if (is.numeric(df.tag_table[[col]])) mode_val <- as.numeric(mode_val)
        new_tag_row[[col]] <- mode_val
      }
    }
  }
  df.tag_table.updated <- rbind(df.tag_table, new_tag_row)

  df.highlights.updated <-
    if (length(highlight_ids) > 0L) {
      key_have <- paste(df.highlights[[colname.highlight_id]],
                        df.highlights[[colname.tag_id]], sep = "|")
      key_new <- paste(highlight_ids, new_id, sep = "|")
      dup <- intersect(key_new, key_have)
      if (length(dup) > 0L) {
        stop(sprintf(
          "add_tag_with_highlights: (highlight_id, tag_id) pair(s) already exist: %s",
          paste(dup, collapse = ", ")
        ))
      }
      new_hl_rows <- df.highlights[rep(NA_integer_, length(highlight_ids)), , drop = FALSE]
      new_hl_rows[[colname.highlight_id]] <- as.integer(highlight_ids)
      new_hl_rows[[colname.tag_id]] <- rep(new_id, length(highlight_ids))
      rbind(df.highlights, new_hl_rows)
    } else {
      df.highlights
    }

  list(df.tag_table.updated, df.highlights.updated)
}
