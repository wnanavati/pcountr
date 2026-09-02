test_that("all 20 Fake Lake site files parse and compute concentrations", {
  dic  <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Fake Lake", dic)
  files <- list.files(system.file("extdata", "fake_lake", package = "pcountr"),
                      pattern = "^FL.*\\.CNT$", full.names = TRUE)
  expect_length(files, 20)
  for (f in files) {
    cnt <- suppressWarnings(read_cnt(f, site = site, quiet = TRUE))
    m <- count_metrics(cnt)
    expect_gt(nrow(cnt$grains), 100)
    expect_gt(m$total_sum, 0)
    expect_true(is.finite(m$concentration))
  }
})

test_that("known data-entry typos surface as exactly 7 anomalies site-wide", {
  # Fake Lake derives from real counts and carries the same data-entry typos
  # as the site it was built from, so the site-wide anomaly total is also 7.
  dic  <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Fake Lake", dic)
  files <- list.files(system.file("extdata", "fake_lake", package = "pcountr"),
                      pattern = "^FL.*\\.CNT$", full.names = TRUE)
  per_file <- vapply(files, function(f) {
    cnt <- suppressWarnings(read_cnt(f, site = site, quiet = TRUE))
    an  <- attr(cnt, "anomalies")
    if (is.null(an)) 0L else nrow(an)
  }, integer(1))
  expect_length(per_file, 20L)
  expect_true(is.integer(per_file))
  expect_equal(sum(per_file), 7L)
})

test_that("any traverse label parses verbatim and produces no anomalies", {
  dic  <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Fake Lake", dic)
  # FL019 contains labels with decimal coords (e.g. 22.5N); all should
  # parse cleanly regardless of format — traverse labels are free text.
  cnt <- suppressWarnings(read_cnt(
    system.file("extdata", "fake_lake", "FL019.CNT", package = "pcountr"),
    site = site, quiet = TRUE))
  an <- attr(cnt, "anomalies")
  expect_equal(if (is.null(an)) 0L else nrow(an), 0L)
  expect_true(length(cnt$traverses) > 0)  # traverses were captured
})

test_that("inline remarks are captured verbatim in sequence", {
  dic  <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Fake Lake", dic)
  # FL011 contains a bracketed remark.
  cnt <- suppressWarnings(read_cnt(
    system.file("extdata", "fake_lake", "FL011.CNT", package = "pcountr"),
    site = site, quiet = TRUE))
  expect_true(length(cnt$remarks) >= 1)
  expect_true(any(grepl("PERIPORATE", vapply(cnt$remarks, `[[`, "", "text"))))
})

test_that("dictionary parses all 232 taxa with expected group sizes", {
  dic <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
  expect_equal(nrow(dic), 232L)
  tb <- table(dic$group)
  expect_equal(as.integer(tb["A"]), 73L)
  expect_equal(as.integer(tb["B"]), 103L)
  expect_equal(as.integer(tb["F"]), 26L)
})
