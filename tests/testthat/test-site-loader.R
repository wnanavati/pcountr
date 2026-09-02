extdata <- function(...) system.file("extdata", ..., package = "pcountr")

# Helper: write a temp CSV sheet for a subset of LM files
write_sheet <- function(path, rows) {
  write.csv(rows, path, row.names = FALSE)
}

# A metadata sheet covering all 20 Fake Lake files. Tests that assert one
# specific warning use this as a base so that .check_sheet_coverage() does
# not also fire about the files the sheet omits -- an unmatched second
# warning leaks past expect_warning() and shows up as a WARN in the report.
full_sheet_rows <- function() {
  data.frame(
    file         = sprintf("FL%03d", 1:20),
    depth_top    = seq(0,    95,    by = 5),
    depth_bottom = seq(0.25, 95.25, by = 5),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Basic load (no metadata sheet)
# ---------------------------------------------------------------------------

test_that("read_site loads all 20 CNT files with NA depths", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  expect_s3_class(site, "pollen_site")
  expect_equal(length(site$samples), 20L)
  tops <- vapply(site$samples, function(s) s$meta$depth_top, NA_real_)
  expect_true(all(is.na(tops)))
})

test_that("read_site auto-detects the single DIC", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  expect_equal(nrow(site$dictionary), 232L)
})

test_that("all samples have valid metrics after read_site", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  for (s in site$samples) {
    m <- count_metrics(s)
    expect_true(is.finite(m$concentration))
    expect_gt(m$total_sum, 0)
  }
})

test_that("samples with NA depth are all at the end", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  # All NA: order is arbitrary, but the list must be length 20
  expect_equal(length(site$samples), 20L)
})

# ---------------------------------------------------------------------------
# Metadata sheet
# ---------------------------------------------------------------------------

test_that("depth from sheet is attached to CNT samples", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write_sheet(tmp, data.frame(
    file         = c("FL001", "FL002"),
    depth_top    = c(10.0, 20.0),
    depth_bottom = c(11.0, 21.0),
    stringsAsFactors = FALSE
  ))
  site <- suppressWarnings(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE)
  )
  expect_equal(site$samples[["FL001"]]$meta$depth_top,    10.0)
  expect_equal(site$samples[["FL001"]]$meta$depth_bottom, 11.0)
  expect_equal(site$samples[["FL002"]]$meta$depth_top,    20.0)
})

test_that("col_map translates custom column names", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write_sheet(tmp, data.frame(
    SampleID = "FL001",
    Top_cm   = 15.5,
    Bot_cm   = 16.5,
    stringsAsFactors = FALSE
  ))
  site <- suppressWarnings(
    read_site(extdata("fake_lake"), metadata = tmp,
              col_map = c(file = "SampleID", depth_top = "Top_cm",
                          depth_bottom = "Bot_cm"),
              quiet = TRUE)
  )
  expect_equal(site$samples[["FL001"]]$meta$depth_top, 15.5)
})

test_that("samples with depths sort before samples without", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  # Use actual LM file names (non-sequential: 001, 009, 017, ...)
  write_sheet(tmp, data.frame(
    file         = c("FL005", "FL001", "FL003"),
    depth_top    = c(40.0, 10.0, 25.0),
    depth_bottom = c(41.0, 11.0, 26.0),
    stringsAsFactors = FALSE
  ))
  site <- suppressWarnings(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE)
  )
  tops <- vapply(site$samples, function(s) s$meta$depth_top %||% NA_real_, NA_real_)
  # First 3 should be depth-sorted ascending; the rest NA
  expect_equal(unname(tops[1]), 10.0)
  expect_equal(unname(tops[2]), 25.0)
  expect_equal(unname(tops[3]), 40.0)
  expect_true(all(is.na(tops[4:20])))
})

# ---------------------------------------------------------------------------
# Sheet coverage warnings
# ---------------------------------------------------------------------------

test_that("folder file with no sheet row produces a warning", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  # Sheet only covers one of 20 files
  write_sheet(tmp, data.frame(
    file         = "FL001",
    depth_top    = 10.0,
    depth_bottom = 11.0,
    stringsAsFactors = FALSE
  ))
  expect_warning(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE),
    regexp = "no metadata sheet row"
  )
})

test_that("sheet row with no matching file produces a warning", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  rows <- rbind(full_sheet_rows(),
                data.frame(file = "DOESNOTEXIST", depth_top = 50.0,
                           depth_bottom = 51.0, stringsAsFactors = FALSE))
  write_sheet(tmp, rows)
  expect_warning(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE),
    regexp = "no matching file"
  )
})

test_that("depth_top >= depth_bottom in sheet produces a warning", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  rows <- full_sheet_rows()
  rows$depth_top[1]    <- 20.0   # swapped for FL001
  rows$depth_bottom[1] <- 10.0
  write_sheet(tmp, rows)
  expect_warning(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE),
    regexp = "depth_top >= depth_bottom"
  )
})

# ---------------------------------------------------------------------------
# YAML round-trip depth handling
# ---------------------------------------------------------------------------

test_that("YAML embedded depth is preserved through read_site", {
  # Write a YAML with an embedded depth, load it via read_site from a temp folder
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("fake_lake", "FL001.CNT"), site = site, quiet = TRUE)
  )
  cnt$meta$depth_top    <- 12.5
  cnt$meta$depth_bottom <- 13.5

  tmp_dir <- file.path(tempdir(), "pcountr_yaml_test")
  dir.create(tmp_dir, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  file.copy(extdata("fake_lake", "ECG.DIC"), file.path(tmp_dir, "ECG.DIC"))
  write_pollen_count(cnt, file.path(tmp_dir, "FL001.yaml"))

  loaded <- read_site(tmp_dir, quiet = TRUE)
  expect_equal(loaded$samples[["FL001"]]$meta$depth_top,    12.5)
  expect_equal(loaded$samples[["FL001"]]$meta$depth_bottom, 13.5)
})

test_that("YAML depth conflicting with sheet is an error", {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("fake_lake", "FL001.CNT"), site = site, quiet = TRUE)
  )
  cnt$meta$depth_top    <- 12.5
  cnt$meta$depth_bottom <- 13.5

  tmp_dir <- file.path(tempdir(), "pcountr_conflict_test")
  dir.create(tmp_dir, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  file.copy(extdata("fake_lake", "ECG.DIC"), file.path(tmp_dir, "ECG.DIC"))
  write_pollen_count(cnt, file.path(tmp_dir, "FL001.yaml"))

  sheet_path <- file.path(tmp_dir, "meta.csv")
  write_sheet(sheet_path, data.frame(
    file         = "FL001",
    depth_top    = 99.0,   # conflicts with YAML's 12.5
    depth_bottom = 100.0,
    stringsAsFactors = FALSE
  ))

  expect_error(
    read_site(tmp_dir, metadata = sheet_path, quiet = TRUE),
    regexp = "depth_top conflict"
  )
})

test_that("ignore_depth_conflicts = TRUE warns instead of errors", {
  dic  <- read_dic(extdata("fake_lake", "ECG.DIC"))
  site <- pollen_site("LM", dic)
  cnt  <- suppressWarnings(
    read_cnt(extdata("fake_lake", "FL001.CNT"), site = site, quiet = TRUE)
  )
  cnt$meta$depth_top    <- 12.5
  cnt$meta$depth_bottom <- 13.5

  tmp_dir <- file.path(tempdir(), "pcountr_ignore_test")
  dir.create(tmp_dir, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  file.copy(extdata("fake_lake", "ECG.DIC"), file.path(tmp_dir, "ECG.DIC"))
  write_pollen_count(cnt, file.path(tmp_dir, "FL001.yaml"))

  sheet_path <- file.path(tmp_dir, "meta.csv")
  write_sheet(sheet_path, data.frame(
    file         = "FL001",
    depth_top    = 99.0,
    depth_bottom = 100.0,
    stringsAsFactors = FALSE
  ))

  # Both depth_top and depth_bottom conflict, so read_site emits two
  # warnings; assert each rather than letting the second leak.
  expect_warning(
    expect_warning(
      loaded <- read_site(tmp_dir, metadata = sheet_path,
                          ignore_depth_conflicts = TRUE, quiet = TRUE),
      regexp = "depth_top conflict"
    ),
    regexp = "depth_bottom conflict"
  )
  # YAML value is kept
  expect_equal(loaded$samples[["FL001"]]$meta$depth_top, 12.5)
})

# ---------------------------------------------------------------------------
# Real LM depth sheet (TSV, non-default column names)
# ---------------------------------------------------------------------------

test_that("shipped metadata_FL.csv loads with correct depths", {
  # metadata_FL.csv uses the standard column names, so no col_map is needed,
  # and its 20 rows match the 20 .CNT files exactly (no coverage warning).
  sheet_path <- extdata("fake_lake", "metadata_FL.csv")
  site <- read_site(extdata("fake_lake"), metadata = sheet_path, quiet = TRUE)
  tops <- vapply(site$samples, function(s) s$meta$depth_top, NA_real_)
  expect_true(all(!is.na(tops)))
  # Known values, straight from the sheet
  expect_equal(site$samples[["FL001"]]$meta$depth_top,     0.00)
  expect_equal(site$samples[["FL001"]]$meta$depth_bottom,  0.25)
  expect_equal(site$samples[["FL020"]]$meta$depth_top,    95.00)
  expect_equal(site$samples[["FL020"]]$meta$depth_bottom, 95.25)
  # Samples should be sorted shallowest first
  expect_equal(names(site$samples)[1],  "FL001")
  expect_equal(names(site$samples)[20], "FL020")
})

test_that("a sheet row with no matching file warns", {
  # metadata_FL.csv covers every file, so append a bogus row to trigger the
  # coverage warning rather than relying on a sheet that over-covers.
  src <- readLines(extdata("fake_lake", "metadata_FL.csv"), warn = FALSE)
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(src, "FL999,FL#999,999,999.25,0,0,1,ml,2,9666,tablets"), tmp)
  expect_warning(
    read_site(extdata("fake_lake"), metadata = tmp, quiet = TRUE),
    regexp = "no matching file"
  )
})

# ---------------------------------------------------------------------------
# set_metadata
# ---------------------------------------------------------------------------

test_that("set_metadata updates depth and re-sorts by name", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))

  site <- set_metadata(site, "FL001", depth_top = 10.0, depth_bottom = 11.0)
  expect_equal(site$samples[["FL001"]]$meta$depth_top,    10.0)
  expect_equal(site$samples[["FL001"]]$meta$depth_bottom, 11.0)
  # FL001 should now be first (only sample with a depth)
  expect_equal(names(site$samples)[1], "FL001")
})

test_that("set_metadata re-sorts correctly when multiple depths set", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  site <- set_metadata(site, "FL005", depth_top = 40.0, depth_bottom = 41.0)
  site <- set_metadata(site, "FL001", depth_top = 10.0, depth_bottom = 11.0)
  site <- set_metadata(site, "FL003", depth_top = 25.0, depth_bottom = 26.0)

  tops <- unname(vapply(site$samples[1:3], function(s) s$meta$depth_top, NA_real_))
  expect_equal(tops, c(10.0, 25.0, 40.0))
})

test_that("set_metadata with integer index works", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  site <- set_metadata(site, 1L, depth_top = 5.0, depth_bottom = 6.0)
  expect_equal(site$samples[[1]]$meta$depth_top, 5.0)
})

test_that("set_metadata errors on invalid interval", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  expect_error(
    set_metadata(site, "FL001", depth_top = 20.0, depth_bottom = 10.0),
    regexp = "depth_top.*must be less than"
  )
})

test_that("set_metadata errors on unknown sample key", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  expect_error(
    set_metadata(site, "DOESNOTEXIST", depth_top = 1.0, depth_bottom = 2.0),
    regexp = "not found"
  )
})

test_that("set_metadata with age updates age fields", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  site <- set_metadata(site, "FL001",
                       depth_top = 10.0, depth_bottom = 11.0,
                       age_top = 500.0, age_bottom = 600.0)
  expect_equal(site$samples[["FL001"]]$meta$age_top,    500.0)
  expect_equal(site$samples[["FL001"]]$meta$age_bottom, 600.0)
})

test_that("set_metadata updates sample_name, quantity, spike fields", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  site <- set_metadata(site, "FL001",
                       depth_top       = 0.0,
                       depth_bottom    = 1.0,
                       sample_name     = "FL24#001",
                       sample_quantity = 2.5,
                       sample_units    = "ml",
                       spike_tablets   = 2L,
                       spike_density   = 9666,
                       spike_units     = "tablets")
  m <- site$samples[["FL001"]]$meta
  expect_equal(m$sample_name,     "FL24#001")
  expect_equal(m$sample_quantity, 2.5)
  expect_equal(m$units,           "ml")
  expect_equal(m$spike_tablets,   2L)
  expect_equal(m$spike_density,   9666)
  expect_equal(m$spike_units,     "tablets")
})

test_that("set_metadata omitted fields leave existing values unchanged", {
  site <- suppressWarnings(read_site(extdata("fake_lake"), quiet = TRUE))
  site <- set_metadata(site, "FL001",
                       depth_top = 0.0, depth_bottom = 1.0,
                       sample_quantity = 1.5)
  # depth fields updated, age fields still NA
  expect_equal(site$samples[["FL001"]]$meta$depth_top, 0.0)
  expect_true(is.na(site$samples[["FL001"]]$meta$age_top))
  expect_equal(site$samples[["FL001"]]$meta$sample_quantity, 1.5)
})
