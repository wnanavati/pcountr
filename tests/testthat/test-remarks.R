# Tests for extract_remarks(), per-sample slide tracking, and the v0.5.8
# preservation-format fixes.
#
# Three bugs are covered here:
#   1. Modifier-only preservation entries (e.g. `9` with no base digit) were
#      rejected on entry in count_app(). The CNT grain grammar still requires a
#      base digit, so this is tested at the data-model level via pres strings.
#   2. Mid-stream {SLIDE NAME} tokens in a .CNT had no tokeniser branch and were
#      discarded as anomalies, so every slide boundary after the first was lost.
#   3. `pres` changed from ";"-separated ("1;9") to concatenated ("19"), which
#      had silently broken preservation_table(collapse_multistate = TRUE).

# ── Helpers ──────────────────────────────────────────────────────────────────

# Minimal CSV dictionary, so these tests do not depend on the unpublished
# ECG.DIC fixture and will run anywhere.
make_dic_r <- function() {
  path <- tempfile(fileext = ".csv")
  writeLines(c(
    "code,alias,group,name,is_special,value",
    "B,B,B,Betula,FALSE,1",
    "I,I,A,Picea,FALSE,1",
    "A,A,A,Abies,FALSE,1"
  ), path)
  path
}

# Writes a minimal well-formed CNT. `body` is the full count stream including
# its leading {slide} descriptor.
make_cnt_r <- function(body) {
  path <- tempfile(fileext = ".CNT")
  writeLines(c(
    "PCounT 2.0",
    "count file",
    "TEST.csv, 1.0, 12000, 10420, 0, 1;",
    "POLLEN SUM = AB",
    "Test Sample",
    body
  ), path)
  path
}

# Builds a one-sample pollen_site around a CNT body.
make_site_r <- function(body, sample_name = "S001") {
  dic  <- read_dic(make_dic_r())
  path <- make_cnt_r(body)
  cnt  <- read_cnt(path, quiet = TRUE)
  cnt$meta$sample_name <- sample_name
  pollen_site("Test", dic, samples = list(s1 = cnt))
}

# ── extract_remarks(): basic shape ───────────────────────────────────────────

test_that("extract_remarks returns the documented columns", {
  site <- make_site_r("{S1}B1[check this]I8")
  r <- extract_remarks(site)

  expect_s3_class(r, "data.frame")
  expect_equal(names(r),
               c("sample_name", "slide", "traverse", "id", "remark"))
  expect_equal(nrow(r), 1L)
  expect_equal(r$remark[1], "check this")
  expect_equal(r$sample_name[1], "S001")
})

test_that("extract_remarks returns an empty frame when there are no remarks", {
  site <- make_site_r("{S1}B1I8A1")
  r <- extract_remarks(site)

  expect_equal(nrow(r), 0L)
  expect_equal(names(r),
               c("sample_name", "slide", "traverse", "id", "remark"))
})

test_that("extract_remarks rejects non-site input", {
  expect_error(extract_remarks(list()), "pollen_site")
})

# ── The `id` column ──────────────────────────────────────────────────────────

test_that("id defaults to the grain counted before the remark", {
  site <- make_site_r("{S1}B1[here]I8")
  r <- extract_remarks(site)

  expect_equal(r$id[1], "B1")
})

test_that("id = 'after' gives the grain counted after the remark", {
  site <- make_site_r("{S1}B1[here]I8")
  r <- extract_remarks(site, id = "after")

  expect_equal(r$id[1], "I8")
})

test_that("id includes modifier digits in the pres string", {
  # B19 = Betula, base 1, hidden. pres is concatenated, so the ID is "B19".
  site <- make_site_r("{S1}B19[here]I80")
  expect_equal(extract_remarks(site)$id[1], "B19")
  expect_equal(extract_remarks(site, id = "after")$id[1], "I8")
})

test_that("id is NA when no grain precedes the remark", {
  site <- make_site_r("{S1}[opening note]B1")
  expect_true(is.na(extract_remarks(site)$id[1]))
  expect_equal(extract_remarks(site, id = "after")$id[1], "B1")
})

test_that("extract_remarks records the active traverse", {
  site <- make_site_r("{S1}B1/edge/I8[note here]A1")
  expect_equal(extract_remarks(site)$traverse[1], "edge")
})

# ── Slide tracking (per sample, not per site) ────────────────────────────────

test_that("remarks are attributed to the slide active when written", {
  # Leading {S1} names slide 1; mid-stream {S2} starts slide 2.
  site <- make_site_r("{S1}B1[first]I8{S2}A1[second]B19")
  r <- extract_remarks(site)

  expect_equal(nrow(r), 2L)
  expect_equal(r$slide, c("S1", "S2"))
  expect_equal(r$remark, c("first", "second"))
  expect_equal(r$id, c("B1", "A1"))
})

test_that("unnamed slides fall back to their ordinal within the sample", {
  site <- make_site_r("{S1}B1{}A1[on slide two]")
  r <- extract_remarks(site)

  expect_equal(r$slide[1], "2",
               info = "unnamed second slide should report ordinal 2")
})

test_that("a third slide increments correctly", {
  site <- make_site_r("{S1}B1{S2}I8{S3}A1[deep]")
  expect_equal(extract_remarks(site)$slide[1], "S3")
})

# ── Mid-stream {...} is a slide event, not an anomaly ────────────────────────

test_that("mid-stream {SLIDE} tokens produce slide_desc events, not anomalies", {
  path <- make_cnt_r("{S1}B1{S2}I8")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  anoms <- attr(cnt, "anomalies")
  expect_equal(nrow(anoms), 0L,
               info = "mid-stream {...} was previously flagged as unparseable")

  sd <- Filter(function(e) e$type == "slide_desc", cnt$events)
  expect_equal(length(sd), 2L,
               info = "expected slide_desc for the leading and mid-stream tokens")
  expect_equal(vapply(sd, function(e) e$text, ""), c("S1", "S2"))
})

test_that("the leading {...} is emitted as the opening event", {
  path <- make_cnt_r("{S1}B1")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  expect_equal(cnt$events[[1]]$type, "slide_desc")
  expect_equal(cnt$events[[1]]$text, "S1")
  expect_equal(cnt$meta$slide, "S1")   # still on meta for back-compat
})

test_that("slide events do not affect grain counts or metrics", {
  path <- make_cnt_r("{S1}B1{S2}I8{S3}A1")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  expect_equal(nrow(cnt$grains), 3L)
  expect_equal(cnt$grains$code, c("B", "I", "A"))
})

# ── pres format: concatenated, not ";"-separated ─────────────────────────────

test_that("pres is a concatenated digit string", {
  path <- make_cnt_r("{S1}B1B19A190")
  on.exit(unlink(path))
  cnt <- read_cnt(path, quiet = TRUE)

  expect_equal(cnt$grains$pres, c("1", "19", "19"))
  expect_false(any(grepl(";", cnt$grains$pres, fixed = TRUE)))
})

test_that("read_pollen_count strips semicolons from legacy pres strings", {
  # Simulates a YAML written before v0.5.8, where pres was "1;9".
  path <- make_cnt_r("{S1}B19")
  on.exit(unlink(path), add = TRUE)
  cnt <- read_cnt(path, quiet = TRUE)

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp), add = TRUE)
  write_pollen_count(cnt, tmp)

  # Rewrite the pres value in the old separated form, then read back.
  txt <- readLines(tmp)
  txt <- sub("pres: *['\"]?19['\"]?", 'pres: "1;9"', txt)
  writeLines(txt, tmp)

  cnt2 <- read_pollen_count(tmp)
  expect_equal(cnt2$grains$pres[1], "19",
               info = "legacy '1;9' should normalise to '19' on read")
})

test_that("preservation_table collapses multi-state grains after the pres change", {
  # B19 carries states 1 and 9. default_precedence is 8 > 6 > 2 > 9 > 1,
  # so the grain must collapse to class "9", not to the literal string "19".
  dic  <- read_dic(make_dic_r())
  site <- pollen_site("Test", dic)
  path <- make_cnt_r("{S1}B1B19")
  on.exit(unlink(path))
  cnt  <- read_cnt(path, quiet = TRUE, site = site)

  tab <- preservation_table(cnt, collapse_multistate = TRUE)
  expect_true("9" %in% colnames(tab),
              info = "multi-state grain failed to collapse; separator regression")
  expect_false("19" %in% colnames(tab))
  expect_equal(sum(tab), 2)
})

test_that("preservation_table keeps raw labels when not collapsing", {
  dic  <- read_dic(make_dic_r())
  site <- pollen_site("Test", dic)
  path <- make_cnt_r("{S1}B1I80")
  on.exit(unlink(path))
  cnt  <- read_cnt(path, quiet = TRUE, site = site)

  tab <- preservation_table(cnt)
  # I80 = base 8, half-grain, so PCount's raw label is "80".
  expect_true(all(c("1", "80") %in% colnames(tab)))
  expect_equal(sum(tab), 1.5)
})
