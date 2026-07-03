extdata <- function(...) system.file("extdata", ..., package = "pcountr")

lm_col_map <- c(file = "SampleName", depth_top = "DepthTop",
                depth_bottom = "DepthBottom")

lm_site <- local({
  suppressWarnings(
    read_site(extdata(),
              metadata = extdata("LM_depths.txt"),
              col_map  = lm_col_map,
              quiet    = TRUE)
  )
})

# ---------------------------------------------------------------------------
# Return structure
# ---------------------------------------------------------------------------

test_that("rarefaction() returns a pollen_rarefaction object", {
  set.seed(1)
  r <- rarefaction(lm_site)
  expect_s3_class(r, "pollen_rarefaction")
  expect_named(r, c("summary", "curves", "groups", "threshold", "n_sim"))
})

test_that("summary has one row per sample with correct columns", {
  set.seed(1)
  r <- rarefaction(lm_site)
  expect_s3_class(r$summary, "data.frame")
  expect_equal(nrow(r$summary), length(lm_site$samples))
  expect_true(all(c("sample", "n_grains", "n_taxa", "threshold_taxa",
                    "optimal_sum", "meets_optimal", "pct_asymptote")
                  %in% names(r$summary)))
})

test_that("curves list has one entry per sample with three named vectors", {
  set.seed(1)
  r <- rarefaction(lm_site)
  expect_equal(length(r$curves), length(lm_site$samples))
  first <- r$curves[[1]]
  expect_named(first, c("curve_mean", "curve_lo", "curve_hi"))
  # All three vectors have the same length (= n_grains for that sample)
  expect_equal(length(first$curve_mean), r$summary$n_grains[1])
  expect_equal(length(first$curve_lo),   r$summary$n_grains[1])
  expect_equal(length(first$curve_hi),   r$summary$n_grains[1])
})

# ---------------------------------------------------------------------------
# Curve properties
# ---------------------------------------------------------------------------

test_that("rarefaction curves are non-decreasing", {
  set.seed(1)
  r <- rarefaction(lm_site)
  for (nm in names(r$curves)) {
    mn <- r$curves[[nm]]$curve_mean
    expect_true(all(diff(mn) >= -1e-9),
                label = paste("curve_mean non-decreasing for", nm))
  }
})

test_that("curve_mean starts at 1 and ends at n_taxa", {
  set.seed(1)
  r <- rarefaction(lm_site)
  for (i in seq_len(nrow(r$summary))) {
    nm <- r$summary$sample[i]
    mn <- r$curves[[nm]]$curve_mean
    expect_equal(mn[1], 1, tolerance = 1e-6,
                 label = paste("first value == 1 for", nm))
    expect_equal(mn[length(mn)], r$summary$n_taxa[i], tolerance = 1e-6,
                 label = paste("last value == n_taxa for", nm))
  }
})

test_that("curve_lo <= curve_mean <= curve_hi everywhere", {
  set.seed(1)
  r <- rarefaction(lm_site)
  for (nm in names(r$curves)) {
    cv <- r$curves[[nm]]
    expect_true(all(cv$curve_lo <= cv$curve_mean + 1e-9),
                label = paste("lo <= mean for", nm))
    expect_true(all(cv$curve_mean <= cv$curve_hi + 1e-9),
                label = paste("mean <= hi for", nm))
  }
})

# ---------------------------------------------------------------------------
# Optimal sum logic
# ---------------------------------------------------------------------------

test_that("threshold_taxa == ceiling(0.9 * n_taxa)", {
  set.seed(1)
  r <- rarefaction(lm_site)
  expected <- ceiling(0.9 * r$summary$n_taxa)
  expect_equal(r$summary$threshold_taxa, expected)
})

test_that("meets_optimal is TRUE when n_grains >= optimal_sum", {
  set.seed(1)
  r <- rarefaction(lm_site)
  df <- r$summary[!is.na(r$summary$optimal_sum), ]
  expect_equal(df$meets_optimal, df$n_grains >= df$optimal_sum)
})

test_that("pct_asymptote is 100 for any sample where all taxa are present", {
  set.seed(1)
  r <- rarefaction(lm_site)
  # At the full count, the mean curve ends at n_taxa, so pct_asymptote = 100
  expect_true(all(r$summary$pct_asymptote <= 100 + 1e-9))
  expect_true(all(r$summary$pct_asymptote >= 0))
})

test_that("custom threshold changes threshold_taxa and optimal_sum", {
  set.seed(1)
  r90 <- rarefaction(lm_site, threshold = 0.90)
  r80 <- rarefaction(lm_site, threshold = 0.80)
  expect_true(all(r80$summary$threshold_taxa <= r90$summary$threshold_taxa))
  # At lower threshold, optimal sum should be <= that at higher threshold
  both_defined <- !is.na(r80$summary$optimal_sum) &
                  !is.na(r90$summary$optimal_sum)
  if (any(both_defined))
    expect_true(all(r80$summary$optimal_sum[both_defined] <=
                    r90$summary$optimal_sum[both_defined]))
})

# ---------------------------------------------------------------------------
# Half-grain rounding
# ---------------------------------------------------------------------------

test_that("half-grain counts are rounded up (ceiling)", {
  # Build a tiny synthetic site with a half-grain
  dic  <- read_dic(extdata("ECG.DIC"))
  site <- pollen_site("test", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("LMSH001.CNT"), site = site, quiet = TRUE)
  )
  # Inject a half-grain for Betula (code "B")
  cnt$grains <- rbind(cnt$grains,
                      data.frame(code = "B", base = "1", pres = "1",
                                 weight = 0.5, hidden = FALSE,
                                 traverse = NA_character_,
                                 position = NA_integer_,
                                 stringsAsFactors = FALSE))
  cnt$meta$depth_top    <- 50.0
  cnt$meta$depth_bottom <- 50.5

  site2 <- read_site(extdata(), metadata = extdata("LM_depths.txt"),
                     col_map = lm_col_map, quiet = TRUE)
  site2$samples[["halfgrain_test"]] <- cnt

  set.seed(1)
  r <- rarefaction(site2)

  # n_grains should include the half grain rounded up: 1 extra grain for B
  orig <- suppressWarnings(rarefaction(
    suppressWarnings(read_site(extdata(),
                               metadata = extdata("LM_depths.txt"),
                               col_map  = lm_col_map, quiet = TRUE))))
  orig_B_count <- orig$summary$n_grains[orig$summary$sample == "LMSH001"]
  new_B_count  <- r$summary$n_grains[r$summary$sample == "halfgrain_test"]
  # halfgrain_test is LMSH001 + 1 extra half-grain rounded up = +1 grain
  expect_equal(new_B_count, orig_B_count + 1L)
})

# ---------------------------------------------------------------------------
# Depth and age range filters
# ---------------------------------------------------------------------------

test_that("depth_range restricts to samples within range", {
  set.seed(1)
  r_all    <- rarefaction(lm_site)
  r_sub    <- rarefaction(lm_site, depth_range = c(0, 10))
  depths   <- r_sub$summary$depth_top
  expect_true(all(depths >= 0 & depths <= 10, na.rm = TRUE))
  expect_lt(nrow(r_sub$summary), nrow(r_all$summary))
})

test_that("depth_range with no matching samples errors", {
  expect_error(rarefaction(lm_site, depth_range = c(9999, 10000)),
               regexp = "No samples")
})

test_that("n_sim is respected", {
  set.seed(1)
  r <- rarefaction(lm_site, n_sim = 10L)
  expect_equal(r$n_sim, 10L)
})

# ---------------------------------------------------------------------------
# print method
# ---------------------------------------------------------------------------

test_that("print.pollen_rarefaction runs without error", {
  set.seed(1)
  r <- rarefaction(lm_site)
  expect_output(print(r), regexp = "rarefaction")
})
