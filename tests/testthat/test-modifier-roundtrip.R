# Tests for preservation modifier round-trip: CNT → pollen_count → YAML → read back.
#
# The bug fixed in v0.5.6: .tokenise_stream() built CNT events with `pres_set`
# instead of the `base`/`pres`/`hidden` fields expected by write_pollen_count().
# For grains with modifier `9` (hidden), write_pollen_count() would emit
# `hidden: false` and `pres: null` into the YAML event, so hidden status and
# the `9` in the preservation string were silently dropped on round-trip. The
# `0` (half-grain) modifier was also dropped from `pres`, though `weight` was
# preserved independently.

# ── Helpers ──────────────────────────────────────────────────────────────────

make_cnt <- function(stream, tmpdir = tempdir()) {
  # Writes a minimal well-formed CNT file and returns the path.
  # header lines 1-2 are ignored by the parser; lines 3-5 are cfg/sum/title.
  lines <- c(
    "PCounT 2.0",
    "count file",
    "ECG.DIC, 1.0, 12000, 10420, 0, 1;",
    "POLLEN SUM = AB",
    "Test Sample",
    paste0("{slide1}", stream)
  )
  path <- tempfile(tmpdir = tmpdir, fileext = ".CNT")
  writeLines(lines, path)
  path
}

# ── Token parsing (CNT grain data frame) ─────────────────────────────────────

test_that("CNT parser: modifier 9 sets hidden=TRUE in grains data frame", {
  path <- make_cnt("B1B19A1")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  g <- cnt$grains
  expect_equal(nrow(g), 3L)

  # B1  — normal grain
  expect_false(g$hidden[1])
  expect_equal(g$pres[1], "1")
  expect_equal(g$weight[1], 1.0)

  # B19 — hidden grain
  expect_true(g$hidden[2])
  expect_equal(g$weight[2], 1.0)

  # A1  — normal grain, unaffected
  expect_false(g$hidden[3])
})

test_that("CNT parser: modifier 0 sets weight=0.5 in grains data frame", {
  path <- make_cnt("I1I80")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  g <- cnt$grains
  expect_equal(nrow(g), 2L)
  expect_equal(g$weight[1], 1.0)   # I1  — full grain
  expect_equal(g$weight[2], 0.5)   # I80 — half grain
  expect_false(g$hidden[2])
})

test_that("CNT parser: combined modifier 90 sets both hidden and weight=0.5", {
  path <- make_cnt("A1A190")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  g <- cnt$grains
  expect_equal(nrow(g), 2L)
  expect_true(g$hidden[2])
  expect_equal(g$weight[2], 0.5)
})

# ── CNT event stream ──────────────────────────────────────────────────────────

test_that("CNT events carry base, pres, hidden fields (not pres_set)", {
  path <- make_cnt("B1.B19I80A190.")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  grain_evs <- Filter(function(e) e$type == "grain", cnt$events)
  expect_equal(length(grain_evs), 4L)

  # Every event must have the standard fields
  for (e in grain_evs) {
    expect_true("base"   %in% names(e), info = paste("missing base for", e$code))
    expect_true("pres"   %in% names(e), info = paste("missing pres for", e$code))
    expect_true("hidden" %in% names(e), info = paste("missing hidden for", e$code))
    expect_false("pres_set" %in% names(e), info = paste("pres_set leaked into event for", e$code))
  }

  # B1:   base="1", pres="1", hidden=FALSE
  expect_equal(grain_evs[[1]]$base,   "1")
  expect_equal(grain_evs[[1]]$pres,   "1")
  expect_false(grain_evs[[1]]$hidden)

  # B19:  base="1", pres="1;9", hidden=TRUE
  expect_equal(grain_evs[[2]]$base,   "1")
  expect_equal(grain_evs[[2]]$pres,   "1;9")
  expect_true(grain_evs[[2]]$hidden)

  # I80:  base="8", pres="8", hidden=FALSE, weight=0.5
  expect_equal(grain_evs[[3]]$base,   "8")
  expect_equal(grain_evs[[3]]$pres,   "8")
  expect_false(grain_evs[[3]]$hidden)
  expect_equal(grain_evs[[3]]$weight, 0.5)

  # A190: base="1", pres="1;9", hidden=TRUE, weight=0.5
  expect_equal(grain_evs[[4]]$base,   "1")
  expect_equal(grain_evs[[4]]$pres,   "1;9")
  expect_true(grain_evs[[4]]$hidden)
  expect_equal(grain_evs[[4]]$weight, 0.5)
})

# ── YAML round-trip ───────────────────────────────────────────────────────────

test_that("YAML round-trip preserves hidden flag and pres for 9-modifier grains", {
  path <- make_cnt("B1.B19.")
  on.exit(unlink(path), add = TRUE)
  cnt <- read_cnt(path, quiet = TRUE)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp), add = TRUE)
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp)

  g <- cnt2$grains
  expect_equal(nrow(g), 2L)

  # B1  survives unchanged
  expect_false(g$hidden[1])
  expect_equal(g$pres[1], "1")
  expect_equal(g$weight[1], 1.0)

  # B19 — hidden flag and pres must survive the round-trip
  expect_true(g$hidden[2],           info = "hidden=TRUE lost on YAML round-trip")
  expect_equal(g$pres[2], "1;9",     info = "pres '1;9' lost on YAML round-trip")
  expect_equal(g$weight[2], 1.0)
})

test_that("YAML round-trip preserves weight for 0-modifier grains", {
  path <- make_cnt("I1I80")
  on.exit(unlink(path), add = TRUE)
  cnt <- read_cnt(path, quiet = TRUE)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp), add = TRUE)
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp)

  g <- cnt2$grains
  expect_equal(g$weight[1], 1.0)
  expect_equal(g$weight[2], 0.5, info = "weight=0.5 lost on YAML round-trip")
  expect_false(g$hidden[2])
})

test_that("YAML round-trip preserves combined 90-modifier (hidden + half-grain)", {
  path <- make_cnt("A1A190")
  on.exit(unlink(path), add = TRUE)
  cnt <- read_cnt(path, quiet = TRUE)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp), add = TRUE)
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp)

  g <- cnt2$grains
  expect_equal(nrow(g), 2L)
  expect_true(g$hidden[2],        info = "hidden lost for combined 90 modifier")
  expect_equal(g$weight[2], 0.5,  info = "weight=0.5 lost for combined 90 modifier")
  expect_equal(g$pres[2], "1;9",  info = "pres lost for combined 90 modifier")
})

test_that("YAML round-trip: metrics unaffected by hidden/half modifiers after fix", {
  # Stream: B1 (full) + I80 (half, weight 0.5) + . (spike) + B19 (hidden, weight 1)
  # B and I are in ECG.DIC (groups B and A respectively); basic_sum (ABF) = 1+0.5+1 = 2.5
  dic  <- read_dic(system.file("extdata", "ECG.DIC", package = "pcountr"))
  site <- pollen_site("Test", dic)

  path <- make_cnt("B1I80.B19")
  on.exit(unlink(path), add = TRUE)
  cnt  <- read_cnt(path, site = site, quiet = TRUE)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp), add = TRUE)
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp, site = site)

  m  <- count_metrics(cnt)
  m2 <- count_metrics(cnt2)

  expect_equal(m2$total_sum,  m$total_sum)
  expect_equal(m2$basic_sum,  m$basic_sum)
  expect_equal(m2$spike,      m$spike)
})
