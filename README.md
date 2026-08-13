# tagmodr

Iterative codebook development for [Taguette](https://www.taguette.org/) qualitative-analysis projects, in R.

## What it does

Read a Taguette SQLite export, materialise the tag hierarchy into a per-highlight review table, apply user-authored **rename / merge / unlink / add / apply** operations from an Excel workbook, and write a fresh SQLite for re-import.

The pipeline exists because Taguette's UI is optimised for coding individual documents, not for **restructuring** an already-large tag hierarchy — renaming groups of tags, merging near-duplicates, or promoting a code up the hierarchy. Doing that inside the UI is slow and error-prone; doing it in Excel with an R replay pass is faster and auditable.

## Install

```r
# install.packages("remotes")
remotes::install_github("Shimpeim/tagmodr")
```

## Interactive UI

There is a Shiny app that walks the two-pass workflow end-to-end:

```r
tagmodr::launch_app()
```

The app steps: upload SQLite → preview + download review CSV → upload the
edited mod-Excel → preview the parsed operations → apply → download the
updated SQLite for re-import into Taguette. Requires `shiny` and `DT`
(Suggests).

### macOS: double-clickable launcher

To install a Desktop launcher that starts the app on double-click:

```r
tagmodr::install_launcher()
```

This copies `tagmodr.command` to your Desktop and marks it executable.
The launcher self-installs `tagmodr`, `shiny`, and `DT` on first run. See
`inst/launcher/README.md` for the macOS Gatekeeper first-launch note and
alternative install locations.

## The two-pass workflow

```
              +---------------------+
              |  Taguette (UI)      |
              |  coding session     |
              +----------+----------+
                         |  export
                         v
                  project.sqlite3
                         |
           +-------------+-------------+
           |                           |
   (a) REVIEW PASS               (b) MOD PASS
           |                           ^
           v                           |
 *_tag_review.csv                *_tag_review..mod.xlsx
           |                           ^
           |  (open in Excel,          |
           |   inspect hierarchy,      |
           |   annotate renames /      |
           |   merges / adds /         |
           |   unlinks in the          |
           |   Old_New + from_to       |
           |   columns)                |
           +---------------------------+
                         |
                         v
              project_updated.sqlite3
                         |
                         v
              (re-import to Taguette)
```

## Quick tour

```r
library(tagmodr)

# 1. Load a Taguette SQLite export as a named list of data frames.
sqlite <- read_taguette_sqlite("project.sqlite3")

# 2. (Review pass) Materialise the tag hierarchy into a per-highlight table.
review <- build_review_table(
  df.tag_table  = normalize_tag_paths(sqlite$tags),
  df.highlights = sqlite$highlight_tags,
  df.snippets   = sqlite$highlights
)
readr::write_excel_csv(review, "project_tag_review.csv")

# 3. User opens the CSV in Excel, saves as *..mod.xlsx, annotates Old_New /
#    from_to columns to describe rename / merge / add / apply / unlink ops.

# 4. (Mod pass) Parse the mod-Excel and apply the ops.
ops <- create_tagmod_list("project_tag_review..mod.xlsx", length.path = 4L)
state <- apply_tagmod_ops(
  ops,
  df.tag_table  = normalize_tag_paths(sqlite$tags),
  df.highlights = sqlite$highlight_tags
)
sqlite$tags           <- state[[1]]
sqlite$highlight_tags <- state[[2]]

# 5. Write a fresh SQLite that Taguette can re-import.
write_taguette_sqlite(sqlite, "project_updated.sqlite3")
```

## Taguette schema — what maps to what

Taguette's SQLite has three tables the pipeline cares about. Their column shapes differ from what their names suggest:

| Taguette table  | Column names                                             | Consumed as                                |
|-----------------|----------------------------------------------------------|--------------------------------------------|
| `tags`          | `id`, `project_id`, `path`, `description`                | `df.tag_table` — the tag hierarchy         |
| `highlight_tags`| `highlight_id`, `tag_id`                                 | `df.highlights` — the (highlight, tag) join|
| `highlights`    | `id`, `document_id`, `start_offset`, `end_offset`, `snippet` | `df.snippets` — the extracted text     |

Every mutation function in this package uses the second column of the naming pair — i.e. `df.tag_table` on `tags`, `df.highlights` on `highlight_tags`, `df.snippets` on `highlights`. The naming is historical and matches the upstream pipeline's variable convention.

## Path convention

A tag's hierarchy is stored as a single string in `tags.path`, with segments joined by two backslashes and a space:

```
Character\\ Grief\\ Rituals
```

The separator is chosen so it is unlikely to occur inside a segment. `build_review_table()` splits `path` on `\\\\ ?` (space optional) so pre-existing malformed paths still split cleanly. The result is one column per hierarchy rank (`1` = Domain, `2` = section, `3` = key, `4` = subkey).

`normalize_tag_paths()` canonicalises the separator using PCRE regexes with Unicode character classes (`\p{L}`, `\p{N}`) so both ASCII and non-ASCII (Japanese, etc.) segment boundaries are handled uniformly.

The **`DEMOTED_`** prefix on the first segment of a `path` is a soft-delete marker: `build_review_table()` silently filters out any tag whose first segment starts with `"DEMOTED_"`. Merges leave the merged-from tag as `DEMOTED_<original path>` so highlights remain traceable if you inspect the SQLite directly, but the tag drops out of the analytical view.

## The mod-Excel format

The mod-Excel (`*_tag_review..mod.xlsx`) is the review CSV opened in Excel with two additional columns filled in by the analyst:

| Column | Filled by | Meaning |
|---|---|---|
| `Old_New` | user | Group ID — all rows with the same integer form one "operation". Rows with NA `Old_New` are silently ignored. |
| `from_to` | user | One of `"from"`, `"to"`, `"unlink"`, `"add"`, `"apply"`. See *Common operations* below. |
| `highlight_id` | (inherited) | From the review CSV — used to re-point highlights. |
| `tag_id`       | (inherited) | Ditto. |
| `path`         | (inherited or user) | If the user wants a full literal target path they can type it here; otherwise the pipeline reconstructs it from the hierarchy columns. |
| `1 - Domain` … `4 - subkey` | user | The four-column hierarchy view. If `path` is NA, `create_tagmod_list()` joins these with the `\\ ` separator. |

`create_tagmod_list()` reads the workbook, groups by `Old_New`, and returns each group as a class-tagged list element (`path_change` / `unlink` / `add` / `apply`). `apply_tagmod_ops()` sorts the ops by class and applies them in the order `path_change → add → apply → unlink`.

## Common operations

Each operation in this section is **one or more rows in the mod-Excel** sharing one `Old_New` integer.

### Rename a tag

Change a tag's path, keep its identity and its coded highlights on the same `tag_id`.

| Old_New | from_to | path |
|---|---|---|
| 1 | `from` | `Character\\ Grief\\ Rituals` |
| 1 | `to`   | `Character\\ Small Rituals` |

Because the target path does not yet exist in the tag_table, `tag_edit()` dispatches to `change_tag()`. `tags.path` is rewritten in place; `highlight_tags.tag_id` is untouched.

### Merge two tags

Consolidate one tag's highlights into another that already exists. Highlights previously on the merged-from tag are re-pointed to the merged-into tag.

| Old_New | from_to | path |
|---|---|---|
| 2 | `from` | `Style\\ Voice` |
| 2 | `to`   | `Style\\ Sentence Length` |

Because the target already exists, `tag_edit()` dispatches to `change_tag_merge()`. Every highlight with `tag_id == id_from` is re-pointed to `id_to`. The from-tag's `path` is rewritten to `DEMOTED_<original>` so it drops out of subsequent review passes but is still discoverable in the raw SQLite.

### Add a new tag (optionally with highlights)

Create a tag directly from the mod-Excel; optionally attach it to specific highlights.

| Old_New | from_to | highlight_id | path |
|---|---|---|---|
| 3 | `add` | 42  | `Character\\ Silence` |
| 3 | `add` | 57  | `Character\\ Silence` |

All rows in an `add` group must share the same `path`. The `path` must **not** already exist in `tags`. Highlight rows with a blank `highlight_id` are legal — the tag is created without any highlights attached.

### Apply an existing tag to highlights

Mirror of `add`, for tags that already exist.

| Old_New | from_to | highlight_id | path |
|---|---|---|---|
| 4 | `apply` | 88  | `Setting\\ Domestic` |
| 4 | `apply` | 91  | `Setting\\ Domestic` |

The `path` must already exist in `tags` — exactly once. Fails loudly on codebook duplicates.

### Unlink a tag from specific highlights

Remove one or more `(highlight_id, tag_id)` pairs from `highlight_tags`, leaving other rows with the same `tag_id` or `highlight_id` untouched.

| Old_New | from_to  | highlight_id | tag_id |
|---|---|---|---|
| 5 | `unlink` | 100          | 3      |
| 5 | `unlink` | 101          | 3      |

Each unlink row targets one specific pair. Errors atomically if any requested pair is not present — no partial writes.

### Soft-delete an entire tag

Two idiomatic options:

**Option A — `DEMOTED_` prefix rename (recommended).** Rename `Foo\\ Bar` to `DEMOTED_Foo\\ Bar`. The tag drops out of the analytical view. Highlights previously on the tag surface in the next review pass with NA hierarchy — intended affordance for re-tagging.

**Option B — Merge into a catch-all.** Merge into a `Trash\\ Deleted` tag (create it first if it doesn't exist). Consolidates highlights under one placeholder.

Hard delete (physical removal from `tags` + `highlight_tags`) is not supported by the pipeline.

## Sequencing within one iteration

`apply_tagmod_ops()` sorts operations by class before the loop:

1. **`path_change`** first — normalise the existing hierarchy so downstream ops work in a stable landscape.
2. **`add`** — new tag_ids generated against the post-`path_change` tag_table.
3. **`apply`** — can legitimately reference tags that were just added in the same iteration.
4. **`unlink`** last — its `(highlight_id, tag_id)` references must be stable when it runs.

## Exact-match semantics for merges

`change_tag_merge()` uses exact string equality on `path` (not `gsub`) and integer equality on `tag_id`, so paths containing regex metacharacters (`|`, `.`, `*`, `[`, `+`, etc.) are safe. The regression test suite (`tests/testthat/test-change_tag_merge.R`) covers 7 scenarios including regex-metachar safety, prefix-of-child collisions, and numeric-id substring collisions.

## Known limitations

- **Highlight offset drift after DB-Browser edits.** Editing `documents.contents` directly in DB Browser or any external SQLite editor invalidates the character positions in `highlights.start_offset` / `end_offset`. The pipeline has no auto-correction; a planned fix would add a per-document offset-delta column to the mod-Excel and apply it at mod time.
- **`Old_New` is user-populated, not diff-computed.** Rows with blank `Old_New` are silently dropped from the mod list; there is no code path that reconstructs a change history from before/after SQLite states.

## Package layout

```
tagmodr/
├── R/                          # exported functions
├── man/                        # roxygen-generated Rd
├── tests/testthat/             # 4 mutation tests + 1 read/write round-trip
├── inst/extdata/               # synthetic example_project.sqlite3 fixture
├── vignettes/tagmodr-workflow.Rmd
└── data-raw/build_example_sqlite.R
```

## License

MIT © Shimpei Morimoto.

## Attribution

Pipeline distilled from an iterative codebook-development workflow used on
a qualitative-analysis project. This package extracts the reusable
tag-mutation primitives (rename / merge / unlink / add / apply) as a
Taguette-agnostic library. The regression test suite (28 scenarios)
mirrors the original in-project tests one-for-one.
