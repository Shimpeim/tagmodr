#' Rename or merge a tag path.
#'
#' Dispatcher: if \code{str_to} already exists in \code{df.tag_table$path},
#' delegates to \code{\link{change_tag_merge}}; otherwise delegates to
#' \code{\link{change_tag}}.
#'
#' @param str_from Length-1 character. The tag path to rename or merge away.
#' @param str_to Length-1 character. The target tag path.
#' @param df.tag_table Data frame of the \code{tag_table} table
#'   (columns include \code{id} and \code{path}).
#' @param df.highlights Data frame of the \code{highlights} table
#'   (columns include \code{tag_id}).
#' @param colname.tag_path Named list with \code{id} and \code{path} column names.
#' @param colname.tag_id Character. Column name of the tag id in \code{df.highlights}.
#'
#' @return List of length 2: updated \code{tag_table}, updated \code{highlights}.
#' @export
tag_edit <- function(
    str_from,
    str_to,
    df.tag_table,
    df.highlights,
    colname.tag_path = list(id = "id", path = "path"),
    colname.tag_id = "tag_id"
) {
  if (length(str_to) == 0) {
    stop("tag_edit: str_to is empty")
  }
  target_hits <- length(
    df.tag_table[
      grep(
        sprintf("^%s$", str_to),
        df.tag_table[, colname.tag_path[["path"]]]
      ),
      colname.tag_path[["id"]]
    ]
  )
  if (target_hits == 0) {
    change_tag(
      str_from, str_to,
      df.tag_table = df.tag_table,
      df.highlights = df.highlights,
      colname.tag_path = colname.tag_path,
      colname.tag_id = colname.tag_id
    )
  } else {
    change_tag_merge(
      str_from, str_to,
      df.tag_table = df.tag_table,
      df.highlights = df.highlights,
      colname.tag_path = colname.tag_path,
      colname.tag_id = colname.tag_id
    )
  }
}

#' Anchored rename of a tag path.
#'
#' Rewrites \code{df.tag_table$path} for the row whose path exactly matches
#' \code{str_from}, replacing it with \code{str_to}. Uses an anchored regex
#' (\code{^str_from$}) so only exact matches are rewritten. Highlights are
#' not touched; they continue to point at the same \code{tag_id}, whose
#' \code{path} value has been rewritten.
#'
#' If \code{str_from} is not found, writes \code{check_tags_exist.csv}
#' to the current working directory and prints a warning (does not stop).
#'
#' @inheritParams tag_edit
#' @return List of length 2: updated \code{tag_table}, unchanged
#'   \code{highlights}.
#' @export
change_tag <- function(
    str_from,
    str_to,
    df.tag_table,
    df.highlights,
    colname.tag_path = list(id = "id", path = "path"),
    colname.tag_id = "tag_id"
) {
  if (is.na(str_to)) {
    stop("change_tag: str_to is NA")
  }

  df.tag_table.updated <- as.data.frame(df.tag_table)

  if (length(grep(sprintf("^%s$", str_from), df.tag_table[, colname.tag_path[["path"]]])) == 0) {
    readr::write_excel_csv(df.tag_table, "check_tags_exist.csv")
    warning(sprintf(
      "change_tag: '%s' (str_from) not found in df.tag_table$%s. See check_tags_exist.csv.",
      str_from, colname.tag_path[["path"]]
    ))
  }

  df.tag_table.updated[, colname.tag_path$path] <-
    gsub(
      sprintf("^%s$", str_from),
      str_to,
      df.tag_table[, colname.tag_path$path]
    )

  na_rows <- which(is.na(df.tag_table.updated[, colname.tag_path$path]))
  if (length(na_rows) > 0) {
    stop(sprintf(
      "change_tag: NA path introduced at row(s) %s",
      paste(na_rows, collapse = ", ")
    ))
  }
  list(df.tag_table.updated, df.highlights)
}

#' Merge a from-tag into an already-existing to-tag.
#'
#' Re-points every highlight with \code{tag_id == id_from} to
#' \code{tag_id == id_to}, and marks the from-tag's row as
#' \code{DEMOTED_<str_from>} so the tag drops out of subsequent review
#' passes but remains discoverable in the raw SQLite.
#'
#' Uses exact string equality on \code{path} (not \code{gsub}) and integer
#' equality on \code{tag_id}, so paths containing regex metacharacters
#' (\code{|}, \code{.}, \code{*}, \code{[}, etc.) are safe.
#'
#' Requires both \code{str_from} and \code{str_to} to appear as exactly one
#' row each in \code{df.tag_table$path}; stops with a clear error message
#' otherwise.
#'
#' @inheritParams tag_edit
#' @return List of length 2: updated \code{tag_table}, updated
#'   \code{highlights}.
#' @export
change_tag_merge <- function(
    str_from,
    str_to,
    df.tag_table,
    df.highlights,
    colname.tag_path = list(id = "id", path = "path"),
    colname.tag_id = "tag_id"
) {
  id_col <- colname.tag_path[["id"]]
  path_col <- colname.tag_path[["path"]]

  df.tag_table <- as.data.frame(df.tag_table)
  idx_from <- which(df.tag_table[, path_col] == str_from)
  idx_to <- which(df.tag_table[, path_col] == str_to)

  if (length(idx_from) == 0) {
    readr::write_excel_csv(df.tag_table, "check_tags_exist.csv")
    stop(sprintf(
      "change_tag_merge: str_from not found in df.tag_table$%s: '%s' (see check_tags_exist.csv)",
      path_col, str_from
    ))
  }
  if (length(idx_from) > 1) {
    stop(sprintf("change_tag_merge: multiple entries for str_from: '%s'", str_from))
  }
  if (length(idx_to) == 0) {
    stop(sprintf(
      "change_tag_merge: str_to not found in df.tag_table$%s: '%s'",
      path_col, str_to
    ))
  }
  if (length(idx_to) > 1) {
    stop(sprintf("change_tag_merge: multiple entries for str_to: '%s'", str_to))
  }

  id_from <- df.tag_table[idx_from, id_col]
  id_to <- df.tag_table[idx_to, id_col]

  df.highlights.updated <- as.data.frame(df.highlights)
  df.highlights.updated[
    df.highlights.updated[, colname.tag_id] == id_from,
    colname.tag_id
  ] <- id_to

  df.tag_table.updated <- df.tag_table
  df.tag_table.updated[idx_from, path_col] <- sprintf("DEMOTED_%s", str_from)

  list(df.tag_table.updated, df.highlights.updated)
}
