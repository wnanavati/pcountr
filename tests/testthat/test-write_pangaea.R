# Tests for write_pangaea() and the site-level georeferencing it depends on.
# Fake Lake carries no coordinates, so each test sets them explicitly -- which
# is also the behaviour being checked: georeferencing is optional everywhere
# except here.

fl_site <- function(...) {
  fl <- system.file("extdata", "fake_lake", package = "pcountr")
  suppressWarnings(read_site(fl,
    metadata = file.path(fl, "metadata_FL.csv"),
    dic      = file.path(fl, "ECG.csv"),
    quiet    = TRUE, ...))
}

# --- georeferencing on pollen_site() --------------------------------------

test_that("a site carries latitude, longitude and elevation when given", {
  s <- fl_site(latitude = 43.0731, longitude = -89.4012, elevation = 259)
  expect_equal(s$latitude, 43.0731)
  expect_equal(s$longitude, -89.4012)
  expect_equal(s$elevation, 259)
})

test_that("georeferencing is optional and defaults to NA", {
  s <- fl_site()
  expect_true(is.na(s$latitude))
  expect_true(is.na(s$longitude))
})

test_that("an out-of-range latitude is rejected", {
  dic <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC",
                              package = "pcountr"))
  expect_error(pollen_site("x", dic, latitude = 91), "between -90 and 90")
  expect_error(pollen_site("x", dic, longitude = -181), "between -180 and 180")
})

test_that("a non-numeric coordinate is rejected rather than coerced to NA", {
  dic <- read_dic(system.file("extdata", "fake_lake", "ECG.DIC",
                              package = "pcountr"))
  expect_error(pollen_site("x", dic, latitude = "forty-three"), "must be numeric")
})

test_that("collection_date accepts an ISO string", {
  s <- fl_site(latitude = 43, longitude = -89, collection_date = "2024-05-13")
  expect_s3_class(s$collection_date, "Date")
  expect_equal(format(s$collection_date, "%Y-%m-%d"), "2024-05-13")
})

# --- write_pangaea() -------------------------------------------------------

test_that("a site with no coordinates still writes, leaving them blank", {
  # The file is a draft to finish before submission, like a .tlx finished in
  # Tilia -- so missing georeferencing is reported, not fatal.
  f <- tempfile(fileext = ".txt")
  expect_message(write_pangaea(fl_site(), f), "Incomplete before submission")
  expect_true(file.exists(f))
  tab <- utils::read.delim(f, check.names = FALSE)
  expect_true(all(is.na(tab$Latitude)))
  expect_true(all(is.na(tab$Longitude)))
})

test_that("position columns are present and populated when set", {
  f <- tempfile(fileext = ".txt")
  suppressMessages(
    write_pangaea(fl_site(latitude = 43.0731, longitude = -89.4012), f))
  tab <- utils::read.delim(f, check.names = FALSE)
  expect_equal(unique(tab$Latitude), 43.0731)
  expect_equal(unique(tab$Longitude), -89.4012)
})

test_that("the file is TAB-delimited with the event label first", {
  f <- tempfile(fileext = ".txt")
  suppressMessages(
    write_pangaea(fl_site(latitude = 43, longitude = -89), f))
  hdr <- strsplit(readLines(f, n = 1L), "\t", fixed = TRUE)[[1]]
  expect_equal(hdr[1], "Event")
  expect_equal(hdr[2], "Latitude")
  expect_true("Depth, sediment/rock [m]" %in% hdr)
  expect_true(length(hdr) > 5)
})

test_that("depth is converted from cm to m", {
  f <- tempfile(fileext = ".txt")
  s <- fl_site(latitude = 43, longitude = -89)
  suppressMessages(write_pangaea(s, f))
  tab <- utils::read.delim(f, check.names = FALSE)
  mat <- site_matrix(s)
  expect_equal(tab[["Depth, sediment/rock [m]"]],
               unname(round(mat$DepTop / 100, 4)))
})

test_that("taxon columns carry the unit in square brackets", {
  s <- fl_site(latitude = 43, longitude = -89)
  for (w in c("counts", "percent")) {
    f <- tempfile(fileext = ".txt")
    suppressMessages(write_pangaea(s, f, what = w))
    hdr <- strsplit(readLines(f, n = 1L), "\t", fixed = TRUE)[[1]]
    unit <- if (w == "counts") "[#]" else "[%]"
    expect_true(any(grepl(unit, tail(hdr, -9), fixed = TRUE)),
                info = paste("no", unit, "header for what =", w))
  }
})

test_that("each `what` writes the matching site_matrix table", {
  s <- fl_site(latitude = 43, longitude = -89)
  f <- tempfile(fileext = ".txt")
  suppressMessages(write_pangaea(s, f, what = "percent", digits = 6))
  tab <- utils::read.delim(f, check.names = FALSE)
  mat <- site_matrix(s)
  first_taxon <- paste0(colnames(mat$TaxaPerc)[1], " [%]")
  expect_equal(tab[[first_taxon]],
               unname(round(as.numeric(mat$TaxaPerc[, 1]), 6)))
})

test_that("a .txt extension is appended when absent", {
  s <- fl_site(latitude = 43, longitude = -89)
  f <- tempfile()
  out <- suppressMessages(write_pangaea(s, f))
  expect_true(grepl("\\.txt$", out))
  expect_true(file.exists(out))
})

# --- site metadata survives the YAML round trip ---------------------------

test_that("site georeferencing is written to YAML and read back", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  dic  <- read_dic(file.path(fl, "ECG.csv"))
  site <- pollen_site("FL", dic, latitude = 43.0731, longitude = -89.4012,
                      elevation = 259, collection_date = "2024-05-13",
                      device = "Livingstone corer", event_label = "FL24-1")
  cnt  <- suppressWarnings(read_cnt(file.path(fl, "FL001.CNT"),
                                    site = site, quiet = TRUE))
  f <- tempfile(fileext = ".yaml")
  write_pollen_count(cnt, f)

  back <- read_pollen_count(f)
  expect_equal(back$meta$latitude, 43.0731)
  expect_equal(back$meta$longitude, -89.4012)
  expect_equal(back$meta$elevation, 259)
  expect_equal(back$meta$collection_date, "2024-05-13")
  expect_equal(back$meta$device, "Livingstone corer")
  expect_equal(back$meta$event_label, "FL24-1")
})

test_that("read_site lifts site metadata back off the samples", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  dic  <- read_dic(file.path(fl, "ECG.csv"))
  site <- pollen_site("FL", dic, latitude = 43.0731, longitude = -89.4012)
  dir  <- tempfile("fl_yaml_"); dir.create(dir)
  for (f in list.files(fl, pattern = "^FL00[123]\\.CNT$", full.names = TRUE)) {
    cnt <- suppressWarnings(read_cnt(f, site = site, quiet = TRUE))
    write_pollen_count(cnt, file.path(dir, sub("\\.CNT$", ".yaml", basename(f))))
  }
  s2 <- suppressWarnings(read_site(dir, dic = file.path(fl, "ECG.csv"),
                                   quiet = TRUE))
  expect_equal(s2$latitude, 43.0731)
  expect_equal(s2$longitude, -89.4012)
})

test_that("samples at different positions are reported, not warned about", {
  # A folder may hold surface samples from many places. That is legitimate,
  # so read_site() reports the spread instead of warning: a warning firing on
  # every correct transect would be ignored by the time it mattered.
  fl  <- system.file("extdata", "fake_lake", package = "pcountr")
  dic <- read_dic(file.path(fl, "ECG.csv"))
  dir <- tempfile("fl_multi_"); dir.create(dir)
  lats  <- c(43.0731, 46.8721, 64.8378)
  files <- list.files(fl, pattern = "^FL00[123]\\.CNT$", full.names = TRUE)
  for (i in seq_along(files)) {
    s_i <- pollen_site("AK", dic, latitude = lats[i], longitude = -150,
                       event_label = paste0("AK-", i))
    c1  <- suppressWarnings(read_cnt(files[i], site = s_i, quiet = TRUE))
    write_pollen_count(c1, file.path(dir, sprintf("S%02d.yaml", i)))
  }

  site <- expect_no_warning(
    read_site(dir, dic = file.path(fl, "ECG.csv"), quiet = TRUE))

  expect_true(is.na(site$latitude))                       # no single value
  expect_equal(attr(site, "n_distinct")[["latitude"]], 3L)
  expect_equal(site$longitude, -150)                      # agreed field resolves
  expect_output(print(site), "positions: 3 distinct")
})

test_that("a multi-location folder exports one PANGAEA row per position", {
  fl  <- system.file("extdata", "fake_lake", package = "pcountr")
  dic <- read_dic(file.path(fl, "ECG.csv"))
  dir <- tempfile("fl_ak_"); dir.create(dir)
  lats  <- c(43.0731, 46.8721)
  files <- list.files(fl, pattern = "^FL00[12]\\.CNT$", full.names = TRUE)
  for (i in seq_along(files)) {
    s_i <- pollen_site("AK", dic, latitude = lats[i], longitude = -150,
                       event_label = paste0("AK-", i))
    c1  <- suppressWarnings(read_cnt(files[i], site = s_i, quiet = TRUE))
    c1$meta$depth_top <- i          # site_matrix needs a depth
    write_pollen_count(c1, file.path(dir, sprintf("S%02d.yaml", i)))
  }
  site <- suppressWarnings(read_site(dir, dic = file.path(fl, "ECG.csv"),
                                     quiet = TRUE))
  f <- tempfile(fileext = ".txt")
  suppressMessages(write_pangaea(site, f))
  tab <- utils::read.delim(f, check.names = FALSE)

  expect_equal(sort(tab$Latitude), sort(lats))     # per row, not one value
  expect_equal(sort(tab$Event), c("AK-1", "AK-2")) # per-sample event labels
})

test_that("an explicit read_site() argument overrides what the samples carry", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  dic  <- read_dic(file.path(fl, "ECG.csv"))
  site <- pollen_site("FL", dic, latitude = 43.0731, longitude = -89.4012)
  dir  <- tempfile("fl_over_"); dir.create(dir)
  cnt  <- suppressWarnings(read_cnt(file.path(fl, "FL001.CNT"),
                                    site = site, quiet = TRUE))
  write_pollen_count(cnt, file.path(dir, "FL001.yaml"))
  s2 <- suppressWarnings(read_site(dir, dic = file.path(fl, "ECG.csv"),
                                   latitude = 10, quiet = TRUE))
  expect_equal(s2$latitude, 10)
  expect_equal(s2$longitude, -89.4012)   # untouched, still from the sample
})

test_that("extract_metadata carries the site-level columns", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  s    <- suppressWarnings(read_site(fl, dic = file.path(fl, "ECG.csv"),
                                     metadata = file.path(fl, "metadata_FL.csv"),
                                     latitude = 43.0731, quiet = TRUE))
  meta <- extract_metadata(s)
  expect_true(all(c("latitude", "longitude", "elevation", "collection_date",
                    "device", "event_label") %in% names(meta)))
})

test_that("write_site() persists site metadata set on read_site()", {
  # Regression: samples built by read_site() reference the bare site created
  # before georeferencing is resolved, so write_pollen_count()'s x$site
  # fallback read NA and the whole round trip silently lost the position.
  # write_site() now takes the values from the site it was handed.
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  site <- suppressWarnings(read_site(fl, dic = file.path(fl, "ECG.csv"),
                                     latitude = 43.0731, longitude = -89.4012,
                                     elevation = 259, device = "corer",
                                     quiet = TRUE))
  yd <- tempfile("fl_yaml_"); dir.create(yd)
  invisible(suppressMessages(write_site(site, yd)))

  back <- suppressWarnings(read_site(yd, dic = file.path(fl, "ECG.csv"),
                                     quiet = TRUE))
  expect_equal(back$latitude, 43.0731)
  expect_equal(back$longitude, -89.4012)
  expect_equal(back$elevation, 259)
  expect_equal(back$device, "corer")
})

test_that("a position assigned after loading still reaches the YAML", {
  # The documented way to add a position to an already-loaded site.
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  site <- suppressWarnings(read_site(fl, dic = file.path(fl, "ECG.csv"),
                                     quiet = TRUE))
  site$latitude  <- 46.8721
  site$longitude <- -113.9940

  yd <- tempfile("fl_post_"); dir.create(yd)
  invisible(suppressMessages(write_site(site, yd)))
  back <- suppressWarnings(read_site(yd, dic = file.path(fl, "ECG.csv"),
                                     quiet = TRUE))
  expect_equal(back$latitude, 46.8721)
  expect_equal(back$longitude, -113.9940)
})

test_that("apply_metadata() lifts edited site columns onto the site", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  site <- suppressWarnings(read_site(fl, dic = file.path(fl, "ECG.csv"),
                                     latitude = 43.0731, quiet = TRUE))
  yd <- tempfile("fl_apply_"); dir.create(yd)
  site <- suppressMessages(write_site(site, yd))

  csv <- file.path(yd, "meta.csv")
  invisible(suppressMessages(extract_metadata(site, file = csv)))
  m <- utils::read.csv(csv); m$elevation <- 300
  utils::write.csv(m, csv, row.names = FALSE)

  site2 <- suppressMessages(apply_metadata(site, csv))
  expect_equal(site2$elevation, 300)
})

test_that("a site with no depths fails naming PANGAEA's geocode requirement", {
  # Depth is the one field that cannot be left blank: site_matrix() drops
  # depth-less samples, so the table would have no rows. The message should
  # name PANGAEA rather than surfacing site_matrix()'s error.
  fl <- system.file("extdata", "fake_lake", package = "pcountr")
  nodepth <- suppressWarnings(read_site(fl, dic = file.path(fl, "ECG.csv"),
                                        quiet = TRUE))   # no metadata sheet
  expect_error(write_pangaea(nodepth, tempfile(fileext = ".txt")),
               "PANGAEA requires depth")
  expect_error(write_pangaea(nodepth, tempfile(fileext = ".txt")),
               "set_metadata")
})

test_that("a site-level position fills rows whose samples carry none", {
  # read_site(latitude=) sets the site, not the samples. Without a fallback
  # in pull(), every exported row came out blank.
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  site <- suppressWarnings(read_site(fl,
    metadata = file.path(fl, "metadata_FL.csv"),
    dic = file.path(fl, "ECG.csv"),
    latitude = 43.0731, longitude = -89.4012, quiet = TRUE))
  f <- tempfile(fileext = ".txt")
  suppressMessages(write_pangaea(site, f))
  tab <- utils::read.delim(f, check.names = FALSE)
  expect_equal(unique(tab$Latitude), 43.0731)
  expect_equal(unique(tab$Longitude), -89.4012)
})

test_that("the report does not call a site-filled column blank", {
  fl   <- system.file("extdata", "fake_lake", package = "pcountr")
  site <- suppressWarnings(read_site(fl,
    metadata = file.path(fl, "metadata_FL.csv"),
    dic = file.path(fl, "ECG.csv"),
    latitude = 43.0731, longitude = -89.4012, quiet = TRUE))
  msg <- paste(capture.output(
    write_pangaea(site, tempfile(fileext = ".txt")), type = "message"),
    collapse = " ")
  expect_false(grepl("latitude", msg))
  expect_true(grepl("elevation", msg))   # genuinely unset, still reported
})
