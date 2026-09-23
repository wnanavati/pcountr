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

# --- sum-group / dictionary mismatch --------------------------------------
# A dictionary drafted by build_dic_neotoma() carries Neotoma's ecological
# group codes, which the default pollen_sum of c("A","B","F") cannot match.
# Before this check the result was a silent sum of 0.

.neotoma_style_dic <- function() {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      code  = c("AL", "PI", "CY"),
      name  = c("Alnus undiff.", "Pinus undiff.", "Cyperaceae undiff."),
      group = c("TRSH", "TRSH", "UPHE"),
      stringsAsFactors = FALSE
    ),
    path, row.names = FALSE
  )
  read_dic_csv(path)
}

.fake_lake_dic <- function() {
  read_dic(system.file("extdata", "fake_lake", "ECG.DIC", package = "pcountr"))
}

test_that("pollen_site warns when no sum group occurs in the dictionary", {
  expect_warning(pollen_site("N", .neotoma_style_dic()),
                 "None of the sum groups")
})

test_that("the mismatch warning names the groups that are present", {
  # Naming them is what makes the warning actionable.
  expect_warning(pollen_site("N", .neotoma_style_dic()), "TRSH, UPHE")
})

test_that("no warning when the dictionary uses the default sum groups", {
  expect_no_warning(pollen_site("Fake Lake", .fake_lake_dic()))
})

test_that("a partial sum-group match does not warn", {
  # A dictionary may legitimately lack one group; only an empty
  # intersection is worth reporting.
  expect_no_warning(
    pollen_site("Fake Lake", .fake_lake_dic(), pollen_sum = c("A", "ZZZ"))
  )
})

test_that("warn_sum = FALSE suppresses the mismatch warning", {
  expect_no_warning(pollen_site("N", .neotoma_style_dic(), warn_sum = FALSE))
})

test_that("passing the dictionary's own groups resolves the mismatch", {
  expect_no_warning(
    pollen_site("N", .neotoma_style_dic(), pollen_sum = c("TRSH", "UPHE"))
  )
})
