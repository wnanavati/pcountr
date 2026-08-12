# test-site-matrix-rioja.R
#
# Smoke tests for the read_site() -> site_matrix() -> rioja::strat.plot()
# pipeline using the bundled Fake Lake dataset.
#
# The existing test-site_matrix.R covers site_matrix() structure in depth
# using the LM data. This file adds:
#   (a) rioja compatibility checks (TaxaPerc matrix shape/names as strat.plot
#       expects them, DepTop parallelism);
#   (b) confirmation that TaxaConc is fully populated when spike metadata is
#       complete (Fake Lake has it; LM data does not);
#   (c) a guarded strat.plot() call that will fail if site_matrix() ever
#       produces output that rioja cannot accept.

fl_dir  <- system.file("extdata", "fake_lake", package = "pcountr")
fl_meta <- system.file("extdata", "fake_lake", "metadata_FL.csv",
                        package = "pcountr")
fl_dic  <- system.file("extdata", "fake_lake", "ECG.csv",
                        package = "pcountr")

fl_site <- local({
  read_site(fl_dir, metadata = fl_meta, dic = fl_dic, quiet = TRUE)
})

fl_mat <- local({
  site_matrix(fl_site, min_present = 2L)
})

# ---------------------------------------------------------------------------
# site_matrix output is rioja-compatible
# ---------------------------------------------------------------------------

test_that("TaxaPerc is a named numeric matrix", {
  expect_true(is.matrix(fl_mat$TaxaPerc))
  expect_true(is.numeric(fl_mat$TaxaPerc))
  expect_false(is.null(rownames(fl_mat$TaxaPerc)))
  expect_false(is.null(colnames(fl_mat$TaxaPerc)))
})

test_that("DepTop is finite double, parallel to TaxaPerc rows", {
  expect_type(fl_mat$DepTop, "double")
  expect_true(all(is.finite(fl_mat$DepTop)))
  expect_equal(length(fl_mat$DepTop), nrow(fl_mat$TaxaPerc))
})

test_that("DepTop is ordered shallowest first", {
  expect_true(all(diff(fl_mat$DepTop) > 0))
})

test_that("Fake Lake produces 20 samples and >= 10 taxa after min_present filter", {
  expect_equal(nrow(fl_mat$TaxaPerc), 20L)
  expect_gte(ncol(fl_mat$TaxaPerc), 10L)
})

test_that("AgeTop is finite for all Fake Lake samples", {
  expect_true(all(is.finite(fl_mat$AgeTop)))
  expect_equal(length(fl_mat$AgeTop), nrow(fl_mat$TaxaPerc))
})

test_that("TaxaConc is fully populated when spike metadata is complete", {
  # Fake Lake has spike parameters for every sample, so no row should be all-NA.
  na_rows <- which(apply(fl_mat$TaxaConc, 1L,
                         function(r) all(is.na(r))))
  expect_equal(length(na_rows), 0L)
})

test_that("TaxaConc and TaxaPerc have the same dimensions and dimnames", {
  expect_equal(dim(fl_mat$TaxaConc),      dim(fl_mat$TaxaPerc))
  expect_equal(dimnames(fl_mat$TaxaConc), dimnames(fl_mat$TaxaPerc))
})

# ---------------------------------------------------------------------------
# rioja::strat.plot() runs without error
# ---------------------------------------------------------------------------

test_that("rioja::strat.plot() accepts TaxaPerc + DepTop without error", {
  skip_if_not_installed("rioja")
  keep    <- colSums(fl_mat$TaxaPerc > 0L, na.rm = TRUE) >= 3L
  tmp_pdf <- tempfile(fileext = ".pdf")
  pdf(tmp_pdf)
  on.exit({ dev.off(); unlink(tmp_pdf) }, add = TRUE)
  # expect_no_warning, not expect_no_error: an unrecognised argument passed
  # through `...` to base graphics only warns, so expect_no_error would let it by.
  expect_no_warning(
    rioja::strat.plot(
      fl_mat$TaxaPerc[, keep, drop = FALSE],
      yvar          = fl_mat$DepTop,
      y.rev         = TRUE,
      scale.percent = TRUE
    )
  )
})

# strat.plot() takes a single y-axis variable (`yvar`). It has no secondary-axis
# argument, so AgeTop is verified as an alternative y-axis, not an additional one.
# An earlier version of this test passed `y2var`, which is not a strat.plot
# parameter: it fell through `...` into base graphics and was discarded with a
# '"y2var" is not a graphical parameter' warning on every internal plotting call.
# expect_no_error() could not see that, so the test passed while asserting
# something untrue.
test_that("rioja::strat.plot() accepts AgeTop as the y-axis variable", {
  skip_if_not_installed("rioja")
  keep    <- colSums(fl_mat$TaxaPerc > 0L, na.rm = TRUE) >= 3L
  tmp_pdf <- tempfile(fileext = ".pdf")
  pdf(tmp_pdf)
  on.exit({ dev.off(); unlink(tmp_pdf) }, add = TRUE)
  expect_no_warning(
    rioja::strat.plot(
      fl_mat$TaxaPerc[, keep, drop = FALSE],
      yvar          = fl_mat$AgeTop,
      y.rev         = TRUE,
      scale.percent = TRUE
    )
  )
})
