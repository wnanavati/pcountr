# Tests for the YAML `created` / `last_modified` pair.
#
# The whole point of `created` is that it does not move. The counting app used
# to restamp it on every start, including a resume, so reopening a count
# silently redated it to the day it was reopened and the original date was
# gone. The fix makes write_pollen_count() stamp it only when there is nothing
# to preserve, and read_pollen_count() carry it back so the next write has
# something to preserve. That is an invariant across a round trip, which is
# exactly the kind of thing a later edit can break without any visible symptom
# -- hence these tests rather than trust.

make_count <- function(created = NA_character_) {
  grains <- data.frame(
    code     = c("A", "B"),
    pres     = c("1", "1"),
    weight   = c(1, 1),
    traverse = c("10N", "10N"),
    stringsAsFactors = FALSE
  )
  pollen_count(grains = grains, spike_n = 0L, traverses = "10N",
               remarks = list(), events = list(),
               title = "timestamp test", created = created)
}

test_that("a first write stamps created and last_modified", {
  p <- tempfile(fileext = ".yaml")
  write_pollen_count(make_count(), p)
  doc <- yaml::yaml.load_file(p)

  expect_true(!is.null(doc$created))
  expect_true(!is.null(doc$last_modified))
  # ISO 8601 to the second, so the field sorts and parses without ambiguity.
  expect_match(doc$created,       "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")
  expect_match(doc$last_modified, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")
})

test_that("created survives a read and is not restamped on rewrite", {
  p <- tempfile(fileext = ".yaml")
  write_pollen_count(make_count(), p)
  first <- yaml::yaml.load_file(p)$created

  # Read back, then write again -- the path a resume takes.
  back <- read_pollen_count(p)
  expect_equal(back$meta$created, first)

  Sys.sleep(1.1)                       # so a restamp would be visible
  write_pollen_count(back, p)
  again <- yaml::yaml.load_file(p)

  expect_equal(again$created, first)          # fixed at the first write
  expect_false(identical(again$last_modified, first))  # and this one moved
})

test_that("last_modified advances on every write", {
  p <- tempfile(fileext = ".yaml")
  write_pollen_count(make_count(), p)
  t1 <- yaml::yaml.load_file(p)$last_modified
  Sys.sleep(1.1)
  write_pollen_count(read_pollen_count(p), p)
  t2 <- yaml::yaml.load_file(p)$last_modified
  expect_true(t2 > t1)
})

test_that("a count carrying an explicit created keeps it", {
  p   <- tempfile(fileext = ".yaml")
  old <- "2014-12-30T12:27:00"
  write_pollen_count(make_count(created = old), p)
  expect_equal(yaml::yaml.load_file(p)$created, old)
})

test_that("a file written before the field existed gains one, once", {
  # Simulates a legacy YAML: write, strip the two keys, read, rewrite.
  p <- tempfile(fileext = ".yaml")
  write_pollen_count(make_count(), p)
  txt <- readLines(p)
  writeLines(txt[!grepl("^(created|last_modified):", txt)], p)
  expect_null(yaml::yaml.load_file(p)$created)

  back <- read_pollen_count(p)
  expect_true(is.na(back$meta$created))       # nothing to carry

  write_pollen_count(back, p)
  stamped <- yaml::yaml.load_file(p)$created
  expect_false(is.null(stamped))              # so the next write stamps it

  Sys.sleep(1.1)
  write_pollen_count(read_pollen_count(p), p) # and never again
  expect_equal(yaml::yaml.load_file(p)$created, stamped)
})
