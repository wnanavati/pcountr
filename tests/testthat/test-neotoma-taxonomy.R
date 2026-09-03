# Tests for neotoma_taxonomy() and its helpers.
#
# Deliberately offline. The network path is NOT tested: R CMD check must not
# depend on api.neotomadb.org, and the real fetch is tens of megabytes. What IS
# tested is the transformation that decides the contents of the lookup -- which
# taxa count as accepted, how the synonymy is keyed, whether the object is a
# drop-in for read_tilia_lookup() -- against fixtures shaped like the real API
# responses.

# ── Fixtures: the exact shape the two API routes return ─────────────────────
#
# /data/taxa. Includes the cases that matter:
#   1  Abies              accepted, VPL
#   2  Alnus incana       accepted, VPL; target of a synonym
#   62 Iva ciliata-type   accepted, VPL; target of a synonym
#   44991 Aneumastus spp. accepted, DIA -- a diatom, proving one table
#                         spans proxies
#   14749 Alnus rugosa    DEPRECATED (appears as invalidtaxonid)
#   14747 Iva frutescens  DEPRECATED
fake_taxa <- function() {
  data.frame(
    taxonid       = c(1, 2, 62, 44991, 14749, 14747),
    taxonname     = c("Abies", "Alnus incana", "Iva ciliata-type",
                      "Aneumastus spp.", "Alnus rugosa", "Iva frutescens"),
    author        = c("Miller, 1754", NA, NA, NA, NA, NA),
    taxoncode     = c("Abi", "Aln.in", "Iva.ci-t", "Ane.s.", "Aln.rg", "Iva.fr"),
    ecolgroup     = c("TRSH", "TRSH", "UPHE", "DIAT", NA, NA),
    highertaxonid = c(329, 900, 901, 24386, NA, NA),
    taxagroupid   = c("VPL", "VPL", "VPL", "DIA", "VPL", "VPL"),
    stringsAsFactors = FALSE)
}

# /data/dbtables/synonyms. The third row points at a taxon that is absent from
# the taxa fixture, which must be dropped rather than carried as an NA key.
fake_syn <- function() {
  data.frame(
    invalidtaxonid = c(14749, 14747, 999999),
    validtaxonid   = c(2, 62, 1),
    stringsAsFactors = FALSE)
}

# ── assembly ────────────────────────────────────────────────────────────────

test_that("deprecated taxa are excluded from the accepted pool", {
  lk <- .neotoma_assemble(fake_taxa(), fake_syn())
  expect_false("Alnus rugosa"   %in% lk$name)
  expect_false("Iva frutescens" %in% lk$name)
  expect_true("Alnus incana" %in% lk$name)
  expect_equal(nrow(lk), 4L)   # 6 taxa - 2 deprecated
})

test_that("the synonymy maps deprecated name to accepted taxon_id", {
  lk  <- .neotoma_assemble(fake_taxa(), fake_syn())
  syn <- attr(lk, "synonyms")
  expect_s3_class(syn, "data.frame")
  expect_named(syn, c("name", "taxon_id"))
  expect_equal(syn$taxon_id[syn$name == "Alnus rugosa"], "2")
  expect_equal(syn$taxon_id[syn$name == "Iva frutescens"], "62")
})

test_that("a synonym whose deprecated taxon is unknown is dropped", {
  # invalidtaxonid 999999 is not in the taxa table, so its name cannot be
  # resolved. Carrying it would put an NA in the lookup key.
  lk  <- .neotoma_assemble(fake_taxa(), fake_syn())
  syn <- attr(lk, "synonyms")
  expect_equal(nrow(syn), 2L)
  expect_false(anyNA(syn$name))
})

test_that("ids are character, matching read_tilia_lookup()", {
  # standardize_dic() builds setNames(pool$name, pool$taxon_id) and looks up
  # synonym targets by that key. The XML reader yields character ids, so the
  # API path must too or every synonym silently fails to resolve.
  lk <- .neotoma_assemble(fake_taxa(), fake_syn())
  expect_type(lk$taxon_id, "character")
  expect_type(lk$higher_id, "character")
  expect_type(attr(lk, "synonyms")$taxon_id, "character")
})

test_that("the object has the columns and class of a tilia_lookup", {
  lk <- .neotoma_assemble(fake_taxa(), fake_syn())
  expect_s3_class(lk, "tilia_lookup")
  expect_true(all(c("taxon_id", "name", "author", "code",
                    "taxa_group", "ecol_group", "higher_id") %in% names(lk)))
  expect_false(is.null(attr(lk, "fetched")))
})

test_that("one table spans proxies", {
  # The point of using the API rather than Tilia's eleven per-proxy files.
  lk <- .neotoma_assemble(fake_taxa(), fake_syn())
  expect_true(all(c("VPL", "DIA") %in% lk$taxa_group))
  expect_equal(lk$name[lk$taxa_group == "DIA"], "Aneumastus spp.")
})

test_that("the print method works on an API-built lookup", {
  lk  <- .neotoma_assemble(fake_taxa(), fake_syn())
  out <- capture.output(print(lk))
  expect_true(any(grepl("tilia_lookup", out)))
  expect_true(any(grepl("synonyms", out)))
})

# ── the drop-in claim ───────────────────────────────────────────────────────

test_that("standardize_dic() accepts an API-built lookup interchangeably", {
  # This is the claim the whole feature rests on: standardize_dic() checks only
  # inherits(lookup, "tilia_lookup") and reads $name / $taxon_id / $taxa_group /
  # $ecol_group plus the synonyms attribute. If that holds, a Windows-free
  # analyst gets the same reconciliation a Tilia user gets.
  lk  <- .neotoma_assemble(fake_taxa(), fake_syn())
  dic <- data.frame(
    code  = c("AB", "A", "AN", "ZZ"),
    name  = c("Abies", "Alnus rugosa", "Aneumastus spp.", "Nothing Like This"),
    group = c("A", "A", "B", "X"),
    stringsAsFactors = FALSE)

  r <- attr(standardize_dic(dic, lk, taxa_groups = NULL), "report")
  st <- stats::setNames(r$status, r$code)
  ac <- stats::setNames(r$accepted_name, r$code)

  expect_equal(st[["AB"]], "exact")
  expect_equal(st[["A"]],  "synonym")          # via dbtables/synonyms
  expect_equal(ac[["A"]],  "Alnus incana")
  expect_equal(st[["AN"]], "exact")            # the diatom resolves too
  expect_equal(st[["ZZ"]], "unmatched")
})

# ── taxa_group filtering ────────────────────────────────────────────────────

test_that("taxa_group keeps the requested proxy and retains the synonymy", {
  # Filtering happens on the cached copy because the API ignores taxagroupid.
  # The synonymy is deliberately kept whole: a deprecated name may point at an
  # accepted taxon inside the filtered group even when the deprecated taxon is
  # itself outside it, and targets resolve by id.
  lk  <- .neotoma_assemble(fake_taxa(), fake_syn())
  dia <- lk[lk$taxa_group == "DIA", , drop = FALSE]
  expect_equal(nrow(dia), 1L)
  expect_equal(nrow(attr(lk, "synonyms")), 2L)
})

# ── cache reporting (no network, no download) ───────────────────────────────

test_that("the cache path is under R_user_dir and is not written by tests", {
  p <- .neotoma_cache_file()
  expect_type(p, "character")
  expect_match(basename(p), "^neotoma_taxonomy\\.rds$")
  # CRAN forbids writing outside tempdir() unless it is R_user_dir; make sure
  # we are pointing at the permitted location and not, say, the package dir.
  expect_match(p, "pcountr", fixed = TRUE)
})

test_that("neotoma_taxonomy_cache() reports without erroring", {
  info <- suppressMessages(neotoma_taxonomy_cache())
  expect_type(info, "list")
  expect_named(info, c("path", "exists", "size", "fetched"))
  expect_type(info$exists, "logical")
})

# ── argument validation reaches no network ──────────────────────────────────

test_that("bad arguments are rejected before any request", {
  expect_error(neotoma_taxonomy(taxa_group = 1))
  expect_error(neotoma_taxonomy(refresh = "yes"))
  expect_error(neotoma_taxonomy(quiet = NA_character_))
})

# ── the Tilia path fallback ─────────────────────────────────────────────────

test_that("the Tilia default path honours the option and is a single string", {
  old <- getOption("pcountr.tilia_lookup")
  on.exit(options(pcountr.tilia_lookup = old), add = TRUE)
  options(pcountr.tilia_lookup = "/some/where/Lookup")
  expect_equal(.tilia_default_path(), "/some/where/Lookup")
  options(pcountr.tilia_lookup = NULL)
  p <- .tilia_default_path()
  expect_type(p, "character")
  expect_length(p, 1L)
})

# ── graceful failure when the API is unreachable ────────────────────────────
#
# CRAN policy: "Packages which use Internet resources should fail gracefully
# with an informative message if the resource is not available or has changed
# (and not give a check warning nor error)." These tests point the API base at
# a port that refuses instantly and the cache at a temporary directory, so no
# network call is made and the real cache is never touched.

# Point the API at a dead local port and the cache at a fresh temporary
# directory, then restore both when the calling test exits. withr is available
# because testthat imports it.
#
# 127.0.0.1:1 does not always refuse instantly -- on Windows the connection
# waits out the timeout -- so `timeout` is set low to keep the suite quick.
local_offline_api <- function(env = parent.frame()) {
  dir <- tempfile("pcountr_cache_")
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  withr::local_options(
    list(pcountr.neotoma_api = "http://127.0.0.1:1/v2.0",
         pcountr.cache_dir   = dir,
         timeout             = 1L),
    .local_envir = env)
  withr::defer(unlink(dir, recursive = TRUE), envir = env)
  dir
}

test_that("an unreachable API returns NULL with a message, not an error", {
  local_offline_api()
  expect_message(res <- neotoma_taxonomy(quiet = TRUE), "Could not reach")
  expect_null(res)
})

test_that("the offline path emits no warning", {
  # A check warning is what CRAN objects to, so assert its absence explicitly.
  local_offline_api()
  expect_no_warning(suppressMessages(neotoma_taxonomy(quiet = TRUE)))
})

test_that(".neotoma_page() returns NULL rather than erroring when unreachable", {
  local_offline_api()
  expect_null(.neotoma_page("data/taxa", quiet = TRUE))
})

test_that("nothing is cached when the fetch fails", {
  dir <- local_offline_api()
  suppressMessages(neotoma_taxonomy(quiet = TRUE))
  # A partial or empty cache would be worse than none: the next call would read
  # it and silently reconcile against nothing.
  expect_false(file.exists(file.path(dir, "neotoma_taxonomy.rds")))
})

test_that("standardize_dic() reports clearly when no taxonomy can be had", {
  # With no Tilia install and no reachable API there is nothing to reconcile
  # against; the message should say so rather than surfacing an HTTP error.
  local_offline_api()
  old <- getOption("pcountr.tilia_lookup")
  options(pcountr.tilia_lookup = file.path(tempdir(), "no_such_lookup_dir"))
  on.exit(options(pcountr.tilia_lookup = old), add = TRUE)

  dic <- data.frame(code = "AB", name = "Abies", group = "A",
                    stringsAsFactors = FALSE)
  expect_error(suppressMessages(standardize_dic(dic)),
               "Could not obtain a taxonomy")
})

test_that("the cache directory option is honoured", {
  dir <- local_offline_api()
  # Compare normalised paths: tempfile() yields backslashes on Windows while
  # file.path()/dirname() yield forward slashes, so a literal comparison fails
  # on Windows for reasons that have nothing to do with the option working.
  norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
  expect_equal(norm(dirname(.neotoma_cache_file())), norm(dir))
})
