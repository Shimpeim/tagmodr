# CLAUDE.md — tagmodr developer reference

## Package summary

`tagmodr` (v0.3.0) is an R package for iterative codebook development on
[Taguette](https://www.taguette.org/) qualitative-analysis projects.

**Core pipeline:** read Taguette SQLite → review table → mod-Excel operations →
updated SQLite for re-import.

**Tag Viewer (v0.3.0):** distance-based seriation of tags within/across strata,
with optional centroid horizontal alignment.

---

## File map

```
R/
  read_taguette_sqlite.R        read SQLite → named list of data frames
  normalize_tag_paths.R         canonicalise \\ separator (PCRE Unicode-safe)
  build_review_table.R          one row per highlight with tag hierarchy split
  create_tagmod_list.R          mod-Excel → class-tagged op list
  apply_tagmod_ops.R            apply op list to (tag_table, highlights)
  change_tag.R                  path_change: rename
  change_tag_merge.R            path_change: merge → DEMOTED_ prefix
  add_tag_with_highlights.R     add op
  apply_tag_to_highlights.R     apply op
  unlink_tag_from_highlight.R   unlink op
  compute_tag_clusters.R        Tag Viewer: seriation + centroid pull  [v0.3.0]
  launch_app.R                  launch Shiny app
  install_launcher.R            macOS double-click launcher
  tagmodr-package.R             package-level doc

inst/app/app.R                  single-file Shiny app (5 tabs as of v0.3.0)
tests/testthat/                 mutation tests + read/write round-trip
inst/extdata/                   synthetic example_project.sqlite3 fixture
```

---

## Core data contracts

### SQLite → R (`read_taguette_sqlite()`)

Returns a named list. The three tables the pipeline cares about:

| List element      | SQLite table    | Key columns                                                        |
|-------------------|-----------------|--------------------------------------------------------------------|
| `$tags`           | `tags`          | `id`, `project_id`, `path`, `description`                         |
| `$highlight_tags` | `highlight_tags`| `highlight_id`, `tag_id`                                          |
| `$highlights`     | `highlights`    | `id`, `document_id`, `start_offset`, `end_offset`, `snippet`      |

The naming mismatch (e.g. `$highlights` is used as `df.snippets` downstream) is
historical. The function arguments `df.tag_table`, `df.highlights`, `df.snippets`
map to `$tags`, `$highlight_tags`, `$highlights` respectively.

### Review table — output of `build_review_table()`

One row per highlight. Column set after the two left-joins:

```
highlight_id | tag_id | path | "1" | "2" | "3" | "4" |
document_id | start_offset | end_offset | snippet
```

`"1"`…`"4"` are the `path` split by `\\ ?` across hierarchy ranks via
`pivot_wider`. Tags whose first segment starts with `DEMOTED_` are filtered
before the pivot; their highlights appear in the result with `NA` in all rank
columns.

### State after `apply_tagmod_ops()`

Returns `list(tag_table, highlight_tags)` — the two updated data frames.
Op execution order: `path_change → add → apply → unlink` (class-sorted
before the loop, regardless of `Old_New` numbering).

Error semantics: **`add` ops are non-fatal** — each is wrapped in `tryCatch`;
if `add_tag_with_highlights()` throws (e.g. path already exists), that op
emits a `warning()` and is skipped, leaving `state` unchanged; the batch
continues. All other op types (`path_change`, `apply`, `unlink`) abort the
entire batch on error and set `applied_state(NULL)` in the Shiny app. The
Apply notification collects and displays all per-op skip warnings via
`withCallingHandlers`.

---

## Tag Viewer — algorithm specification

### Function signature

```r
compute_tag_clusters(df, col_vars, row_vars = character(0),
                     dist_col         = "path", # any character column of df
                     centroid_strata  = NULL,   # named list, e.g. list("1" = "Character")
                     centroid_weight  = 0.50,   # w  ∈ [0, 1]
                     neighbourhood_r  = 0.50,   # τ  ∈ [0, 1]
                     pull_sharpness   = 5,       # α  ∈ [1, 50]
                     path_part        = c("full", "leaf"))  # only when dist_col = "path"
```

`df` is the output of `build_review_table()`. **No rows are aggregated or
dropped.** `highlight_id` and `document_id` are preserved on every row through
to the return value.

- `col_vars`: column names in `df` whose unique value combinations become
  **columns** in `$wide` (side-by-side strata).
- `row_vars`: column names whose unique value combinations become **row
  sections** within each column. When empty (default), `$wide` has no separator
  rows — same behaviour as the original `strat_cols` parameter.
- `centroid_strata` is keyed by `col_vars` only (not `row_vars`). When
  `row_vars` is non-empty, the centroid pull operates independently within each
  row-key group.

---

### Step A — unique tag × stratum table

```r
col_key   <- apply(df[col_vars], 1, paste, collapse = "\x1f")
row_key   <- if (length(row_vars) > 0) apply(df[row_vars], 1, paste, collapse = "\x1f")
             else rep("", nrow(df))
strat_key <- paste(col_key, row_key, sep = "\x1e")   # record separator (\x1e) between col_key and row_key

extra_col   <- if (dist_col != "path") dist_col else character(0)
ut_cols     <- unique(c("path", col_vars, row_vars, extra_col,
                        "col_key", "row_key", "strat_key"))
unique_tags <- unique(df[, ut_cols, drop = FALSE])
unique_tags <- unique_tags[!is.na(unique_tags$path), ]
# Deduplication guard: when dist_col has multiple values per tag (e.g. snippet),
# unique() over ut_cols produces multiple rows per (path, strat_key). Collapse
# to one row so centroid-pull distances operate over tags, not dist_col instances,
# and the final merge back to df does not duplicate rows.
unique_tags <- unique_tags[!duplicated(unique_tags[, c("path", "strat_key")]), ]
```

`col_key` is the interaction of `col_vars` values (joined by `\x1f`).
`row_key` is the interaction of `row_vars` values (joined by `\x1f`), or `""`
when `row_vars` is empty.
`strat_key` combines both with `\x1e` (ASCII record separator) so the boundary
between col and row parts is unambiguous.

The `string` column used for distance computation:

- If `dist_col = "path"` and `path_part = "leaf"`: last `\\ `-delimited segment of each `path`.
- If `dist_col = "path"` and `path_part = "full"`: `string <- path`.
- If `dist_col != "path"`: `string <- as.character(unique_tags[[dist_col]])`; `NA` → `""`.

All distance computations in Steps B–D use `string`; `path` is retained for display only.

---

### Step B — global distance matrix

```r
strings <- unique(unique_tags$string)          # P unique strings
dmat    <- adist(strings, strings)             # P × P integer Levenshtein matrix
nc      <- outer(nchar(strings), nchar(strings), pmax)
nc      <- pmax(nc, 1L)                        # guard: 0/0 for two empty strings
nmat    <- dmat / nc                           # P × P normalised ∈ [0, 1]
```

`adist()` is base R; no external package dependency.  
`outer(nchar(a), nchar(b), pmax)[i,j] = max(nchar(a[i]), nchar(b[j]))` — the
standard normaliser for edit distance.  
`nmat` is computed once and indexed by position for all downstream sub-matrix
extractions.

---

### Step C — across-stratum seriation

```r
hc_all       <- hclust(as.dist(nmat), method = "average")
# hc_all$order: length-P vector, the dendrogram leaf sequence from left to right
order_across <- order(hc_all$order)     # position of each string in the leaf sequence

leaf_seq     <- hc_all$order            # display order: leaf_seq[1] is leftmost
dist_prev    <- c(NA, diag(nmat[leaf_seq[-1], leaf_seq[-length(leaf_seq)]]))
# dist_prev[i] = nmat[leaf_seq[i], leaf_seq[i-1]]; NA at position 1
```

Join `order_across` and `dist_to_prev_across` back to `unique_tags` on `string`.

---

### Step D — within-stratum seriation with optional centroid pull

Resolve `centroid_col_key` from `centroid_strata` (named list keyed by
`col_vars`). Split `unique_tags` by `strat_key`. Pre-compute
`O_centroid_norm` per unique `row_key`:

```r
for (rk in unique(unique_tags$row_key)) {
  centroid_sk <- paste(centroid_col_key, rk, sep = "\x1e")
  if (centroid_sk %in% groups) ...   # compute O_centroid_norm for this rk
}
```

When `row_vars` is empty there is only one `row_key` (`""`), so the loop
runs once and the centroid is global — same as the original v0.3.0 behaviour.

For each group g (identified by `strat_key`, with `col_key = ck` and
`row_key = rk`) with tags at positions `idx_g` in `nmat`:

#### Case 1 — n = 1

```r
order_within        <- 1L
dist_to_prev_within <- NA_real_
```

No `hclust` call.

#### Case 2 — n ≥ 2, no centroid set, or this group is the centroid

```r
nmat_g   <- nmat[idx_g, idx_g]
hc_g     <- hclust(as.dist(nmat_g), method = "average")
leaf_g   <- hc_g$order                           # display sequence within group
O_raw    <- order(hc_g$order)                    # position of each tag
O_norm   <- (O_raw - 1) / max(O_raw - 1, 1)     # normalise to [0, 1]

# dist_to_prev_within:
d_prev_g <- c(NA, diag(nmat_g[leaf_g[-1], leaf_g[-length(leaf_g)]]))
# assign back by leaf_g position
```

When this group is the centroid, also store `O_centroid_norm <- O_norm` and
`idx_C` for use in Case 3 below.

#### Case 3 — n ≥ 2, non-centroid group, centroid is set

```r
# 1. Pure within-stratum order (same as Case 2) → O_norm, leaf_g
nmat_g <- nmat[idx_g, idx_g]
hc_g   <- hclust(as.dist(nmat_g), method = "average")
O_raw  <- order(hc_g$order)
O_norm <- (O_raw - 1) / max(O_raw - 1, 1)

# 2. Cross-distance matrix  (m × K,  non-centroid tags × centroid tags)
D_cross <- nmat[idx_g, idx_C]

# 3. Masked softmax pull
W <- exp(-pull_sharpness * D_cross) * (D_cross <= neighbourhood_r)

# Fallback: if any row is all-zero (no centroid tag within τ), use unmasked weights
zero_rows      <- rowSums(W) == 0
W[zero_rows, ] <- exp(-pull_sharpness * D_cross[zero_rows, , drop = FALSE])

W  <- W / rowSums(W)                              # row-normalise → probabilities
H  <- as.vector(W %*% O_centroid_norm)            # m-vector ∈ [0, 1]

# 4. Blended score and final order
O_blend  <- (1 - centroid_weight) * O_norm + centroid_weight * H
O_raw    <- rank(O_blend, ties.method = "first")  # final within-group positions
O_norm   <- (O_raw - 1) / max(O_raw - 1, 1)

# dist_to_prev_within — recomputed on the blended display sequence:
leaf_g   <- order(O_blend)                        # original indices sorted by blend
d_prev_g <- c(NA, diag(nmat_g[leaf_g[-1], leaf_g[-length(leaf_g)]]))
```

**Intuition:** `W %*% O_centroid_norm` is a weighted average of centroid display
positions, where the weights concentrate (via `exp(-α·d)`) on centroid tags near
the current non-centroid tag, and the mask `(d ≤ τ)` excludes distant anchors.
The fallback prevents the mask from leaving any tag with zero influence.

Join `order_within` and `dist_to_prev_within` to `unique_tags`.

---

### Return value

A named list of two data frames.

**`$annotated`** — the original `df` with seven columns left-joined on
`(path, strat_key)`:

```
… original columns … | col_key             (character, \x1f-joined col_vars values)
                      | row_key             (character, \x1f-joined row_vars values, "" when empty)
                      | strat_key           (character, paste(col_key, row_key, sep="\x1e"))
                      | order_within        (integer)
                      | dist_to_prev_within (numeric ∈ [0,1], NA at group start)
                      | order_across        (integer)
                      | dist_to_prev_across (numeric ∈ [0,1], NA at position 1)
```

Still one row per highlight. `highlight_id` and `document_id` are untouched.

**`$wide`** when `row_vars` is empty:

```
pos (int) | <centroid_col_key> | <col_key_B> | <col_key_C> | …
        1 | "Tag A1"           | "Tag B1"     | "Tag C1"
        2 | "Tag A2"           | "Tag B2"     | NA
        3 | "Tag A3"           | NA           | NA
```

**`$wide`** when `row_vars` is non-empty (separator rows mark each section):

```
is_separator | row_label | pos | <centroid_col_key> | <col_key_B> | …
TRUE         | "Doc1"    | NA  | NA                 | NA
FALSE        | NA        | 1   | "Tag A1"           | "Tag B1"
FALSE        | NA        | 2   | "Tag A2"           | NA
TRUE         | "Doc2"    | NA  | NA                 | NA
FALSE        | NA        | 1   | "Tag C1"           | "Tag D1"
```

- `is_separator` is hidden in the Shiny DT but accessible via JS `rowCallback`
  for row styling.
- `row_label` holds the pretty-printed `row_key` (`\x1f` → ` × `), or `NA`
  in data rows. The click handler reconstructs `row_key` from `row_label` by
  reversing the substitution.
- Column order: centroid col_key leftmost (if set), then remaining col_keys
  alphabetically.
- Cells hold full `path` strings or `NA`.

Construction sketch:

```r
cols <- lapply(groups, function(g) {
  paths_ordered <- g$path[order(g$order_within)]   # display sequence
  length(paths_ordered) <- max_m                   # pad with NA
  paths_ordered
})
wide <- as.data.frame(c(list(pos = seq_len(max_m)), cols))
```

---

### Edge cases

| Situation | Handling |
|---|---|
| Empty string after leaf extraction | `pmax(nc, 1L)` prevents 0/0 |
| All `D_cross > τ` for a row | `W` falls back to unmasked `exp` weights |
| `centroid_weight = 0` | Skip pull entirely; all groups use Case 2 |
| Centroid group has n = 1 | `O_centroid_norm = 0.5`; all non-centroid tags pulled to midpoint |
| Only one unique `strat_key` | Within- and across-stratum orders are identical; `$wide` has one data column |
| `strat_cols` produces groups with no common tag path | Cross-distance matrix is well-defined; no special handling needed |

---

## Shiny app — Tab 5 specification

### Sidebar controls (shown after SQLite is loaded)

```
strat_vars       selectizeInput  multiple = TRUE
                                 choices  = colnames(review_tbl())
                                 (renamed from strat_cols in v0.3.1)
<per-variable>   radioButtons    one per selected variable in strat_vars
  role_<var>                     choices = c("Column"="col", "Row"="row")
                                 default "col"; id = "role_" + sanitised var name
dist_col         selectInput     "Distance on:"
                                 choices = colnames(review_tbl())
                                 default "path"
path_part        radioButtons    c("full", "leaf"), default "full"
                                 conditionalPanel: shown only when dist_col == "path"
centroid_strata  selectInput     c("(none)", unique col_key values)
                                 keyed by col_vars only (not row_vars)
                                 NULL when "(none)" selected
centroid_weight  sliderInput     0.00–1.00 step 0.05   ┐
neighbourhood_r  sliderInput     0.00–1.00 step 0.05   │ shown only when
pull_sharpness   sliderInput     1–50      step 1      ┘ centroid_strata ≠ NULL
[Compute]        actionButton    triggers compute_tag_clusters(); decoupled
                                 from input reactives to avoid recomputation
                                 on every slider move
[below hr]
wide_display_col selectInput     "Cell content (side-by-side):"
                                 choices = colnames(review_tbl())
                                 default "path"
                                 does NOT trigger recompute; substitutes display
                                 values in $wide without rerunning seriation
display_cols     selectizeInput  "Show columns:" multiple = TRUE
                                 choices = colnames(review_tbl())
                                 default = all columns
                                 filters columns in highlight_detail_dt and
                                 across_dt; does NOT trigger recompute
```

Derived reactives: `col_vars_r()` = variables whose role is "col";
`row_vars_r()` = variables whose role is "row"; `col_keys_r()` = unique
col_key combinations computed from `col_vars_r()` (feeds centroid selectInput).

### Main panel sub-tabs

**"Side-by-side (within)"**
- `DT::renderDT` of `$wide`
- Cells default to path strings; `NA` → empty cell
- `wide_display_col` sidebar selector substitutes display values in `$wide`
  without rerunning seriation: path values are replaced by the chosen column's
  values via a lookup dict keyed on `paste0(path, "\x02", strat_key)`
- Click handler reads the original path by row/column index from the unsubstituted
  `$wide` (not from `click$value`, which would give the display text instead)
- Reconstructs `strat_key` from column name (`gsub(" × ", "\x1f", col_label)`)
  and nearest preceding separator row for `row_key`; filters `$annotated` →
  renders highlight detail DT below using columns selected by `display_cols`

**"Across strata"**
- `DT::renderDT` of `$annotated` sorted by `order_across`
- Columns displayed: controlled by `display_cols` sidebar selector (default: all)
- Always includes `order_across` and `dist_to_prev_across` for colour formatting
- `dist_to_prev_across` → `DT::formatStyle(background = styleColorBar(...))`
  green (near 0) to red (near 1)
- DT column filters for `strat_key` and `document_id`

---

## Implementation invariants

- **Exact-match semantics.** All tag-path lookups use string equality (`==`),
  never regex. Tag paths may contain regex metacharacters (`|`, `.`, `*`, `+`,
  `[`, etc.).
- **Unicode / Japanese safety.** `normalize_tag_paths()` uses PCRE Unicode
  character classes (`\p{L}`, `\p{N}`) so Japanese and ASCII paths normalise
  identically. `adist()` in `compute_tag_clusters()` treats each Unicode
  codepoint as one edit operation, which is correct for character-level
  similarity on Japanese tag strings.
- **Op ordering.** `apply_tagmod_ops()` always applies `path_change` before
  `add` before `apply` before `unlink`, regardless of `Old_New` numbering.
- **DEMOTED_ convention.** Merge ops rewrite the from-path with a `DEMOTED_`
  prefix rather than deleting the row. `build_review_table()` filters these out.
  Highlights remain traceable in the raw SQLite.
- **No hard deletes.** The package never physically removes rows from `tags` or
  `highlight_tags`. Soft-delete via `DEMOTED_` prefix rename is the only
  supported removal pathway.
- **`compute_tag_clusters()` is read-only.** It never mutates `df` or the
  SQLite state. It may be called multiple times with different parameters
  without side effects.
- **`$wide` stores `path`, not `string`.** Even when `path_part = "leaf"` or
  `dist_col != "path"` was used to compute distances, cells in `$wide` hold the
  full `path` value. The `wide_display_col` sidebar selector substitutes display
  text in the Shiny layer without mutating `$wide`; the click handler always
  reads paths from `$wide` by row/column index to identify the tag.
