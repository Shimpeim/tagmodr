#' Apply a list of mod-Excel operations to a tag_table + highlights pair.
#'
#' Consumes the class-tagged operations list from
#' \code{\link{create_tagmod_list}} and applies each op to the running
#' \code{(tag_table, highlights)} pair. Ops are re-ordered by class before
#' the loop so intra-iteration references resolve correctly:
#' \enumerate{
#'   \item \code{path_change} first -- normalise the existing hierarchy.
#'   \item \code{add} -- new tag_ids generated against the post-path_change
#'         tag_table.
#'   \item \code{apply} -- can legitimately reference tags that were just
#'         added in the same iteration.
#'   \item \code{unlink} last -- its (highlight_id, tag_id) references must
#'         be stable when it runs.
#' }
#'
#' After the loop, checks for duplicate paths in the resulting
#' \code{tag_table}; stops with an error if any are present.
#'
#' @param ops Named list from \code{\link{create_tagmod_list}}.
#' @param df.tag_table Data frame of the \code{tag_table} table.
#' @param df.highlights Data frame of the \code{highlights} table.
#'
#' @return List of length 2: updated \code{tag_table}, updated
#'   \code{highlights}.
#' @export
apply_tagmod_ops <- function(ops, df.tag_table, df.highlights) {
  op_priority <- function(op) {
    if (inherits(op, "unlink")) 4L
    else if (inherits(op, "apply")) 3L
    else if (inherits(op, "add")) 2L
    else 1L
  }
  ops_ordered <- ops[order(vapply(ops, op_priority, integer(1)))]

  state <- list(df.tag_table, df.highlights)
  for (i in seq_along(ops_ordered)) {
    op <- ops_ordered[[i]]
    state <-
      if (inherits(op, "unlink")) {
        unlink_tag_from_highlight(
          highlight_ids = op$highlight_ids,
          tag_ids = op$tag_ids,
          df.tag_table = state[[1]],
          df.highlights = state[[2]]
        )
      } else if (inherits(op, "apply")) {
        apply_tag_to_highlights(
          path = op$path,
          highlight_ids = op$highlight_ids,
          df.tag_table = state[[1]],
          df.highlights = state[[2]]
        )
      } else if (inherits(op, "add")) {
        tryCatch(
          add_tag_with_highlights(
            path          = op$path,
            highlight_ids = op$highlight_ids,
            df.tag_table  = state[[1]],
            df.highlights = state[[2]]
          ),
          error = function(e) {
            warning(sprintf("add op (path='%s') skipped: %s",
                            op$path, conditionMessage(e)))
            state
          }
        )
      } else {
        tag_edit(
          str_from = op$str_from,
          str_to = op$str_to,
          df.tag_table = state[[1]],
          df.highlights = state[[2]]
        )
      }
  }

  dup_check <- state[[1]] %>%
    plyr::ddply(
      "path",
      function(d) {
        if (nrow(d) > 1 && length(unique(d$id)) > 1) {
          d$count <- seq_len(nrow(d))
          return(d)
        }
      }
    )
  if (nrow(dup_check) > 0) {
    stop("apply_tagmod_ops: duplicate tag paths detected after applying ops.")
  }

  state
}
