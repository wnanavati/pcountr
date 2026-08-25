# Tests for build_dic_neotoma() and its helpers.
#
# Deliberately offline. The network path is NOT tested: R CMD check must not
# depend on api.neotomadb.org, and a spatial query there takes tens of
# seconds. What IS tested is everything that decides the contents of the
# dictionary -- the units/group filtering, the presence tally, the fixed
# entries, the geometry, and the distance maths -- against a fixture built
# from the real shape of neotoma2::samples() output.

# A miniature samples() frame. Column names and values follow real Neotoma
# records from a Montana pollen dataset, including the traps that matter:
#   - Lycopodium tablets / Sample quantity  -> laboratory rows, non-NISP
#   - Lycopodium spike                      -> LABO, units "number"
#   - Unknown / Indeterminable              -> UNID, NISP, real tally rows
#   - Botryococcus                          -> Algae, NISP, a real taxon
fake_samples <- function() {
  add <- function(siteid, variablename, units, ecologicalgroup, taxongroup) {
    data.frame(siteid = siteid, variablename = variablename, units = units,
               ecologicalgroup = ecologicalgroup, taxongroup = taxongroup,
               stringsAsFactors = FALSE)
  }
  rbind(
    # Pinus at three sites, several samples each -> most widespread
    add(c(1, 1, 1, 2, 2, 3), "Pinus", "NISP", "TRSH", "Vascular plants"),
    # Abies at two sites
    add(c(1, 2), "Abies", "NISP", "TRSH", "Vascular plants"),
    # Artemisia at one site but MANY samples: presence must not reward this
    add(rep(1, 12), "Artemisia", "NISP", "UPHE", "Vascular plants"),
    # a non-pollen palynomorph that must survive
    add(c(1, 2), "Botryococcus", "NISP", "ALGA", "Algae"),
    # laboratory rows that must all be dropped
    add(1, "Lycopodium tablets", "grains/tablet", "LABO", "Laboratory analyses"),
    add(1, "Sample quantity",    "ml",            "LABO", "Laboratory analyses"),
    add(1, "Lycopodium spike",   "number",        "LABO", "Laboratory analyses"),
    # unidentified rows: excluded from the ranking, re-added as fixed entries
    add(c(1, 2), "Unknown",        "NISP", "UNID", "Unidentified palynomorphs"),
    add(1,       "Indeterminable", "NISP", "UNID", "Unidentified palynomorphs")
  )
}

# ── the tally ───────────────────────────────────────────────────────────────

test_that("taxa are ranked by distinct sites, not by number of samples", {
  d <- .dic_from_samples(fake_samples(), n = 50)
  taxa <- d[!d$name %in% c("Spike", "Unknown", "Indeterminable"), ]

  # Pinus (3 sites) beats Abies (2) beats Artemisia (1), even though
  # Artemisia has by far the most rows. This is the whole point of using
  # presence rather than abundance.
  expect_equal(taxa$name[1], "Pinus")
  expect_true(match("Abies", taxa$name) < match("Artemisia", taxa$name))
})

test_that("laboratory rows are excluded", {
  d <- .dic_from_samples(fake_samples(), n = 50)
  expect_false(any(grepl("Lycopodium", d$name)))
  expect_false("Sample quantity" %in% d$name)
  expect_false(any(d$group == "LABO"))
})

test_that("non-pollen palynomorphs are kept", {
  # Algae are counted by analysts and are neither LABO nor UNID, so a pollen
  # datasettype legitimately yields a palynomorph dictionary.
  d <- .dic_from_samples(fake_samples(), n = 50)
  expect_true("Botryococcus" %in% d$name)
  expect_equal(d$group[d$name == "Botryococcus"], "ALGA")
})

test_that("spike and unidentified entries are always present and fixed", {
  d <- .dic_from_samples(fake_samples(), n = 50)
  expect_identical(d$name[1:3], c("Spike", "Unknown", "Indeterminable"))
  expect_equal(d$code[d$name == "Spike"], ".")
  expect_true(d$is_special[d$name == "Spike"])
  # Unknown/Indeterminable appear once each despite being filtered out of
  # the ranking, and are not duplicated by the tally.
  expect_equal(sum(d$name == "Unknown"), 1L)
})

test_that("n caps the taxa but not the fixed entries", {
  d <- .dic_from_samples(fake_samples(), n = 2)
  expect_equal(nrow(d), 5L)          # 3 fixed + 2 taxa
  expect_equal(d$name[4], "Pinus")
})

test_that("the draft has the columns read_dic_csv() expects", {
  d <- .dic_from_samples(fake_samples(), n = 50)
  expect_named(d, c("code", "alias", "group", "name", "is_special", "value"))
  expect_true(all(d$value == 1))
  # Codes are blank by design: read_dic_csv() drops blank-code rows, so this
  # is a draft the analyst completes, not a loadable dictionary.
  expect_true(all(d$code[d$name != "Spike"] == ""))
})

test_that("a datasettype with no taxa errors informatively", {
  # What a charcoal datasettype looks like: measurements, no taxa.
  charcoal <- data.frame(
    siteid = c(1, 1), variablename = c("Charcoal", "Sample quantity"),
    units = c("number", "ml"), ecologicalgroup = c("LABO", "LABO"),
    taxongroup = c("Laboratory analyses", "Laboratory analyses"),
    stringsAsFactors = FALSE)
  expect_error(
    .dic_from_samples(charcoal, n = 50, datasettype = "macrocharcoal"),
    "taxon vocabulary")
})

test_that("missing columns are reported rather than silently mangled", {
  expect_error(.dic_from_samples(data.frame(siteid = 1), n = 5),
               "lacks column")
})

# ── the CSV round trip ──────────────────────────────────────────────────────

test_that("the draft survives a write/read round trip, diacritics included", {
  # Neotoma really does return "Isoetes" spelled with a diaeresis in a western
  # Montana pollen query, which is why build_dic_neotoma() writes with an
  # explicit fileEncoding and read_dic_csv() reads with encoding = "UTF-8".
  # The escape keeps this file ASCII; a literal would fail R CMD check.
  iso <- "Iso\u00ebtes"

  s <- fake_samples()
  s <- rbind(s, data.frame(siteid = c(1, 2), variablename = iso,
                           units = "NISP", ecologicalgroup = "AQVP",
                           taxongroup = "Vascular plants",
                           stringsAsFactors = FALSE))
  d <- .dic_from_samples(s, n = 50)
  expect_true(iso %in% d$name)

  # Simulate the analyst completing the draft: codes are blank by design, and
  # read_dic_csv() drops blank-code rows, so fill them before reading back.
  d$code <- sprintf("%02d", seq_len(nrow(d)))
  d$code[d$name == "Spike"] <- "."

  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f), add = TRUE)
  write.csv(d, f, row.names = FALSE, fileEncoding = "UTF-8")

  back <- read_dic_csv(f)
  expect_s3_class(back, "pollen_dictionary")
  expect_equal(nrow(back), nrow(d))
  expect_true(iso %in% back$name)
  expect_equal(back$group[back$name == iso], "AQVP")
  # The spike must still be recognised as special via its "." code.
  expect_true(back$is_special[back$code == "."])
})

# ── geometry and distance ───────────────────────────────────────────────────

test_that("haversine matches known distances", {
  # Forest Lake, MT -> Blacktail Pond, Yellowstone. Measured against the real
  # Neotoma coordinates; ~206 km.
  d <- .haversine_km(46.45167, -112.16583, 44.95551, -110.60180)
  expect_gt(d, 195); expect_lt(d, 215)
  # identity and symmetry
  expect_equal(.haversine_km(46, -112, 46, -112), 0)
  expect_equal(.haversine_km(46, -112, 44, -110),
               .haversine_km(44, -110, 46, -112))
})

test_that("haversine is vectorised over the second point", {
  d <- .haversine_km(46, -112, c(46, 47, 48), c(-112, -112, -112))
  expect_length(d, 3L)
  expect_equal(d[1], 0)
  expect_true(all(diff(d) > 0))
})

test_that("the GeoJSON box is valid, closed, and encloses the point", {
  js <- .geojson_box(46.45167, -112.16583, 250)
  expect_match(js, '"type":"Polygon"', fixed = TRUE)

  nums <- as.numeric(regmatches(js, gregexpr("-?[0-9]+\\.[0-9]+", js))[[1]])
  expect_length(nums, 10L)                       # 5 vertices, closed ring
  lon <- nums[c(1, 3, 5, 7, 9)]
  lat <- nums[c(2, 4, 6, 8, 10)]
  expect_equal(lon[1], lon[5]); expect_equal(lat[1], lat[5])

  expect_lt(min(lon), -112.16583); expect_gt(max(lon), -112.16583)
  expect_lt(min(lat),   46.45167); expect_gt(max(lat),   46.45167)

  # A box circumscribing 250 km reaches at least that far along each axis.
  expect_gt(.haversine_km(46.45167, -112.16583, max(lat), -112.16583), 245)
})

test_that("a larger radius gives a strictly larger box", {
  small <- .geojson_box(46, -112, 50)
  large <- .geojson_box(46, -112, 500)
  n <- function(x) as.numeric(regmatches(x, gregexpr("-?[0-9]+\\.[0-9]+", x))[[1]])
  expect_gt(diff(range(n(large)[c(2, 6)])), diff(range(n(small)[c(2, 6)])))
})

# ── argument validation (no network reached) ─────────────────────────────────

test_that("bad coordinates are rejected before any query", {
  skip_if_not_installed("neotoma2")
  expect_error(build_dic_neotoma(lat = 91,  long = 0))
  expect_error(build_dic_neotoma(lat = 46,  long = 200))
  expect_error(build_dic_neotoma(lat = NA,  long = 0))
  expect_error(build_dic_neotoma(lat = 46,  long = 0, radius_km = -1))
  expect_error(build_dic_neotoma(lat = 46,  long = 0, n = 0))
})
