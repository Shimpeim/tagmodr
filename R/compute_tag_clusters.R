#' Compute tag seriation and optional centroid pull for the Tag Viewer.
#'
#' Orders tags within and across strata using hierarchical clustering
#' (\code{hclust}, average linkage) on normalised Levenshtein distances.
#' Optionally realigns non-centroid column strata horizontally toward a
#' designated centroid column via a masked-softmax pull kernel.
#'
#' No rows are aggregated or dropped: \code{highlight_id} and
#' \code{document_id} are preserved on every row throughout.
#'
#' @param df Data frame — output of \code{\link{build_review_table}}.
#'   One row per highlight.
#' @param col_vars Character vector of column names in \code{df} whose unique
#'   value combinations define the side-by-side columns in \code{$wide}.
#' @param row_vars Character vector (default \code{character(0)}) of column
#'   names in \code{df} whose unique value combinations create labelled row
#'   sections within each column of \code{$wide}. When empty, \code{$wide}
#'   has no separator rows, matching the original single-\code{strat_cols}
#'   behaviour.
#' @param centroid_strata Named list or \code{NULL}. Identifies one
#'   \code{col_vars} combination as the centroid column, e.g.
#'   \code{list("1" = "Character")}. Names must match elements of
#'   \code{col_vars}. \code{NULL} (default) disables centroid pull. When
#'   \code{row_vars} is non-empty the pull operates independently within each
#'   row-key group, using that group's centroid column as its anchor.
#' @param centroid_weight Numeric in \code{[0, 1]}. Global blend weight
#'   \eqn{w}: \code{0} = pure within-column order; \code{1} = full
#'   horizontal alignment to centroid. Default \code{0.5}.
#' @param neighbourhood_r Numeric in \code{[0, 1]}. Distance threshold
#'   \eqn{\tau}: only centroid tags whose normalised Levenshtein distance to
#'   the query tag is \code{<= neighbourhood_r} act as pull anchors. Tags
#'   with no centroid anchor within \eqn{\tau} fall back to unmasked soft
#'   pull over all centroid tags. Default \code{0.5}.
#' @param pull_sharpness Numeric \code{>= 1}. Softmax temperature \eqn{\alpha}
#'   within the neighbourhood: \code{1} spreads weight evenly across near
#'   anchors; \code{50} concentrates weight on the single nearest anchor.
#'   Default \code{5}.
#' @param dist_col Name of the column in \code{df} whose string values are
#'   used for Levenshtein distance computation. Default \code{"path"}.
#'   Any character column of the review table is accepted (e.g. \code{"1"},
#'   \code{"snippet"}). When \code{dist_col != "path"}, \code{path_part} is
#'   ignored and raw cell values are used as-is; \code{NA} values are treated
#'   as empty strings.
#' @param path_part One of \code{"full"} or \code{"leaf"}.  Applies only when
#'   \code{dist_col = "path"}: \code{"full"} uses the complete path string;
#'   \code{"leaf"} uses only the last \code{\\\\ }-delimited segment.
#'   Default \code{"full"}.
#'
#' @return A named list with two elements:
#' \describe{
#'   \item{\code{$annotated}}{The original \code{df} with seven extra columns:
#'     \code{col_key} (paste of \code{col_vars} values, \code{\\x1f}-joined),
#'     \code{row_key} (paste of \code{row_vars} values, or \code{""}),
#'     \code{strat_key} (\code{paste(col_key, row_key, sep = "\\x1e")}),
#'     \code{order_within} (integer position within stratum),
#'     \code{dist_to_prev_within} (normalised Levenshtein to tag immediately
#'     above in within-stratum display order; \code{NA} at group start),
#'     \code{order_across} (integer position in the across-stratum leaf
#'     sequence), \code{dist_to_prev_across} (distance to preceding tag in
#'     across-stratum order; \code{NA} at position 1).
#'     One row per highlight throughout.}
#'   \item{\code{$wide}}{Wide data frame for side-by-side display.
#'     When \code{row_vars} is empty: \code{pos} (integer 1..max_m) followed
#'     by one character column per unique \code{col_key}, centroid leftmost
#'     when set, then alphabetical.
#'     When \code{row_vars} is non-empty: three structural columns
#'     (\code{is_separator} logical, \code{row_label} character,
#'     \code{pos} integer) followed by the same tag columns; separator rows
#'     (\code{is_separator = TRUE}) carry the pretty-printed row-key in
#'     \code{row_label} and \code{NA} in all other cells.
#'     Column names use \code{" × "} as the separator between values.}
#' }
#' @export
compute_tag_clusters <- function(df, col_vars, row_vars = character(0),
                                 dist_col         = "path",
                                 centroid_strata  = NULL,
                                 centroid_weight  = 0.50,
                                 neighbourhood_r  = 0.50,
                                 pull_sharpness   = 5,
                                 path_part        = c("full", "leaf")) {
  path_part <- match.arg(path_part)

  # ── Step A: build col_key / row_key / strat_key ─────────────────────────────
  col_df  <- as.data.frame(df[, col_vars, drop = FALSE])
  col_key <- apply(col_df, 1L, paste, collapse = "\x1f")

  has_rows <- length(row_vars) > 0L
  if (has_rows) {
    row_df  <- as.data.frame(df[, row_vars, drop = FALSE])
    row_key <- apply(row_df, 1L, paste, collapse = "\x1f")
  } else {
    row_key <- rep("", nrow(df))
  }

  strat_key <- paste(col_key, row_key, sep = "\x1e")

  df$col_key   <- col_key
  df$row_key   <- row_key
  df$strat_key <- strat_key

  extra_col   <- if (dist_col != "path") dist_col else character(0)
  ut_cols     <- unique(c("path", col_vars, row_vars, extra_col,
                          "col_key", "row_key", "strat_key"))
  unique_tags <- unique(df[, ut_cols, drop = FALSE])
  unique_tags <- unique_tags[!is.na(unique_tags$path), , drop = FALSE]
  # Guarantee one row per (path, strat_key). When dist_col has multiple values
  # per tag (e.g. snippet), the unique() above would produce multiple rows and
  # the centroid-pull distances would operate over dist_col instances rather
  # than over paths, and the final merge back to df would duplicate rows.
  unique_tags <- unique_tags[
    !duplicated(unique_tags[, c("path", "strat_key")]), , drop = FALSE
  ]
  rownames(unique_tags) <- NULL

  if (dist_col == "path") {
    if (path_part == "leaf") {
      unique_tags$string <- vapply(
        strsplit(unique_tags$path, "\\\\ "),
        function(x) x[length(x)],
        character(1L)
      )
    } else {
      unique_tags$string <- unique_tags$path
    }
  } else {
    vals <- as.character(unique_tags[[dist_col]])
    vals[is.na(vals)] <- ""
    unique_tags$string <- vals
  }

  # ── Step B: global normalised Levenshtein distance matrix ───────────────────
  all_strings <- unique(unique_tags$string)
  P           <- length(all_strings)
  if (P == 0L) stop("compute_tag_clusters: no non-NA tag paths found in df.")

  dmat <- adist(all_strings, all_strings)
  nc   <- outer(nchar(all_strings), nchar(all_strings), pmax)
  nc   <- pmax(nc, 1L)
  nmat <- dmat / nc

  str_idx <- match(unique_tags$string, all_strings)

  # ── Step C: across-stratum seriation ────────────────────────────────────────
  if (P == 1L) {
    order_across_vec     <- 1L
    dist_prev_across_vec <- NA_real_
  } else {
    hc_all   <- hclust(as.dist(nmat), method = "average")
    leaf_all <- hc_all$order
    order_across_vec <- order(leaf_all)

    d_prev_a <- rep(NA_real_, P)
    for (i in seq(2L, P)) {
      d_prev_a[leaf_all[i]] <- nmat[leaf_all[i], leaf_all[i - 1L]]
    }
    dist_prev_across_vec <- d_prev_a
  }

  unique_tags$order_across        <- order_across_vec[str_idx]
  unique_tags$dist_to_prev_across <- dist_prev_across_vec[str_idx]

  # ── Step D: within-stratum seriation with optional centroid pull ─────────────
  # Resolve centroid col_key from centroid_strata (names must match col_vars)
  centroid_col_key <- NULL
  if (!is.null(centroid_strata)) {
    ck_parts <- vapply(col_vars, function(col) {
      v <- centroid_strata[[col]]
      if (is.null(v)) NA_character_ else as.character(v)
    }, character(1L))
    centroid_col_key <- paste(ck_parts, collapse = "\x1f")
  }

  groups <- split(unique_tags, unique_tags$strat_key, drop = TRUE)

  # Pre-compute O_centroid_norm per row_key (reused across non-centroid groups)
  centroid_by_row_key <- list()
  if (!is.null(centroid_col_key)) {
    all_row_keys <- unique(unique_tags$row_key)
    for (rk in all_row_keys) {
      centroid_sk <- paste(centroid_col_key, rk, sep = "\x1e")
      if (centroid_sk %in% names(groups)) {
        g_c   <- groups[[centroid_sk]]
        idx_C <- match(g_c$string, all_strings)
        K     <- length(idx_C)
        if (K == 1L) {
          O_centroid_norm <- 0.5
        } else {
          nmat_c  <- nmat[idx_C, idx_C, drop = FALSE]
          hc_c    <- hclust(as.dist(nmat_c), method = "average")
          O_raw_c <- order(hc_c$order)
          O_centroid_norm <- (O_raw_c - 1) / max(O_raw_c - 1, 1)
        }
        centroid_by_row_key[[rk]] <- list(O_centroid_norm = O_centroid_norm,
                                          idx_C = idx_C)
      }
    }
  }

  # Inner helper: order one stratum group
  .order_group <- function(idx_g, rk, ck) {
    m <- length(idx_g)
    if (m == 1L) {
      return(list(order_within        = 1L,
                  dist_to_prev_within = NA_real_))
    }

    nmat_g <- nmat[idx_g, idx_g, drop = FALSE]
    hc_g   <- hclust(as.dist(nmat_g), method = "average")
    O_raw  <- order(hc_g$order)
    O_norm <- (O_raw - 1) / max(O_raw - 1, 1)
    leaf_g <- hc_g$order

    is_centroid <- !is.null(centroid_col_key) && identical(ck, centroid_col_key)
    cent_info   <- centroid_by_row_key[[rk]]
    has_pull    <- !is.null(centroid_col_key) && !is_centroid &&
                   !is.null(cent_info) && centroid_weight > 0

    if (has_pull) {
      D_cross   <- nmat[idx_g, cent_info$idx_C, drop = FALSE]
      W         <- exp(-pull_sharpness * D_cross) * (D_cross <= neighbourhood_r)
      zero_rows <- rowSums(W) == 0
      if (any(zero_rows)) {
        W[zero_rows, ] <-
          exp(-pull_sharpness * D_cross[zero_rows, , drop = FALSE])
      }
      W       <- W / rowSums(W)
      H       <- as.vector(W %*% cent_info$O_centroid_norm)
      O_blend <- (1 - centroid_weight) * O_norm + centroid_weight * H
      O_raw   <- rank(O_blend, ties.method = "first")
      leaf_g  <- order(O_blend)
    }

    d_prev_g <- rep(NA_real_, m)
    for (i in seq(2L, m)) {
      d_prev_g[leaf_g[i]] <- nmat_g[leaf_g[i], leaf_g[i - 1L]]
    }

    list(order_within        = O_raw,
         dist_to_prev_within = d_prev_g)
  }

  groups_out <- lapply(names(groups), function(sk) {
    g     <- groups[[sk]]
    idx_g <- match(g$string, all_strings)
    rk    <- g$row_key[1L]
    ck    <- g$col_key[1L]
    res   <- .order_group(idx_g, rk, ck)
    g$order_within        <- res$order_within
    g$dist_to_prev_within <- res$dist_to_prev_within
    g
  })

  unique_tags_out <- do.call(rbind, groups_out)
  rownames(unique_tags_out) <- NULL

  # ── Join order columns back to df ───────────────────────────────────────────
  join_cols <- c("path", "strat_key",
                 "order_within", "dist_to_prev_within",
                 "order_across",  "dist_to_prev_across")
  annotated <- merge(
    df,
    unique_tags_out[, join_cols],
    by     = c("path", "strat_key"),
    all.x  = TRUE,
    sort   = FALSE
  )

  # ── Build $wide ─────────────────────────────────────────────────────────────
  all_col_keys <- sort(unique(unique_tags_out$col_key))
  if (!is.null(centroid_col_key) && centroid_col_key %in% all_col_keys) {
    all_col_keys <- c(centroid_col_key, setdiff(all_col_keys, centroid_col_key))
  }
  col_labels <- gsub("\x1f", " × ", all_col_keys)

  if (!has_rows) {
    # Simple case: one block, one column per col_key (same as v0.3.0 behaviour)
    max_m <- max(vapply(groups, nrow, integer(1L)))

    wide_cols <- setNames(
      lapply(all_col_keys, function(ck) {
        g     <- unique_tags_out[unique_tags_out$col_key == ck, , drop = FALSE]
        g     <- g[order(g$order_within), , drop = FALSE]
        paths <- g$path
        length(paths) <- max_m
        paths
      }),
      col_labels
    )

    wide <- as.data.frame(
      c(list(pos = seq_len(max_m)), wide_cols),
      stringsAsFactors = FALSE,
      check.names      = FALSE
    )
  } else {
    # Row-sectioned case: separator row per row_key, then data rows
    all_row_keys <- sort(unique(unique_tags_out$row_key))

    parts <- lapply(all_row_keys, function(rk) {
      tags_rk  <- unique_tags_out[unique_tags_out$row_key == rk, , drop = FALSE]
      max_m_rk <- 0L
      for (ck in all_col_keys) {
        max_m_rk <- max(max_m_rk, sum(tags_rk$col_key == ck))
      }
      if (max_m_rk == 0L) max_m_rk <- 1L

      pretty_rk <- gsub("\x1f", " × ", rk)

      sep_row <- as.data.frame(
        c(list(is_separator = TRUE,
               row_label    = pretty_rk,
               pos          = NA_integer_),
          setNames(rep(list(NA_character_), length(all_col_keys)), col_labels)),
        stringsAsFactors = FALSE, check.names = FALSE
      )

      data_rows <- as.data.frame(
        c(list(
            is_separator = rep(FALSE, max_m_rk),
            row_label    = rep(NA_character_, max_m_rk),
            pos          = seq_len(max_m_rk)
          ),
          setNames(
            lapply(all_col_keys, function(ck) {
              g     <- tags_rk[tags_rk$col_key == ck, , drop = FALSE]
              g     <- g[order(g$order_within), , drop = FALSE]
              paths <- g$path
              length(paths) <- max_m_rk
              paths
            }),
            col_labels
          )
        ),
        stringsAsFactors = FALSE, check.names = FALSE
      )

      rbind(sep_row, data_rows)
    })

    wide <- do.call(rbind, parts)
    rownames(wide) <- NULL
  }

  list(annotated = annotated, wide = wide)
}
