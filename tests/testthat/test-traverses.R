# Tests for extract_traverses(). Fake Lake carries traverse labels with stage
# coordinates (e.g. "42N"), so it exercises both the counting and the parsing.

fl_site_tr <- function() {
  fl <- system.file("extdata", "fake_lake", package = "pcountr")
  suppressWarnings(read_site(fl,
    metadata = file.path(fl, "metadata_FL.csv"),
    dic      = file.path(fl, "ECG.csv"), quiet = TRUE))
}

test_that("one row per sample and traverse, in counting order", {
  tv <- extract_traverses(fl_site_tr())
  expect_true(all(c("sample", "traverse", "ordinal", "n_traverses",
                    "position", "direction", "dist_start", "n_ident",
                    "n_marker", "n_special", "richness",
                    "sum_weight") %in% names(tv)))
  one <- tv[tv$sample == tv$sample[1], ]
  expect_equal(one$ordinal, seq_len(nrow(one)))
  expect_equal(unique(one$n_traverses), nrow(one))
})

test_that("a repeated label starts a new traverse", {
  # FL003 types 22 traverse markers but only 21 distinct labels: "35S" is
  # used twice, once at the 8th traverse and again at the 18th. That is what
  # a second slide looks like, since the analyst returns to the same stage
  # coordinates on fresh glass. Keying on the label text pooled the two into
  # one row and silently lost a traverse; on a four-slide count elsewhere it
  # lost 23 of 88.
  tv  <- extract_traverses(fl_site_tr())
  one <- tv[tv$sample == "FL003", ]
  expect_equal(nrow(one), 22L)
  expect_true(any(duplicated(one$traverse)))   # the label does repeat
  expect_false(any(duplicated(one$ordinal)))   # the traverse does not
  expect_equal(sum(one$traverse == "35S"), 2L)

  # The same must hold for the per-taxon view, which indexes by ordinal.
  lg <- extract_traverses(fl_site_tr(), taxa = TRUE)
  expect_equal(length(unique(lg$ordinal[lg$sample == "FL003"])), 22L)
})

test_that("consecutive repeats of a label stay one traverse", {
  # A re-typed marker is not a revisit, so run-length encoding must not
  # split it. Built by hand because no bundled file does this.
  dic <- read_dic_csv(system.file("extdata", "fake_lake", "ECG.csv",
                                  package = "pcountr"))
  ev <- list(
    list(type = "grain", code = "Q", weight = 1, traverse = "10N"),
    list(type = "grain", code = "Q", weight = 1, traverse = "10N"),
    list(type = "grain", code = "P", weight = 1, traverse = "11S"),
    list(type = "grain", code = "Q", weight = 1, traverse = "10N")
  )
  cnt <- structure(list(events = ev, grains = NULL, meta = list()),
                   class = "pollen_count")
  out <- pcountr:::.traverses_one(cnt, "x", character(0), taxa = FALSE)
  expect_equal(nrow(out), 3L)                 # 10N, 11S, 10N again
  expect_equal(out$n_ident, c(2L, 1L, 1L))
})

test_that("identification counts reconcile with the sample total", {
  # Every non-special grain belongs to exactly one traverse, so the traverse
  # sums must add back to the whole count.
  site <- fl_site_tr()
  tv   <- extract_traverses(site)
  k    <- names(site$samples)[1]
  cnt  <- site$samples[[k]]
  g    <- cnt$grains
  spec <- site$dictionary$code[site$dictionary$is_special %in% TRUE]
  expect_equal(sum(tv$n_ident[tv$sample == k]),
               sum(!g$code %in% spec))
})

test_that("markers are counted per traverse, not lumped with grains", {
  site <- fl_site_tr()
  tv   <- extract_traverses(site)
  k    <- names(site$samples)[1]
  expect_equal(sum(tv$n_marker[tv$sample == k]), site$samples[[k]]$spike_n)
})

test_that("stage coordinates parse out of the label", {
  tv <- extract_traverses(fl_site_tr())
  expect_true(any(!is.na(tv$position)))
  expect_true(all(tv$direction[!is.na(tv$direction)] %in% c("N","S","E","W")))
  # distance is measured from each sample's own first traverse
  first <- tv[tv$ordinal == 1L & !is.na(tv$position), ]
  expect_true(all(first$dist_start == 0))
})

test_that("a non-numeric label yields NA rather than a coerced number", {
  pos <- pcountr:::.parse_traverse_pos(c("118.0N", "edge", "42S", ""))
  expect_equal(pos$position, c(118, NA, 42, NA))
  expect_equal(pos$direction, c("N", NA, "S", NA))
})

test_that("taxa = TRUE gives one row per sample, traverse and taxon", {
  site <- fl_site_tr()
  lg   <- extract_traverses(site, taxa = TRUE)
  expect_true(all(c("sample","traverse","ordinal","position",
                    "code","n","weight") %in% names(lg)))
  k <- names(site$samples)[1]
  expect_equal(sum(lg$n[lg$sample == k]), nrow(site$samples[[k]]$grains))
})

test_that("a site with no samples is an error, not an empty frame", {
  dic <- read_dic(system.file("extdata", "fake_lake", "ECG.csv",
                              package = "pcountr"))
  expect_error(extract_traverses(pollen_site("x", dic)), "no samples")
})
