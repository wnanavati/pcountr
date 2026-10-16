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
