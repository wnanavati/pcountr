# Deprecated test file — tests moved to test-site_matrix.R (v0.5.0).
# This file is retained only because OneDrive prevents deletion;
# it contains a single smoke-test confirming the deprecation wrapper works.

test_that("as_rioja() deprecation wrapper calls site_matrix() and warns", {
  extdata <- function(...) system.file("extdata", ..., package = "pcountr")
  lm_col_map <- c(file = "SampleName", depth_top = "DepthTop",
                  depth_bottom = "DepthBottom")
  site <- suppressWarnings(
    read_site(extdata(),
              metadata = extdata("LM_depths.txt"),
              col_map  = lm_col_map,
              quiet    = TRUE)
  )
  expect_warning(r <- as_rioja(site), regexp = "site_matrix")
  expect_true(is.matrix(r$TaxaPerc))
})
