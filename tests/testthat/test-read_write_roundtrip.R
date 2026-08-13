fixture_path <- function() {
  system.file("extdata", "example_project.sqlite3", package = "tagmodr")
}

test_that("read_taguette_sqlite loads all non-system tables into a named list", {
  path <- fixture_path()
  skip_if(path == "", "fixture not installed (dev-only test)")

  sqlite <- read_taguette_sqlite(path)
  expect_type(sqlite, "list")
  expect_true("tags" %in% names(sqlite))
  expect_true("highlights" %in% names(sqlite))
  expect_true("highlight_tags" %in% names(sqlite))
  expect_true("documents" %in% names(sqlite))
  # No system tables leaked into the list.
  expect_false("sqlite_sequence" %in% names(sqlite))
  # table_names attribute preserves the read order.
  expect_identical(attr(sqlite, "table_names"), names(sqlite))
})

test_that("read → write round-trip preserves tag and highlight_tags contents", {
  path <- fixture_path()
  skip_if(path == "", "fixture not installed (dev-only test)")

  sqlite <- read_taguette_sqlite(path)
  out <- tempfile(fileext = ".sqlite3")
  write_taguette_sqlite(sqlite, out)

  sqlite2 <- read_taguette_sqlite(out)
  # Compare only the frames we care about — dbplyr may reorder columns for
  # tables whose R-side column order isn't stable across drivers, so we
  # normalise by sorting rows on their id column and checking equality on
  # the load-bearing columns.
  expect_setequal(sqlite2$tags$id, sqlite$tags$id)
  expect_setequal(sqlite2$tags$path, sqlite$tags$path)
  expect_setequal(
    paste(sqlite2$highlight_tags$highlight_id, sqlite2$highlight_tags$tag_id),
    paste(sqlite$highlight_tags$highlight_id, sqlite$highlight_tags$tag_id)
  )
})

test_that("normalize_tag_paths canonicalises Japanese boundaries left un-spaced by the fixture", {
  path <- fixture_path()
  skip_if(path == "", "fixture not installed (dev-only test)")

  sqlite <- read_taguette_sqlite(path)
  # The fixture intentionally stores Japanese pairs without the space after
  # "\\" (e.g. "登場人物\\内面"). After normalisation the space should be
  # inserted between Unicode-letter neighbours.
  norm <- normalize_tag_paths(sqlite$tags)
  jp_paths <- norm$path[grep("登場人物|場面", norm$path)]
  expect_true(all(grepl("\\\\\\\\ ", jp_paths)))
})

test_that("build_review_table joins tags/highlight_tags/highlights by the expected keys", {
  path <- fixture_path()
  skip_if(path == "", "fixture not installed (dev-only test)")

  sqlite <- read_taguette_sqlite(path)
  tbl <- build_review_table(
    df.tag_table  = normalize_tag_paths(sqlite$tags),
    df.highlights = sqlite$highlight_tags,
    df.snippets   = sqlite$highlights
  )
  # One row per (highlight_id, tag_id) pair.
  expect_equal(nrow(tbl), nrow(sqlite$highlight_tags))
  expect_true(all(c("highlight_id", "tag_id", "path", "snippet") %in% names(tbl)))
  # Split hierarchy columns "1" and "2" exist (some tags have 2 or 3 segments).
  expect_true("1" %in% names(tbl))
  expect_true("2" %in% names(tbl))
})
