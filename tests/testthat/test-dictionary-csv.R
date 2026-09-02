extdata <- function(...) system.file("extdata", ..., package = "pcountr")

# ---------------------------------------------------------------------------
# read_dic_csv
# ---------------------------------------------------------------------------

test_that("template CSV loads as a valid pollen_dictionary", {
  dic <- read_dic_csv(extdata("dictionary_template.csv"))
  expect_s3_class(dic, "pollen_dictionary")
  expect_true(all(c("code","alias","group","name","is_special") %in% names(dic)))
  expect_gt(nrow(dic), 0L)
})

test_that("spike row is marked is_special", {
  dic <- read_dic_csv(extdata("dictionary_template.csv"))
  spike_row <- dic[dic$code == ".", ]
  expect_equal(nrow(spike_row), 1L)
  expect_true(spike_row$is_special)
})

test_that("hash-prefixed non-pollen codes are marked is_special", {
  dic <- read_dic_csv(extdata("dictionary_template.csv"))
  npp <- dic[grepl("^#", dic$code), ]
  expect_true(nrow(npp) > 0L)
  expect_true(all(npp$is_special))
})

test_that("regular pollen taxa are not is_special", {
  dic <- read_dic_csv(extdata("dictionary_template.csv"))
  pollen <- dic[dic$group %in% c("A","B","F","Q") & !dic$is_special, ]
  expect_gt(nrow(pollen), 0L)
})

test_that("column names are matched case-insensitively", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(data.frame(
    Code  = c("B", "."),
    Name  = c("Betula", "Microspheres"),
    Group = c("A", ""),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  dic <- read_dic_csv(tmp)
  expect_equal(nrow(dic), 2L)
  expect_equal(dic$code[1], "B")
})

test_that("missing required column gives an informative error", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(data.frame(code="B", name="Betula", stringsAsFactors=FALSE),
            tmp, row.names=FALSE)   # no 'group' column
  expect_error(read_dic_csv(tmp), regexp = "group")
})

test_that("blank rows are silently dropped", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(data.frame(
    code  = c("A", "", "B"),
    name  = c("Alnus", "", "Betula"),
    group = c("A", "", "A"),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  dic <- read_dic_csv(tmp)
  expect_equal(nrow(dic), 2L)
})

test_that("optional alias and is_special columns can be absent", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(data.frame(code="A", name="Alnus", group="A",
                       stringsAsFactors=FALSE), tmp, row.names=FALSE)
  dic <- read_dic_csv(tmp)
  expect_true("alias"      %in% names(dic))
  expect_true("is_special" %in% names(dic))
})

# ---------------------------------------------------------------------------
# read_dic auto-detection
# ---------------------------------------------------------------------------

test_that("read_dic dispatches to CSV reader for .csv extension", {
  dic_csv <- read_dic_csv(extdata("dictionary_template.csv"))
  dic_auto <- read_dic(extdata("dictionary_template.csv"))
  expect_identical(dic_csv, dic_auto)
})

test_that("read_dic still reads legacy .DIC files", {
  dic <- read_dic(extdata("fake_lake", "ECG.DIC"))
  expect_s3_class(dic, "pollen_dictionary")
  expect_equal(nrow(dic), 232L)
})

# ---------------------------------------------------------------------------
# write_dic_csv
# ---------------------------------------------------------------------------

test_that("write_dic_csv produces a readable CSV that round-trips", {
  dic_orig <- read_dic(extdata("fake_lake", "ECG.DIC"))
  tmp      <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  write_dic_csv(dic_orig, tmp)
  dic_rt <- read_dic_csv(tmp)

  expect_equal(nrow(dic_rt),  nrow(dic_orig))
  expect_equal(dic_rt$code,   dic_orig$code)
  expect_equal(dic_rt$group,  dic_orig$group)
  expect_equal(dic_rt$name,   dic_orig$name)
})

test_that("write_dic_csv returns path invisibly", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  dic <- read_dic(extdata("fake_lake", "ECG.DIC"))
  result <- write_dic_csv(dic, tmp)
  expect_equal(result, tmp)
})

test_that("migrated DIC preserves is_special for spike and # codes", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  dic_orig <- read_dic(extdata("fake_lake", "ECG.DIC"))
  write_dic_csv(dic_orig, tmp)
  dic_rt <- read_dic_csv(tmp)
  # Spike
  expect_true(dic_rt$is_special[dic_rt$code == "."])
  # Hash-prefixed codes
  hash_rows <- dic_rt[grepl("^#", dic_rt$code), ]
  if (nrow(hash_rows) > 0) expect_true(all(hash_rows$is_special))
})

# ---------------------------------------------------------------------------
# sample_name in pollen_count / YAML round-trip
# ---------------------------------------------------------------------------

test_that("sample_name round-trips through YAML", {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("LMSH001.CNT"), site=site, quiet=TRUE)
  )
  cnt$meta$sample_name <- "FL24#001"

  tmp <- tempfile(fileext = ".yaml")
  on.exit(unlink(tmp))
  write_pollen_count(cnt, tmp)
  cnt2 <- read_pollen_count(tmp)
  expect_equal(cnt2$meta$sample_name, "FL24#001")
})
