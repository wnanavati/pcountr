# Tests for read_tilia_lookup() and standardize_dic().
#
# A miniature Tilia lookup file is written to a tempfile, so these tests need
# neither a Tilia installation nor the 11 MB real lookup. The synthetic file
# reproduces the structures that matter: accepted taxa with TaxaGroup /
# EcolGroup, and a <Synonyms> block carrying Neotoma's own synonymy.

skip_if_no_xml2 <- function() skip_if_not_installed("xml2")

# ── A miniature lookup ──────────────────────────────────────────────────────
# Cases embedded here, mirroring what the real ECG dictionary throws up:
#   Abies                    -> exact
#   cf. Gymnocarpium         -> orthographic variant of "c.f. Gymnocarpium"
#   Alnus incana             -> accepted; "Alnus rugosa" is its synonym
#   Pinus subg. Pinus        -> accepted; "Pinus subg. Diploxylon" its synonym,
#                               reachable only after subgen./subg. normalising
#   Tidestromia lanuginosa   -> near "Tidestromia lanuginosa-type" but NOT a
#                               variant, because "-type" changes meaning
#   Nitzschia oregona        -> a diatom (TaxaGroup DIA), must be excluded
make_lookup_xml <- function() {
  path <- tempfile(fileext = ".xml")
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    '<TiliaTaxa version="4.0">',
    '<Title>Test Pollen Taxa</Title>',
    '<EcologicalGroups>',
    '<TaxaGroup Code="VPL" Name="Vascular plants">',
    '<EcologicalGroup><Code>TRSH</Code><Name>Trees and Shrubs</Name></EcologicalGroup>',
    '<EcologicalGroup><Code>UPHE</Code><Name>Upland Herbs</Name></EcologicalGroup>',
    '<EcologicalGroup><Code>VACR</Code><Name>Terrestrial Vascular Cryptogams</Name></EcologicalGroup>',
    '</TaxaGroup>',
    '<TaxaGroup Code="DIA" Name="Diatoms">',
    '<EcologicalGroup><Code>DIAT</Code><Name>Diatoms</Name></EcologicalGroup>',
    '</TaxaGroup>',
    '</EcologicalGroups>',
    '<Taxa>',
    '<Taxon ID="1"><Name>Abies</Name><Code>Abi</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>TRSH</EcolGroup><HigherID>900</HigherID></Taxon>',
    '<Taxon ID="2"><Name>Alnus incana</Name><Code>Aln.in</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>TRSH</EcolGroup><HigherID>900</HigherID></Taxon>',
    '<Taxon ID="3"><Name>cf. Gymnocarpium</Name><Code>Gym</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>VACR</EcolGroup><HigherID>901</HigherID></Taxon>',
    '<Taxon ID="4"><Name>Pinus subg. Pinus</Name><Code>Pin.Pin</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>TRSH</EcolGroup><HigherID>900</HigherID></Taxon>',
    '<Taxon ID="5"><Name>Tidestromia lanuginosa</Name><Code>Tid.la</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>UPHE</EcolGroup><HigherID>902</HigherID></Taxon>',
    '<Taxon ID="6"><Name>Cannabaceae</Name><Code>Cann</Code>',
    '<TaxaGroup>VPL</TaxaGroup><EcolGroup>TRSH</EcolGroup><HigherID>900</HigherID></Taxon>',
    '<Taxon ID="7"><Name>Nitzschia oregona</Name><Author>Sovereign, 1958</Author>',
    '<Code>Nit.or</Code><TaxaGroup>DIA</TaxaGroup><EcolGroup>DIAT</EcolGroup>',
    '<HigherID>800</HigherID></Taxon>',
    '</Taxa>',
    '<Synonyms>',
    '<Synonym ID="500"><Name>Alnus rugosa</Name><TaxonID>2</TaxonID></Synonym>',
    '<Synonym ID="501"><Name>Pinus subg. Diploxylon</Name><TaxonID>4</TaxonID></Synonym>',
    '</Synonyms>',
    '</TiliaTaxa>'), path)
  path
}

test_dic <- function() {
  data.frame(
    code = c("AB", "A",            "GY",                "E",
             "TA",                          "HC",          "ZZ"),
    name = c("Abies", "Alnus rugosa", "c.f. Gymnocarpium", "Pinus subgen. Diploxylon",
             "Tidestromia lanuginosa-type", "Cannabaceae", "Nothing Like This"),
    group = c("A", "A", "F", "A", "B", "B", "X"),
    stringsAsFactors = FALSE)
}

# ── read_tilia_lookup() ─────────────────────────────────────────────────────

test_that("read_tilia_lookup parses taxa, synonyms and groups", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())

  expect_s3_class(lk, "tilia_lookup")
  expect_true(all(c("taxon_id", "name", "author", "code", "taxa_group",
                    "ecol_group", "higher_id") %in% names(lk)))
  expect_equal(nrow(lk), 7L)
  expect_equal(lk$ecol_group[lk$name == "Abies"], "TRSH")
  expect_equal(lk$author[lk$name == "Nitzschia oregona"], "Sovereign, 1958")
  expect_true(is.na(lk$author[lk$name == "Abies"]))

  syn <- attr(lk, "synonyms")
  expect_equal(nrow(syn), 2L)
  expect_equal(syn$taxon_id[syn$name == "Alnus rugosa"], "2")

  grp <- attr(lk, "groups")
  expect_true("TRSH" %in% grp$ecol_group)
  expect_equal(grp$taxa_group_name[grp$ecol_group == "DIAT"], "Diatoms")
  expect_equal(attr(lk, "title"), "Test Pollen Taxa")
})

test_that("read_tilia_lookup caches within the session", {
  skip_if_no_xml2()
  p <- make_lookup_xml()
  expect_identical(read_tilia_lookup(p), read_tilia_lookup(p))
})

test_that("read_tilia_lookup errors clearly on bad input", {
  skip_if_no_xml2()
  expect_error(read_tilia_lookup(file.path(tempdir(), "nope.xml")),
               "not found")
  bad <- tempfile(fileext = ".xml")
  writeLines(c('<?xml version="1.0"?>', "<Other><Thing/></Other>"), bad)
  expect_error(read_tilia_lookup(bad), "Tilia lookup file")
})

test_that("print method for the lookup runs", {
  skip_if_no_xml2()
  out <- capture.output(print(read_tilia_lookup(make_lookup_xml())))
  expect_true(any(grepl("tilia_lookup", out)))
  expect_true(any(grepl("palynomorph", out)))
})

# ── classification ──────────────────────────────────────────────────────────

test_that("statuses are assigned as documented", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  r  <- attr(standardize_dic(test_dic(), lk), "report")
  st <- stats::setNames(r$status, r$code)

  expect_equal(st[["AB"]], "exact")
  expect_equal(st[["A"]],  "synonym")     # Alnus rugosa -> Alnus incana
  expect_equal(st[["GY"]], "variant")     # c.f. -> cf.
  expect_equal(st[["HC"]], "exact")
  expect_equal(st[["ZZ"]], "unmatched")

  ac <- stats::setNames(r$accepted_name, r$code)
  expect_equal(ac[["A"]],  "Alnus incana")
  expect_equal(ac[["GY"]], "cf. Gymnocarpium")
})

test_that("normalised synonym matching resolves subgen./subg.", {
  skip_if_no_xml2()
  # "Pinus subgen. Diploxylon" reaches the synonym "Pinus subg. Diploxylon"
  # only after abbreviation normalising. Without that branch an authoritative
  # answer would be downgraded to an advisory fuzzy suggestion, which against the
  # real lookup does not favour the right target.
  lk <- read_tilia_lookup(make_lookup_xml())
  r  <- attr(standardize_dic(test_dic(), lk), "report")
  row <- r[r$code == "E", ]
  expect_equal(row$status, "synonym")
  expect_equal(row$accepted_name, "Pinus subg. Pinus")
})

test_that("'-type' is never treated as an orthographic variant", {
  skip_if_no_xml2()
  # "Tidestromia lanuginosa-type" is a morphotype, not a determination of
  # Tidestromia lanuginosa. It must NOT be classed 'variant'.
  lk <- read_tilia_lookup(make_lookup_xml())
  r  <- attr(standardize_dic(test_dic(), lk), "report")
  row <- r[r$code == "TA", ]
  expect_false(row$status == "variant")
  expect_equal(row$status, "suggestion")
  expect_true(row$similarity > 0.8)
})

test_that("non-palynomorph taxa groups are excluded from matching", {
  skip_if_no_xml2()
  lk  <- read_tilia_lookup(make_lookup_xml())
  dic <- data.frame(code = "NO", name = "Nitzschia oregona", group = "B",
                    stringsAsFactors = FALSE)
  # DIA is not a palynomorph group, so the diatom must not match
  expect_equal(attr(standardize_dic(dic, lk), "report")$status, "unmatched")
  # ...but it does when the filter is removed
  expect_equal(attr(standardize_dic(dic, lk, taxa_groups = NULL),
                    "report")$status, "exact")
})

test_that("a synonym pointing outside the pool falls through, and does not error", {
  skip_if_no_xml2()
  # In the real pollen lookup, 439 of 2,182 synonym targets are non-palynomorph
  # taxa. Resolving those with [[ throws "subscript out of bounds"; the fix uses
  # [ so the row falls through to fuzzy matching instead.
  #
  # Here "Diatom Synonym" is a synonym of taxon 7, a diatom, which the default
  # palynomorph filter excludes.
  p <- tempfile(fileext = ".xml")
  x <- readLines(make_lookup_xml())
  x <- sub("</Synonyms>",
           paste0('<Synonym ID="502"><Name>Diatom Synonym</Name>',
                  '<TaxonID>7</TaxonID></Synonym></Synonyms>'), x)
  writeLines(x, p)
  lk  <- read_tilia_lookup(p)
  dic <- data.frame(code = "DS", name = "Diatom Synonym", group = "B",
                    stringsAsFactors = FALSE)

  expect_no_error(r <- attr(standardize_dic(dic, lk), "report"))
  expect_true(r$status %in% c("suggestion", "unmatched"))
  expect_false(r$status == "synonym")

  # ...and it does resolve when the filter is lifted
  r2 <- attr(standardize_dic(dic, lk, taxa_groups = NULL), "report")
  expect_equal(r2$status, "synonym")
  expect_equal(r2$accepted_name, "Nitzschia oregona")
})

test_that("groups are NOT compared by default", {
  skip_if_no_xml2()
  # An ecological group is a local "sum by" choice, so no comparison is made
  # unless group_map is supplied. NA records "not compared", distinct from FALSE
  # meaning "compared and agreed".
  lk <- read_tilia_lookup(make_lookup_xml())
  r  <- attr(standardize_dic(test_dic(), lk), "report")
  expect_true(all(is.na(r$group_differs)))
  # ...but ecol_group is still reported, for reference
  expect_equal(r$ecol_group[r$code == "HC"], "TRSH")
})

test_that("group_map = enables the comparison, and still changes nothing", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  gm <- c(A = "TRSH", B = "UPHE", F = "VACR", Q = "AQVP", X = "UNID")
  d  <- standardize_dic(test_dic(), lk, group_map = gm)
  r  <- attr(d, "report")
  # Cannabaceae: dictionary says B (-> UPHE), lookup says TRSH
  expect_true(r$group_differs[r$code == "HC"])
  expect_false(r$group_differs[r$code == "AB"])
  expect_equal(d$group, test_dic()$group)      # untouched either way
})

test_that("printed ecol is blank for suggestion and unmatched rows", {
  skip_if_no_xml2()
  # ecol_group is derived from accepted_name, which on a suggestion is only a
  # candidate. Printing it beside the analyst's group would attribute a group the
  # taxon does not have. TA suggests Tidestromia lanuginosa (UPHE) and ZZ matches
  # nothing; neither should show an ecological group.
  lk  <- read_tilia_lookup(make_lookup_xml())
  out <- capture.output(print(standardize_dic(test_dic(), lk)))

  ta <- grep("^  TA ", out, value = TRUE)
  zz <- grep("^  ZZ ", out, value = TRUE)
  expect_length(ta, 1L); expect_length(zz, 1L)
  expect_false(grepl("UPHE", ta))
  expect_false(grepl("[A-Z]{4}\\s*$", sub("\\s+$", "", zz)))

  # ...while a variant row still shows it
  gy <- grep("^  GY ", out, value = TRUE)
  expect_true(grepl("VACR", gy))

  # and the underlying column is untouched
  r <- attr(standardize_dic(test_dic(), lk), "report")
  expect_equal(r$ecol_group[r$code == "TA"], "UPHE")
})

test_that("print reports whether groups were compared", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  out1 <- capture.output(print(standardize_dic(test_dic(), lk)))
  expect_true(any(grepl("Groups are not compared", out1)))
  expect_false(any(grepl("GROUP DIFFERS", out1)))

  gm <- c(A = "TRSH", B = "UPHE", F = "VACR", Q = "AQVP", X = "UNID")
  out2 <- capture.output(print(standardize_dic(test_dic(), lk, group_map = gm)))
  expect_true(any(grepl("GROUP DIFFERS", out2)))
})

# ── apply ───────────────────────────────────────────────────────────────────

test_that("apply = 'none' changes nothing", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d  <- standardize_dic(test_dic(), lk)
  expect_equal(d$name, test_dic()$name)
  expect_false(any(attr(d, "report")$applied))
})

test_that("apply = 'variant' takes only the variants", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d  <- suppressMessages(standardize_dic(test_dic(), lk, apply = "variant"))
  expect_equal(d$name[d$code == "GY"], "cf. Gymnocarpium")
  expect_equal(d$name[d$code == "A"],  "Alnus rugosa")   # synonym untouched
})

test_that("apply accepts a code, and a name, for a single row", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d1 <- suppressMessages(standardize_dic(test_dic(), lk, apply = "TA"))
  expect_equal(d1$name[d1$code == "TA"], "Tidestromia lanuginosa")
  expect_equal(d1$name[d1$code == "GY"], "c.f. Gymnocarpium")  # not selected

  d2 <- suppressMessages(standardize_dic(test_dic(), lk,
                                         apply = "Alnus rugosa"))
  expect_equal(d2$name[d2$code == "A"], "Alnus incana")
})

test_that("apply combines classes with individual rows", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d <- suppressMessages(
    standardize_dic(test_dic(), lk, apply = c("variant", "synonym", "TA")))
  expect_equal(d$name[d$code == "GY"], "cf. Gymnocarpium")
  expect_equal(d$name[d$code == "A"],  "Alnus incana")
  expect_equal(d$name[d$code == "E"],  "Pinus subg. Pinus")
  expect_equal(d$name[d$code == "TA"], "Tidestromia lanuginosa")
})

test_that("'suggestion' and 'all' are refused as classes", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  expect_error(standardize_dic(test_dic(), lk, apply = "suggestion"),
               "will not take")
  expect_error(standardize_dic(test_dic(), lk, apply = "all"),
               "no \"all\" shorthand")
})

test_that("an unrecognised apply element is an error, not a silent no-op", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  expect_error(standardize_dic(test_dic(), lk,
                               apply = c("variant", "Asteracae typo")),
               "match no class, code or name")
})

test_that("applying is idempotent -- re-running reports the row as exact", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d1 <- suppressMessages(standardize_dic(test_dic(), lk, apply = "variant"))
  r2 <- attr(standardize_dic(d1, lk), "report")
  expect_equal(r2$status[r2$code == "GY"], "exact")
})

# ── aliases ─────────────────────────────────────────────────────────────────

test_that("a missing alias file produces a template of unresolved rows", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  p  <- tempfile(fileext = ".csv")
  suppressMessages(standardize_dic(test_dic(), lk, aliases = p))

  expect_true(file.exists(p))
  a <- utils::read.csv(p, stringsAsFactors = FALSE, colClasses = "character")
  expect_true(all(c("name", "accepted_name") %in% names(a)))
  expect_true("Nothing Like This" %in% a$name)    # unmatched
  expect_true("Tidestromia lanuginosa-type" %in% a$name)   # suggestion
  expect_true(all(!nzchar(a$accepted_name)))      # blank, for you to fill

  # A template read straight back must not resolve anything -- in particular the
  # blank column must not arrive as the literal string "NA".
  r <- attr(suppressMessages(standardize_dic(test_dic(), lk, aliases = p)),
            "report")
  expect_false(any(r$status == "alias"))
})

test_that("a filled alias file resolves rows as 'alias' and can be applied", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  p  <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(name = "Nothing Like This",
                              accepted_name = "Abies",
                              stringsAsFactors = FALSE), p, row.names = FALSE)

  r <- attr(standardize_dic(test_dic(), lk, aliases = p), "report")
  expect_equal(r$status[r$code == "ZZ"], "alias")

  d <- suppressMessages(standardize_dic(test_dic(), lk, aliases = p,
                                        apply = "alias"))
  expect_equal(d$name[d$code == "ZZ"], "Abies")
})

test_that("an alias file missing required columns errors", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  p  <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(a = 1, b = 2), p, row.names = FALSE)
  expect_error(standardize_dic(test_dic(), lk, aliases = p),
               "accepted_name")
})

# ── return value and printing ───────────────────────────────────────────────

test_that("the return value is still a usable dictionary", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  d  <- standardize_dic(test_dic(), lk)
  expect_s3_class(d, "standardized_dic")
  expect_s3_class(d, "data.frame")
  expect_true(all(c("code", "name", "group") %in% names(d)))
  expect_equal(nrow(d), nrow(test_dic()))
  expect_s3_class(attr(d, "report"), "data.frame")
})

test_that("print shows the report and the status tallies", {
  skip_if_no_xml2()
  lk  <- read_tilia_lookup(make_lookup_xml())
  out <- capture.output(print(standardize_dic(test_dic(), lk)))
  expect_true(any(grepl("standardisation report", out)))
  expect_true(any(grepl("VARIANT", out)))
  expect_true(any(grepl("ADVISORY ONLY", out)))
  expect_true(any(grepl("Nothing changed", out)))
  expect_true(any(grepl("ecol_group is the lookup's", out)))
})

test_that("invalid inputs are rejected", {
  skip_if_no_xml2()
  lk <- read_tilia_lookup(make_lookup_xml())
  expect_error(standardize_dic(list(), lk), "data frame with")
  expect_error(standardize_dic(test_dic(), lookup = data.frame(a = 1)),
               "read_tilia_lookup")
})
