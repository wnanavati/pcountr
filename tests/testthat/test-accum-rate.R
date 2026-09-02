extdata <- function(...) system.file("extdata", ..., package = "pcountr")

# LMSH001 known values (from golden test):
#   total_sum = 338.5, spike_n = 72
#   spike_tablets = 2, spike_density = 9666, sample_quantity = 1, units = "g"
#   spike_factor = (2 * 9666) / (72 * 1) = 268.5
#   concentration = 338.5 * 268.5 = 90887.25 grains/g
#   B (Betula) weight = 139.0 -> B_conc = 139.0 * 268.5 = 37321.5 grains/g

# Helper: build a one-sample site from LMSH001 with full inputs
make_one_sample_site <- function(depth_top    = 0.0,
                                 depth_bottom = 0.5,
                                 age_top      = 100.0,
                                 age_bottom   = 200.0) {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("LMSH001.CNT"), site = site, quiet = TRUE)
  )
  cnt$meta$depth_top    <- depth_top
  cnt$meta$depth_bottom <- depth_bottom
  cnt$meta$age_top      <- age_top
  cnt$meta$age_bottom   <- age_bottom
  pollen_site("LM_test", dic, samples = list(LMSH001 = cnt))
}

# ---------------------------------------------------------------------------
# Return structure
# ---------------------------------------------------------------------------

test_that("accum_rate returns list with data, taxon_concentration, taxon_influx", {
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_named(r, c("data", "taxon_concentration", "taxon_influx"))
})

test_that("data frame has correct columns and one row", {
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_equal(nrow(r$data), 1L)
  expect_true(all(c("sample", "depth_top", "depth_bottom",
                    "age_top", "age_bottom", "deposition_time",
                    "concentration", "influx") %in% names(r$data)))
})

# ---------------------------------------------------------------------------
# Deposition time arithmetic
# ---------------------------------------------------------------------------

test_that("deposition_time = (age_bottom - age_top) / (depth_bottom - depth_top)", {
  # depth interval = 0.5 cm, age interval = 100 yr -> dep_time = 200 yr/cm
  s <- make_one_sample_site(depth_top = 0.0, depth_bottom = 0.5,
                            age_top   = 100, age_bottom   = 200)
  r <- accum_rate(s)
  expect_equal(r$data$deposition_time, 200.0)
})

test_that("deposition_time handles non-unit intervals correctly", {
  # depth = 2 cm, age = 500 yr -> dep_time = 250 yr/cm
  s <- make_one_sample_site(depth_top = 10.0, depth_bottom = 12.0,
                            age_top   = 1000, age_bottom   = 1500)
  r <- accum_rate(s)
  expect_equal(r$data$deposition_time, 250.0)
})

# ---------------------------------------------------------------------------
# Concentration (golden value from count_metrics)
# ---------------------------------------------------------------------------

test_that("concentration matches count_metrics golden value", {
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_equal(r$data$concentration, 90887.25, tolerance = 1e-6)
})

# ---------------------------------------------------------------------------
# Total PAR
# ---------------------------------------------------------------------------

test_that("influx = concentration / deposition_time", {
  # dep_time = 200 yr/cm; concentration = 90887.25 -> influx = 454.43625
  s <- make_one_sample_site(depth_top = 0.0, depth_bottom = 0.5,
                            age_top   = 100, age_bottom   = 200)
  r <- accum_rate(s)
  expect_equal(r$data$influx, 90887.25 / 200, tolerance = 1e-6)
})

# ---------------------------------------------------------------------------
# Per-taxon concentration
# ---------------------------------------------------------------------------

test_that("per-taxon concentration: Betula (B) = 139.0 * 268.5 = 37321.5", {
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_equal(r$taxon_concentration["LMSH001", "B"], 37321.5, tolerance = 1e-6)
})

test_that("sum of per-taxon concentrations >= total concentration", {
  # Per-taxon covers ALL non-special taxa; total uses only total_groups (A+B+F+Q).
  # So sum of all taxon concentrations >= reported total concentration.
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_gte(sum(r$taxon_concentration["LMSH001", ]), r$data$concentration - 1e-6)
})

# ---------------------------------------------------------------------------
# Per-taxon influx
# ---------------------------------------------------------------------------

test_that("taxon_influx = taxon_concentration / deposition_time", {
  s <- make_one_sample_site(depth_top = 0.0, depth_bottom = 0.5,
                            age_top   = 100, age_bottom   = 200)
  r <- accum_rate(s)
  # B influx = 37321.5 / 200 = 186.6075
  expect_equal(r$taxon_influx["LMSH001", "B"], 37321.5 / 200, tolerance = 1e-6)
})

test_that("taxon_influx and taxon_concentration have same dimensions", {
  s <- make_one_sample_site()
  r <- accum_rate(s)
  expect_equal(dim(r$taxon_influx), dim(r$taxon_concentration))
  expect_equal(dimnames(r$taxon_influx), dimnames(r$taxon_concentration))
})

test_that("only non-special taxa appear in per-taxon matrices", {
  s   <- make_one_sample_site()
  dic <- s$dictionary
  r   <- accum_rate(s)
  spc <- dic$code[dic$is_special]
  expect_false(any(colnames(r$taxon_influx) %in% spc))
})

# ---------------------------------------------------------------------------
# Multi-sample site
# ---------------------------------------------------------------------------

test_that("multi-sample site returns one row per depth-bearing sample", {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  make_cnt <- function(f, dt, db, at, ab) {
    cnt <- suppressWarnings(read_cnt(extdata(f), site = site, quiet = TRUE))
    cnt$meta$depth_top    <- dt
    cnt$meta$depth_bottom <- db
    cnt$meta$age_top      <- at
    cnt$meta$age_bottom   <- ab
    cnt
  }
  s2 <- pollen_site("LM2", dic, samples = list(
    LMSH001 = make_cnt("LMSH001.CNT", 0.0, 0.5,  100, 200),
    FL002   = make_cnt("fake_lake/FL002.CNT", 4.0, 4.5, 500, 650)
  ))
  r <- accum_rate(s2)
  expect_equal(nrow(r$data), 2L)
  expect_equal(nrow(r$taxon_influx), 2L)
})

# ---------------------------------------------------------------------------
# Validation errors
# ---------------------------------------------------------------------------

test_that("missing age_top triggers an informative error", {
  s <- make_one_sample_site()
  s$samples[["LMSH001"]]$meta$age_top <- NA_real_
  expect_error(accum_rate(s), regexp = "age_top is NA")
})

test_that("missing age_bottom triggers an informative error", {
  s <- make_one_sample_site()
  s$samples[["LMSH001"]]$meta$age_bottom <- NA_real_
  expect_error(accum_rate(s), regexp = "age_bottom is NA")
})

test_that("age_bottom <= age_top triggers an informative error", {
  s <- make_one_sample_site(age_top = 500, age_bottom = 100)  # reversed
  expect_error(accum_rate(s), regexp = "age_bottom.*must be > age_top")
})

test_that("depth_bottom <= depth_top triggers an informative error", {
  s <- make_one_sample_site(depth_top = 10.0, depth_bottom = 5.0)
  expect_error(accum_rate(s), regexp = "depth_bottom.*must be > depth_top")
})

test_that("multiple errors across samples are all reported in one stop()", {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  make_bare <- function(f) {
    suppressWarnings(read_cnt(extdata(f), site = site, quiet = TRUE))
    # depth will be NA, age will be NA -> multiple errors
  }
  cnt1 <- suppressWarnings(read_cnt(extdata("LMSH001.CNT"), site = site, quiet = TRUE))
  cnt2 <- suppressWarnings(read_cnt(extdata("fake_lake", "FL002.CNT"), site = site, quiet = TRUE))
  # Give depths but not ages to both
  cnt1$meta$depth_top <- 0.0; cnt1$meta$depth_bottom <- 0.5
  cnt2$meta$depth_top <- 4.0; cnt2$meta$depth_bottom <- 4.5
  s2 <- pollen_site("LM2", dic,
                    samples = list(LMSH001 = cnt1, FL002 = cnt2))
  err <- tryCatch(accum_rate(s2), error = function(e) conditionMessage(e))
  # Both samples should appear in the error message
  expect_true(grepl("LMSH001", err))
  expect_true(grepl("FL002", err))
})

test_that("samples without depth_top are skipped with a message", {
  s <- make_one_sample_site()
  # Add a second sample with no depth
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt2 <- suppressWarnings(
    read_cnt(extdata("fake_lake", "FL002.CNT"), site = site, quiet = TRUE)
  )
  # cnt2 has no depth -> should be skipped
  s$samples[["FL002"]] <- cnt2
  expect_message(r <- accum_rate(s), regexp = "FL002")
  expect_equal(nrow(r$data), 1L)
})
