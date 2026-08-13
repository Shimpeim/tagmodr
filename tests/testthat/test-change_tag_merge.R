sep <- "sep"

test_that("A. safe merge — no collisions", {
  tag_tbl <- data.frame(
    id = c(10L, 20L),
    path = c(paste("Foo", "Bar", sep = sep), paste("Baz", "Qux", sep = sep)),
    stringsAsFactors = FALSE
  )
  hl <- data.frame(
    highlight_id = 1:3, tag_id = c(10L, 10L, 20L),
    stringsAsFactors = FALSE
  )
  res <- change_tag_merge(
    str_from = paste("Foo", "Bar", sep = sep),
    str_to = paste("Baz", "Qux", sep = sep),
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(
    res[[1]]$path[order(res[[1]]$id)],
    c(sprintf("DEMOTED_%s", paste("Foo", "Bar", sep = sep)),
      paste("Baz", "Qux", sep = sep))
  )
  expect_identical(as.integer(res[[2]]$tag_id[order(res[[2]]$highlight_id)]),
                   c(20L, 20L, 20L))
})

test_that("B. str_from is a prefix of another tag's path", {
  tag_tbl <- data.frame(
    id = c(10L, 20L, 30L, 40L),
    path = c(
      paste("A", "B", sep = sep),
      paste("C", "D", sep = sep),
      paste("A", "B", "Y", sep = sep),
      paste("X", "A", "B", sep = sep)
    ),
    stringsAsFactors = FALSE
  )
  hl <- data.frame(
    highlight_id = 1:4, tag_id = c(10L, 30L, 40L, 20L),
    stringsAsFactors = FALSE
  )
  res <- change_tag_merge(
    str_from = paste("A", "B", sep = sep),
    str_to = paste("C", "D", sep = sep),
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(
    res[[1]]$path[order(res[[1]]$id)],
    c(sprintf("DEMOTED_%s", paste("A", "B", sep = sep)),
      paste("C", "D", sep = sep),
      paste("A", "B", "Y", sep = sep),
      paste("X", "A", "B", sep = sep))
  )
  expect_identical(as.integer(res[[2]]$tag_id[order(res[[2]]$highlight_id)]),
                   c(20L, 30L, 40L, 20L))
})

test_that("C. numeric tag_id substring collision (id_from=1 vs id=12)", {
  tag_tbl <- data.frame(
    id = c(1L, 2L, 12L), path = c("Alpha", "Beta", "Gamma"),
    stringsAsFactors = FALSE
  )
  hl <- data.frame(
    highlight_id = 1:3, tag_id = c(1L, 12L, 2L),
    stringsAsFactors = FALSE
  )
  res <- change_tag_merge(
    str_from = "Alpha", str_to = "Beta",
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(res[[1]]$path[order(res[[1]]$id)],
                   c("DEMOTED_Alpha", "Beta", "Gamma"))
  expect_identical(as.integer(res[[2]]$tag_id[order(res[[2]]$highlight_id)]),
                   c(2L, 12L, 2L))
})

test_that("D. str_from is an internal substring of an unrelated tag's path", {
  tag_tbl <- data.frame(
    id = c(5L, 6L, 15L),
    path = c("Perception", "Understanding",
             paste("Patient", "Perception of the Condition", sep = sep)),
    stringsAsFactors = FALSE
  )
  hl <- data.frame(
    highlight_id = 1:3, tag_id = c(5L, 15L, 6L),
    stringsAsFactors = FALSE
  )
  res <- change_tag_merge(
    str_from = "Perception", str_to = "Understanding",
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(
    res[[1]]$path[order(res[[1]]$id)],
    c("DEMOTED_Perception", "Understanding",
      paste("Patient", "Perception of the Condition", sep = sep))
  )
  expect_identical(as.integer(res[[2]]$tag_id[order(res[[2]]$highlight_id)]),
                   c(6L, 15L, 6L))
})

test_that("E. str_from contains regex metacharacters (|, .)", {
  tag_tbl <- data.frame(
    id = c(100L, 200L, 300L), path = c("a|b.c", "z", "a"),
    stringsAsFactors = FALSE
  )
  hl <- data.frame(
    highlight_id = 1:3, tag_id = c(100L, 300L, 200L),
    stringsAsFactors = FALSE
  )
  res <- change_tag_merge(
    str_from = "a|b.c", str_to = "z",
    df.tag_table = tag_tbl, df.highlights = hl
  )
  expect_identical(res[[1]]$path[order(res[[1]]$id)],
                   c("DEMOTED_a|b.c", "z", "a"))
  expect_identical(as.integer(res[[2]]$tag_id[order(res[[2]]$highlight_id)]),
                   c(200L, 300L, 200L))
})

test_that("F. errors when str_from is missing", {
  tt <- data.frame(id = c(1L, 2L), path = c("Alpha", "Beta"),
                   stringsAsFactors = FALSE)
  hl <- data.frame(highlight_id = 1L, tag_id = 1L, stringsAsFactors = FALSE)
  # Suppress the check_tags_exist.csv write during the error path.
  withr::with_tempdir({
    expect_error(
      change_tag_merge("Missing", "Beta", df.tag_table = tt, df.highlights = hl),
      "str_from not found"
    )
  })
})

test_that("G. errors when str_to is missing", {
  tt <- data.frame(id = c(1L, 2L), path = c("Alpha", "Beta"),
                   stringsAsFactors = FALSE)
  hl <- data.frame(highlight_id = 1L, tag_id = 1L, stringsAsFactors = FALSE)
  expect_error(
    change_tag_merge("Alpha", "Missing", df.tag_table = tt, df.highlights = hl),
    "str_to not found"
  )
})
