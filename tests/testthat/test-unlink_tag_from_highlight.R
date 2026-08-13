tag_tbl <- data.frame(
  id = c(10L, 20L, 30L), path = c("Alpha", "Beta", "Gamma"),
  stringsAsFactors = FALSE
)
hl <- data.frame(
  highlight_id = c(100L, 100L, 101L, 102L, 102L),
  tag_id = c(10L, 20L, 10L, 20L, 30L),
  stringsAsFactors = FALSE
)

test_that("U-A. single unlink — one (highlight_id, tag_id) pair", {
  res <- unlink_tag_from_highlight(
    highlight_ids = 100L, tag_ids = 10L,
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(res[[1]], tag_tbl)
  expect_identical(as.integer(res[[2]]$highlight_id), c(100L, 101L, 102L, 102L))
  expect_identical(as.integer(res[[2]]$tag_id), c(20L, 10L, 20L, 30L))
})

test_that("U-B. batch unlink — two pairs at once", {
  res <- unlink_tag_from_highlight(
    highlight_ids = c(100L, 102L), tag_ids = c(10L, 30L),
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(as.integer(res[[2]]$highlight_id), c(100L, 101L, 102L))
  expect_identical(as.integer(res[[2]]$tag_id), c(20L, 10L, 20L))
})

test_that("U-C. errors when highlight_id is absent", {
  expect_error(
    unlink_tag_from_highlight(highlight_ids = 999L, tag_ids = 10L,
                              df.tag_table = tag_tbl, df.highlights = hl),
    "not present in df.highlights"
  )
})

test_that("U-D. errors when (highlight_id, tag_id) pair is absent", {
  expect_error(
    unlink_tag_from_highlight(highlight_ids = 101L, tag_ids = 30L,
                              df.tag_table = tag_tbl, df.highlights = hl),
    "not present in df.highlights"
  )
})

test_that("U-E. errors on length mismatch", {
  expect_error(
    unlink_tag_from_highlight(highlight_ids = c(100L, 102L), tag_ids = 10L,
                              df.tag_table = tag_tbl, df.highlights = hl),
    "length\\(highlight_ids\\)"
  )
})

test_that("U-F. last-tag semantics — highlight vanishes when its sole tag is unlinked", {
  res <- unlink_tag_from_highlight(
    highlight_ids = 101L, tag_ids = 10L,
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(as.integer(res[[2]]$highlight_id), c(100L, 100L, 102L, 102L))
  expect_identical(as.integer(res[[2]]$tag_id), c(10L, 20L, 20L, 30L))
})

test_that("U-G. atomic error — no partial write when one pair in a batch is missing", {
  expect_error(
    unlink_tag_from_highlight(
      highlight_ids = c(100L, 999L), tag_ids = c(10L, 10L),
      df.tag_table = tag_tbl, df.highlights = hl
    ),
    "not present in df.highlights"
  )
})
