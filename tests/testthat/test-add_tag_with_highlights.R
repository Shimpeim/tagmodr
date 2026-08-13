tag_tbl_base <- data.frame(
  id = c(10L, 20L, 30L), path = c("Alpha", "Beta", "Gamma"),
  stringsAsFactors = FALSE
)
hl_base <- data.frame(
  highlight_id = c(100L, 100L, 101L, 102L),
  tag_id = c(10L, 20L, 10L, 30L),
  stringsAsFactors = FALSE
)

test_that("A-A. tag-only add (empty highlight_ids)", {
  res <- add_tag_with_highlights(
    path = "Delta", highlight_ids = integer(0),
    df.tag_table = tag_tbl_base, df.highlights = hl_base
  )
  expect_equal(nrow(res[[1]]), nrow(tag_tbl_base) + 1L)
  expect_identical(res[[2]], hl_base)
  new_row <- res[[1]][res[[1]]$path == "Delta", ]
  expect_equal(nrow(new_row), 1L)
  expect_equal(new_row$id, 31L)
})

test_that("A-B. add + attach to one highlight", {
  res <- add_tag_with_highlights(
    path = "Delta", highlight_ids = 200L,
    df.tag_table = tag_tbl_base, df.highlights = hl_base
  )
  new_id <- res[[1]][res[[1]]$path == "Delta", "id"]
  expect_equal(new_id, 31L)
  expect_equal(nrow(res[[2]]), nrow(hl_base) + 1L)
  last <- res[[2]][nrow(res[[2]]), ]
  expect_equal(last$highlight_id, 200L)
  expect_equal(last$tag_id, 31L)
})

test_that("A-C. add + attach to multiple highlights", {
  res <- add_tag_with_highlights(
    path = "Delta", highlight_ids = c(200L, 201L, 202L),
    df.tag_table = tag_tbl_base, df.highlights = hl_base
  )
  new_id <- res[[1]][res[[1]]$path == "Delta", "id"]
  new_hl <- res[[2]][res[[2]]$tag_id == new_id, ]
  expect_equal(nrow(new_hl), 3L)
  expect_identical(sort(as.integer(new_hl$highlight_id)), c(200L, 201L, 202L))
})

test_that("A-D. errors when path already exists", {
  expect_error(
    add_tag_with_highlights(path = "Alpha", highlight_ids = 200L,
                            df.tag_table = tag_tbl_base, df.highlights = hl_base),
    "path already exists"
  )
})

test_that("A-E. errors on duplicate highlight_ids in batch", {
  expect_error(
    add_tag_with_highlights(path = "Delta", highlight_ids = c(200L, 200L),
                            df.tag_table = tag_tbl_base, df.highlights = hl_base),
    "duplicate highlight_ids"
  )
})

test_that("A-F. sequential adds -> distinct tag_ids", {
  r1 <- add_tag_with_highlights(path = "Delta",
                                df.tag_table = tag_tbl_base, df.highlights = hl_base)
  r2 <- add_tag_with_highlights(path = "Epsilon",
                                df.tag_table = r1[[1]], df.highlights = r1[[2]])
  id1 <- r1[[1]][r1[[1]]$path == "Delta", "id"]
  id2 <- r2[[1]][r2[[1]]$path == "Epsilon", "id"]
  expect_equal(id1, 31L)
  expect_equal(id2, 32L)
})

test_that("A-G. empty highlight_ids argument is legal", {
  res <- add_tag_with_highlights(path = "Zeta", highlight_ids = integer(0),
                                 df.tag_table = tag_tbl_base, df.highlights = hl_base)
  expect_equal(nrow(res[[1]]), nrow(tag_tbl_base) + 1L)
  expect_equal(nrow(res[[2]]), nrow(hl_base))
})

test_that("A-H. empty starting tag_table -> id 1L", {
  empty_tt <- tag_tbl_base[0, , drop = FALSE]
  empty_hl <- hl_base[0, , drop = FALSE]
  res <- add_tag_with_highlights(path = "First",
                                 df.tag_table = empty_tt, df.highlights = empty_hl)
  expect_equal(res[[1]]$id, 1L)
})
