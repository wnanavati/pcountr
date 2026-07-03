extdata <- function(...) system.file("extdata", ..., package = "pcountr")

lm_col_map <- c(file = "SampleName", depth_top = "DepthTop",
                depth_bottom = "DepthBottom")

# Load the full 20-sample LM site with real depths once for all tests.
lm_site <- local({
  suppressWarnings(
    read_site(extdata(),
              metadata = extdata("LM_depths.txt"),
              col_map  = lm_col_map,
              quiet    = TRUE)
  )
})

# ---------------------------------------------------------------------------
# Basic structure
# ---------------------------------------------------------------------------

test_that("site_matrix returns correct list names", {
  r <- site_matrix(lm_site)
  expect_type(r, "list")
  expect_named(r, c("DepTop", "DepBot", "AgeTop", "AgeBot",
                    "SampleSize", "SpikeCount", "SpikeAdded", "SpikeConc",
                    "TaxaCount", "TaxaPerc", "TaxaConc", "TaxaAccRate",
                    "groups_used"))
})

test_that("TaxaPerc is a numeric matrix with 20 rows (one per depth sample)", {
  r <- site_matrix(lm_site)
  expect_true(is.matrix(r$TaxaPerc))
  expect_true(is.numeric(r$TaxaPerc))
  expect_equal(nrow(r$TaxaPerc), 20L)
})

test_that("TaxaCount has same dimensions as TaxaPerc", {
  r <- site_matrix(lm_site)
  expect_equal(dim(r$TaxaCount), dim(r$TaxaPerc))
  expect_equal(dimnames(r$TaxaCount), dimnames(r$TaxaPerc))
})

test_that("DepTop vector is parallel to TaxaPerc rows and all finite", {
  r <- site_matrix(lm_site)
  expect_equal(length(r$DepTop), nrow(r$TaxaPerc))
  expect_true(all(is.finite(r$DepTop)))
})

test_that("rows are ordered shallowest first", {
  r <- site_matrix(lm_site)
  expect_true(all(diff(r$DepTop) > 0))
  expect_equal(unname(r$DepTop[1]),  0.0)   # LMSH001
  expect_equal(unname(r$DepTop[20]), 44.0)  # LMSH158
})

test_that("row names match sample keys in depth order", {
  r <- site_matrix(lm_site)
  expect_equal(rownames(r$TaxaPerc)[1],  "LMSH001")
  expect_equal(rownames(r$TaxaPerc)[20], "LMSH158")
})

test_that("only non-special taxa appear as columns", {
  r   <- site_matrix(lm_site, taxon_label = "code")
  dic <- lm_site$dictionary
  special_codes <- dic$code[dic$is_special]
  expect_false(any(colnames(r$TaxaPerc) %in% special_codes))
})

# ---------------------------------------------------------------------------
# Percentage correctness
# ---------------------------------------------------------------------------

test_that("percentages sum to > 0 for each sample", {
  r <- site_matrix(lm_site)
  for (i in seq_len(nrow(r$TaxaPerc)))
    expect_gt(sum(r$TaxaPerc[i, ], na.rm = TRUE), 0)
})

test_that("LMSH001 Betula (B) percentage is correct", {
  r   <- site_matrix(lm_site, groups = c("A", "B", "F"), taxon_label = "code")
  dic <- lm_site$dictionary
  cnt <- suppressWarnings(
    read_cnt(extdata("LMSH001.CNT"),
             site = pollen_site("LM", dic), quiet = TRUE)
  )
  g       <- cnt$grains
  grp     <- dic$group[match(g$code, dic$code)]
  denom   <- sum(g$weight[!is.na(grp) & grp %in% c("A","B","F")])
  betula  <- sum(g$weight[g$code == "B"])
  expected_pct <- betula / denom * 100
  expect_equal(unname(r$TaxaPerc["LMSH001", "B"]), expected_pct, tolerance = 1e-6)
})

test_that("TaxaCount Betula (B) raw count matches grains data frame", {
  r   <- site_matrix(lm_site, taxon_label = "code")
  dic <- lm_site$dictionary
  cnt <- suppressWarnings(
    read_cnt(extdata("LMSH001.CNT"),
             site = pollen_site("LM", dic), quiet = TRUE)
  )
  expected_count <- sum(cnt$grains$weight[cnt$grains$code == "B"])
  expect_equal(unname(r$TaxaCount["LMSH001", "B"]), expected_count, tolerance = 1e-6)
})

# ---------------------------------------------------------------------------
# groups argument
# ---------------------------------------------------------------------------

test_that("custom groups changes the denominator", {
  r_abf  <- site_matrix(lm_site, groups = c("A","B","F"))
  r_abfq <- site_matrix(lm_site, groups = c("A","B","F","Q"))
  expect_true(all(r_abfq$TaxaPerc <= r_abf$TaxaPerc + 1e-9, na.rm = TRUE))
  expect_equal(r_abfq$groups_used, c("A","B","F","Q"))
})

test_that("groups_used reflects the supplied groups", {
  r <- site_matrix(lm_site, groups = c("A","B"))
  expect_equal(r$groups_used, c("A","B"))
})

# ---------------------------------------------------------------------------
# taxon_label argument
# ---------------------------------------------------------------------------

test_that("default taxon_label uses full taxon names", {
  r <- site_matrix(lm_site)
  expect_true(mean(nchar(colnames(r$TaxaPerc))) > 5)
})

test_that("taxon_label = 'code' uses dictionary codes as column names", {
  r <- site_matrix(lm_site, taxon_label = "code")
  dic <- lm_site$dictionary
  valid_codes <- dic$code[!dic$is_special]
  expect_true(all(colnames(r$TaxaPerc) %in% valid_codes))
})

test_that("taxon_label = 'name' uses full taxon names", {
  r <- site_matrix(lm_site, taxon_label = "name")
  expect_true(mean(nchar(colnames(r$TaxaPerc))) > 5)
})

test_that("taxon_label = 'alias' falls back to code when alias is blank", {
  r_alias <- site_matrix(lm_site, taxon_label = "alias")
  r_code  <- site_matrix(lm_site, taxon_label = "code")
  expect_true(all(nzchar(colnames(r_alias$TaxaPerc))))
  expect_equal(dim(r_alias$TaxaPerc), dim(r_code$TaxaPerc))
})

# ---------------------------------------------------------------------------
# min_present filter
# ---------------------------------------------------------------------------

test_that("min_present reduces the number of columns in all taxa matrices", {
  r0 <- site_matrix(lm_site, min_present = 0L)
  r5 <- site_matrix(lm_site, min_present = 5L)
  expect_lt(ncol(r5$TaxaPerc),  ncol(r0$TaxaPerc))
  expect_lt(ncol(r5$TaxaCount), ncol(r0$TaxaCount))
  expect_equal(ncol(r5$TaxaPerc), ncol(r5$TaxaCount))
})

test_that("min_present = 1 excludes taxa absent from all samples", {
  r <- site_matrix(lm_site, min_present = 1L)
  present <- colSums(r$TaxaPerc > 0, na.rm = TRUE)
  expect_true(all(present >= 1L))
})

# ---------------------------------------------------------------------------
# Samples without depth are excluded
# ---------------------------------------------------------------------------

test_that("samples without depth are excluded and a message is emitted", {
  site2 <- lm_site
  site2$samples[["LMSH001"]]$meta$depth_top    <- NA_real_
  site2$samples[["LMSH001"]]$meta$depth_bottom <- NA_real_

  expect_message(r <- site_matrix(site2), regexp = "LMSH001")
  expect_equal(nrow(r$TaxaPerc), 19L)
  expect_false("LMSH001" %in% rownames(r$TaxaPerc))
})

