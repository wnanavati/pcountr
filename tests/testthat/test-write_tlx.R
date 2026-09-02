extdata <- function(...) system.file("extdata", ..., package = "pcountr")

# metadata_FL.csv uses the standard column names, so no col_map is needed.
fl_site <- local({
  suppressWarnings(
    read_site(extdata("fake_lake"),
              metadata = extdata("fake_lake", "metadata_FL.csv"),
              quiet    = TRUE)
  )
})

# ---------------------------------------------------------------------------
# Basic file creation
# ---------------------------------------------------------------------------

test_that("write_tlx() creates a file", {
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  expect_true(file.exists(f))
  expect_gt(file.size(f), 1000L)
})

test_that("write_tlx() returns the file path invisibly", {
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  ret <- write_tlx(fl_site, f)
  expect_equal(ret, f)
})

# ---------------------------------------------------------------------------
# XML structure
# ---------------------------------------------------------------------------

test_that("output is well-formed XML with four SpreadSheet pages", {
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  doc   <- xml2::read_xml(f)
  pages <- xml2::xml_find_all(doc, ".//SpreadSheet")
  expect_equal(length(pages), 4L)
  names_found <- xml2::xml_attr(pages, "name")
  expect_equal(names_found, c("Data", "Percents", "Concentrations", "Accumulation"))
})

test_that("each SpreadSheet has 20 sample columns (Col ID 8-27)", {
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  doc   <- xml2::read_xml(f)
  data_page <- xml2::xml_find_first(doc, ".//SpreadSheet[@name='Data']")
  cols <- xml2::xml_find_all(data_page, "Col")
  # Cols 1,2,4,7 are header cols; remaining are sample cols
  col_ids <- as.integer(xml2::xml_attr(cols, "ID"))
  sample_cols <- col_ids[col_ids >= 8L]
  expect_equal(length(sample_cols), 20L)
})

# ---------------------------------------------------------------------------
# Content spot checks
# ---------------------------------------------------------------------------

test_that("only taxa with positive counts appear as taxon rows", {
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  doc      <- xml2::read_xml(f)
  # Col 1 of Data page holds codes; rows >= 10 are taxa
  col1     <- xml2::xml_find_first(doc,
                ".//SpreadSheet[@name='Data']/Col[@ID='1']")
  cells    <- xml2::xml_find_all(col1, "cell")
  rows     <- as.integer(xml2::xml_attr(cells, "row"))
  codes    <- xml2::xml_text(cells)
  # Rows >= 10 that are not group-sum rows
  is_taxon <- rows >= 10L & !grepl("^S{1,2}SUM", codes)
  expect_gt(sum(is_taxon), 0L)
})

test_that("group sum rows appear in Data page", {
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  raw   <- readLines(f)
  expect_true(any(grepl("SUM(A)",      raw, fixed = TRUE)))
  expect_true(any(grepl("SSUM(All)",   raw, fixed = TRUE)))
  expect_true(any(grepl("SSUM(Terr)",  raw, fixed = TRUE)))
})

test_that("CONC metadata rows appear: age, depth, spike, quantity", {
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  raw <- readLines(f)
  expect_true(any(grepl("#Chron1",                     raw, fixed = TRUE)))
  expect_true(any(grepl("#Depth1",                     raw, fixed = TRUE)))
  expect_true(any(grepl("Lyc.spik:counted:number",     raw, fixed = TRUE)))
  expect_true(any(grepl("Lyc.tab:quantity added",      raw, fixed = TRUE)))
  expect_true(any(grepl("dep.time",                    raw, fixed = TRUE)))
})

test_that("Site and CollectionUnit stub elements are present", {
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  raw <- readLines(f)
  expect_true(any(grepl("<Site></Site>", raw, fixed = TRUE)))
  expect_true(any(grepl("<CollectionUnit></CollectionUnit>", raw, fixed = TRUE)))
})

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

test_that("write_tlx() errors when no stratigraphic position is available", {
  site2 <- fl_site
  for (nm in names(site2$samples)) {
    site2$samples[[nm]]$meta$depth_top    <- NA_real_
    site2$samples[[nm]]$meta$depth_bottom <- NA_real_
    site2$samples[[nm]]$meta$sample_name   <- NA_character_
    site2$samples[[nm]]$meta$age_top      <- NA_real_
  }
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  expect_error(write_tlx(site2, f), regexp = "stratigraphic position")
})

test_that("write_tlx() orders samples by depth_top", {
  skip_if_not_installed("xml2")
  f <- tempfile(fileext = ".tlx")
  on.exit(unlink(f))
  write_tlx(fl_site, f)
  doc      <- xml2::read_xml(f)
  data_pg  <- xml2::xml_find_first(doc, ".//SpreadSheet[@name='Data']")
  # Col 8 is the first sample; row 1 holds depth_top (the column header)
  col8     <- xml2::xml_find_first(data_pg, "Col[@ID='8']")
  row1     <- xml2::xml_find_first(col8, "cell[@row='1']")
  depth1   <- as.numeric(xml2::xml_text(
                xml2::xml_find_first(row1, "value")))
  expect_equal(depth1, 0.0)  # FL001 is at 0 cm
})
