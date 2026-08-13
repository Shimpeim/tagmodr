tag_tbl_base <- data.frame(
  id = c(10L, 20L, 30L), path = c("Alpha", "Beta", "Gamma"),
  stringsAsFactors = FALSE
)
hl_base <- data.frame(
  highlight_id = c(100L, 100L, 101L, 102L),
  tag_id = c(10L, 20L, 10L, 30L),
  stringsAsFactors = FALSE
)

test_that("P-A. apply existing tag to one highlight", {
  res <- apply_tag_to_highlights(
    path = "Alpha", highlight_ids = 200L,
    df.tag_table = tag_tbl_base, df.highlights = hl_base
  )
  expect_identical(res[[1]], tag_tbl_base)
  expect_equal(nrow(res[[2]]), nrow(hl_base) + 1L)
  last <- res[[2]][nrow(res[[2]]), ]
  expect_equal(last$highlight_id, 200L)
  expect_equal(last$tag_id, 10L)
})

test_that("P-B. batch apply — one tag to multiple highlights", {
  res <- apply_tag_to_highlights(
    path = "Beta", highlight_ids = c(300L, 301L, 302L),
    df.tag_table = tag_tbl_base, df.highlights = hl_base
  )
  new <- res[[2]][res[[2]]$highlight_id %in% c(300L, 301L, 302L), ]
  expect_equal(nrow(new), 3L)
  expect_true(all(new$tag_id == 20L))
})

test_that("P-C. errors when path not in tag_table", {
  expect_error(
    apply_tag_to_highlights(path = "MissingPath", highlight_ids = 200L,
                            df.tag_table = tag_tbl_base, df.highlights = hl_base),
    "path not found"
  )
})

test_that("P-D. errors on duplicate highlight_ids in batch", {
  expect_error(
    apply_tag_to_highlights(path = "Alpha", highlight_ids = c(200L, 200L),
                            df.tag_table = tag_tbl_base, df.highlights = hl_base),
    "duplicate highlight_ids"
  )
})

test_that("P-E. errors when (highlight_id, tag_id) pair already exists", {
  expect_error(
    apply_tag_to_highlights(path = "Alpha", highlight_ids = 100L,
                            df.tag_table = tag_tbl_base, df.highlights = hl_base),
    "already present"
  )
})

test_that("P-F. errors when tag_table has duplicate paths", {
  tt_dup <- rbind(tag_tbl_base,
                  data.frame(id = 40L, path = "Alpha", stringsAsFactors = FALSE))
  expect_error(
    apply_tag_to_highlights(path = "Alpha", highlight_ids = 200L,
                            df.tag_table = tt_dup, df.highlights = hl_base),
    "multiple rows"
  )
})

test_that("P-G. apply against a just-added tag", {
  r_add <- add_tag_with_highlights(path = "Delta", highlight_ids = integer(0),
                                   df.tag_table = tag_tbl_base, df.highlights = hl_base)
  r_app <- apply_tag_to_highlights(path = "Delta", highlight_ids = c(400L, 401L),
                                   df.tag_table = r_add[[1]], df.highlights = r_add[[2]])
  new_id <- r_add[[1]][r_add[[1]]$path == "Delta", "id"]
  new_hl <- r_app[[2]][r_app[[2]]$tag_id == new_id, ]
  expect_equal(nrow(new_hl), 2L)
})
