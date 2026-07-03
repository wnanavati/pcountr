test_that("LMSH001 reproduces LM23SH00.RPT to the digit", {
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Little Mosquito Lake", dic)
  cnt  <- read_cnt(system.file("extdata", "LMSH001.CNT", package = "pcountr"),
                   site = site, quiet = TRUE)
  m <- count_metrics(cnt)

  expect_equal(as.numeric(m$group_sums["A"]), 292.5)
  expect_equal(as.numeric(m$group_sums["B"]), 32.0)
  expect_equal(as.numeric(m$group_sums["F"]), 7.0)
  expect_equal(as.numeric(m$group_sums["Q"]), 7.0)
  expect_equal(m$basic_sum, 331.5)
  expect_equal(m$total_sum, 338.5)
  expect_equal(m$spike, 72)
  expect_equal(round(m$ratio, 4), 4.7014)
  expect_equal(round(m$concentration), 90887)
  expect_equal(m$n_traverses, 6L)
  expect_equal(round(m$mean_grains_per_traverse, 2), 56.42)
})

test_that("per-taxon weighted counts match the report", {
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Little Mosquito Lake", dic)
  cnt  <- read_cnt(system.file("extdata", "LMSH001.CNT", package = "pcountr"),
                   site = site, quiet = TRUE)
  g <- cnt$grains[!grepl("^#", cnt$grains$code), ]
  tx <- tapply(g$weight, g$code, sum)
  expect_equal(as.numeric(tx["A"]), 83.0)
  expect_equal(as.numeric(tx["B"]), 139.0)
  expect_equal(as.numeric(tx["I"]), 42.5)   # Picea: includes 5 half-grains
  expect_equal(as.numeric(tx["S"]), 17.0)
})

test_that("YAML round-trip preserves grain count, spike, and metrics", {
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Little Mosquito Lake", dic)
  cnt  <- read_cnt(system.file("extdata", "LMSH001.CNT", package = "pcountr"),
                   site = site, quiet = TRUE)
  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  write_pollen_count(cnt, tmp)

  cnt2 <- read_pollen_count(tmp, site = site)
  expect_equal(nrow(cnt2$grains), nrow(cnt$grains))
  expect_equal(cnt2$spike_n, cnt$spike_n)
  expect_equal(cnt2$traverses, cnt$traverses)

  m2 <- count_metrics(cnt2)
  expect_equal(m2$basic_sum,    331.5)
  expect_equal(m2$total_sum,    338.5)
  expect_equal(m2$spike,        72)
  expect_equal(round(m2$concentration), 90887)
})

test_that("YAML round-trip preserves full event stream and spike positions", {
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("LM", dic)

  # Synthetic count: slide_desc, B1, spike, A1, spike, I8
  # Spike positions (3 and 5) must survive write → read.
  evs <- list(
    list(type="slide_desc", text="slide-1",   position=1L),
    list(type="grain",  code="B", base="1", pres="1", weight=1,
         hidden=FALSE, traverse=NA_character_, position=2L, anomaly=FALSE),
    list(type="spike",  traverse=NA_character_, position=3L),
    list(type="grain",  code="A", base="1", pres="1", weight=1,
         hidden=FALSE, traverse=NA_character_, position=4L, anomaly=FALSE),
    list(type="spike",  traverse=NA_character_, position=5L),
    list(type="grain",  code="I", base="8", pres="8", weight=1,
         hidden=FALSE, traverse=NA_character_, position=6L, anomaly=FALSE)
  )
  grain_evs <- Filter(function(e) e$type == "grain", evs)
  grains <- data.frame(
    code     = vapply(grain_evs, function(e) e$code, ""),
    base     = vapply(grain_evs, function(e) e$base, ""),
    pres     = vapply(grain_evs, function(e) e$pres, ""),
    weight   = as.numeric(vapply(grain_evs, function(e) e$weight, 0)),
    hidden   = vapply(grain_evs, function(e) e$hidden, FALSE),
    traverse = vapply(grain_evs, function(e) e$traverse, ""),
    position = vapply(grain_evs, function(e) e$position, 0L),
    stringsAsFactors = FALSE
  )
  cnt <- pollen_count(grains=grains, spike_n=2L, events=evs, site=site)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp, site=site)

  # Full event list survives round-trip
  expect_equal(length(cnt2$events), length(evs))

  # Spike positions are exact
  spike_pos <- vapply(Filter(function(e) e$type == "spike", cnt2$events),
                      function(e) e$position, 0L)
  expect_equal(spike_pos, c(3L, 5L))

  # Interleaving is correct: position 3 = spike, position 4 = grain A
  expect_equal(cnt2$events[[3]]$type, "spike")
  expect_equal(cnt2$events[[4]]$type, "grain")
  expect_equal(cnt2$events[[4]]$code, "A")

  # Derived fields still correct
  expect_equal(nrow(cnt2$grains), 3L)
  expect_equal(cnt2$spike_n, 2L)
})

test_that("half-grain (code 0) yields weight 0.5", {
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("LM", dic)
  cnt  <- read_cnt(system.file("extdata", "LMSH001.CNT", package = "pcountr"),
                   site = site, quiet = TRUE)
  halves <- cnt$grains[cnt$grains$weight == 0.5, ]
  expect_true(nrow(halves) > 0)
  expect_true(all(grepl("0$", paste0(halves$base, "0"))))
})
