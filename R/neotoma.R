# neotoma.R -- build a starting dictionary from nearby Neotoma records.
#
# Design notes, measured rather than assumed (see DESIGN.md):
#
#   * Spatial queries are slow but usable. Around Forest Lake, Montana, a
#     250 km box took 40-50 s. Shrinking the box does not help: 50 km still
#     cost 74 s for five sites, so roughly 70 s is fixed server overhead.
#     A generous default radius is therefore close to free.
#
#   * get_datasets(loc=, datasettype=) is the cheapest spatial call. At the
#     same 250 km it ran three times faster than get_sites(loc=), because
#     filtering the datasettype server-side does less work.
#
#   * Enumeration is cheap; downloads are not. all_data = TRUE is therefore
#     used for the enumeration (without it the API silently caps at 25, and
#     ranking an arbitrary 25 sites by distance would be meaningless) while
#     the download step is bounded by `max_sites`.
#
#   * `loc` must be an sf object, an sfg, a numeric bbox or a GeoJSON string.
#     An `sfc` is NOT handled: neotoma2's parseLocation() has no sfc branch
#     and no else-guard, so it fails with "object 'geojson' not found" before
#     any request is sent. A GeoJSON string is used here, which keeps sf out
#     of pcountr's dependencies entirely.

# neotoma2::samples() emits two cosmetic warnings that would otherwise reach
# the analyst on every call:
#
#   1. "no non-missing arguments to max; returning -Inf" -- the chronology
#      precedence ranking found no default with a recognised age type.
#   2. A warning with an EMPTY message. samples() builds its text with
#      sprintf("...%s...", ids$datasetid[1]), and ids$datasetid is always
#      NULL because getids.collunit() passes a list to data.frame() and so
#      never creates that column. sprintf() on NULL gives character(0), and
#      warning(character(0)) prints nothing after the colon.
#
# Both concern age attribution only; no sample rows are dropped, and this
# function never uses ages. Muffling is deliberately narrow -- matched by
# exact text or emptiness -- so the one warning that matters, "No assigned
# samples. Did you run get_downloads()?", still surfaces.
.quiet_samples <- function(x) {
  withCallingHandlers(
    neotoma2::samples(x),
    warning = function(w) {
      m <- conditionMessage(w)
      if (!nzchar(trimws(m)) ||
          grepl("no non-missing arguments to max", m, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    })
}

# Rank taxa by the number of distinct sites they occur in and assemble the
# draft dictionary. Split out from build_dic_neotoma() so the whole tally can
# be tested against a fixture without touching the network.
.dic_from_samples <- function(s, n = 50, datasettype = "pollen",
                              suggest_codes = TRUE) {
  need <- c("siteid", "variablename", "units", "ecologicalgroup", "taxongroup")
  miss <- setdiff(need, names(s))
  if (length(miss))
    stop("samples() output lacks column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)

  # units == "NISP" keeps counted palynomorphs -- including algal colonies
  # and the unidentified categories, which are genuine tally categories --
  # while dropping every laboratory row, since tablets are "grains/tablet",
  # sample quantity is "ml" and the spike count is "number". The group
  # exclusions then drop the unidentified rows from the *ranking*; they are
  # added back below as fixed entries.
  s <- s[!is.na(s$units) & s$units == "NISP", , drop = FALSE]
  s <- s[!s$ecologicalgroup %in% c("LABO", "UNID"), , drop = FALSE]
  s <- s[!s$taxongroup %in% c("Laboratory analyses",
                              "Unidentified palynomorphs"), , drop = FALSE]
  if (nrow(s) == 0L)
    stop("No countable taxa found. Datasettype \"", datasettype,
         "\" may not carry a taxon vocabulary.", call. = FALSE)

  # Distinct site-taxon pairs, then count sites per taxon. Counting distinct
  # pairs rather than rows is what makes this a presence measure: a taxon in
  # one site but two hundred of its samples scores 1, not 200.
  pair  <- unique(s[, c("siteid", "variablename")])
  tally <- sort(table(pair$variablename), decreasing = TRUE)
  top   <- names(utils::head(tally, n))

  # One ecologicalgroup per taxon: the most frequent one seen.
  grp_of <- function(nm) {
    g <- s$ecologicalgroup[s$variablename == nm]
    g <- g[!is.na(g)]
    if (!length(g)) "" else names(sort(table(g), decreasing = TRUE))[1L]
  }

  taxa <- data.frame(
    code       = "",
    alias      = "",
    group      = vapply(top, grp_of, character(1L), USE.NAMES = FALSE),
    name       = top,
    is_special = FALSE,
    value      = 1,
    stringsAsFactors = FALSE)

  # Fixed entries every count needs, in Neotoma's own spelling so that they
  # come back "exact" from standardize_dic(). The spike keeps pcountr's "."
  # code because that is fixed by the counting app, not a matter of taste.
  fixed <- data.frame(
    code       = c(".",     "",        ""),
    alias      = c("",      "",        ""),
    group      = c("",      "UNID",    "UNID"),
    name       = c("Spike", "Unknown", "Indeterminable"),
    is_special = c(TRUE,    FALSE,     FALSE),
    value      = c(1,       1,         1),
    stringsAsFactors = FALSE)

  out <- rbind(fixed, taxa)
  rownames(out) <- NULL

  if (isTRUE(suggest_codes)) {
    # The spike's "." is fixed by the counting app, so it is held back from
    # the pool and never reassigned.
    fill <- !nzchar(out$code)
    out$code[fill] <- .suggest_codes(out$name[fill], taken = out$code[!fill])
  }
  out
}

# ---- code suggestion ------------------------------------------------------
#
# Codes are what an analyst types hundreds of times per sample, so they are
# ultimately a matter of personal habit. These are a starting point only.
#
# Two sources, in order. First the dictionary shipped with the package
# (inst/extdata/fake_lake/ECG.csv, 231 North American pollen taxa): where a
# Neotoma name matches one of those entries exactly, its curated code is
# reused, because a code an analyst actually chose beats one derived
# mechanically. Otherwise the code is built from the name.
#
# Neotoma's own `taxoncode` is deliberately NOT used. It is a Tilia display
# abbreviation -- "Ace.sa-t", "Ane.s." -- carrying periods and hyphens, and
# "." alone is the spike. Sanitising those would produce collisions and
# keystroke-hostile codes.
#
# Candidates are tried in an order that reproduces the convention in ECG.csv,
# where codes are two uppercase letters: initials for a two-word name
# ("Acer negundo" -> AN), the first two letters for a single word
# ("Abies" -> AB). Longer forms follow only when those are taken.
.strip_qualifiers <- function(x) {
  # Transliterate diacritics first: Neotoma spells one taxon "Isoetes" with a
  # diaeresis, and stripping non-ASCII before folding would split it into
  # "Iso" + "tes" and yield a code built from the wrong letters.
  x <- chartr(
    paste0("\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e8\u00e9\u00ea\u00eb",
           "\u00ec\u00ed\u00ee\u00ef\u00f2\u00f3\u00f4\u00f5\u00f6\u00f9",
           "\u00fa\u00fb\u00fc\u00fd\u00f1\u00e7",
           "\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00c8\u00c9\u00ca\u00cb",
           "\u00cc\u00cd\u00ce\u00cf\u00d2\u00d3\u00d4\u00d5\u00d6\u00d9",
           "\u00da\u00db\u00dc\u00dd\u00d1\u00c7"),
    paste0("aaaaaaeeeeiiiiooooouuuuync",
           "AAAAAAEEEEIIIIOOOOOUUUUYNC"), x)

  x <- gsub("\\([^)]*\\)", " ", x)                  # (parentheticals)
  # Both boundaries required. Without the trailing \\b, "sp" matches the start
  # of "Sparganium" and "Spiraea", leaving "arganium" and "iraea" to be coded
  # from -- which is how Sparganium acquired the code "ARG".
  x <- gsub("\\b(undiff|spp|sp|cf|aff)\\b\\.?", " ", x, ignore.case = TRUE)
  x <- gsub("\\b(subg|subgen|subf|subfam|sect|ser|var|subsp)\\b\\.?", " ", x,
            ignore.case = TRUE)
  x <- gsub("-type\\b", " ", x, ignore.case = TRUE)
  x <- gsub("[^A-Za-z ]+", " ", x)                  # drop digits, slashes, dots
  trimws(gsub("\\s+", " ", x))
}

# Candidate codes for one name, best first. All uppercase letters, so a code
# can never end in a digit -- digits are preservation, and a code ending in one
# would be unparseable at entry.
.code_candidates <- function(name) {
  w <- strsplit(.strip_qualifiers(name), " ", fixed = TRUE)[[1]]
  w <- w[nzchar(w)]
  if (!length(w)) return(character(0))
  up <- function(x) toupper(x)
  w1 <- w[1L]
  cand <- character(0)
  if (length(w) >= 2L)
    cand <- c(cand, up(paste0(substr(w1, 1, 1), substr(w[2L], 1, 1))))
  cand <- c(cand, up(substr(w1, 1, 2)), up(substr(w1, 1, 1)))
  if (length(w) >= 2L)
    cand <- c(cand,
              up(paste0(substr(w1, 1, 1), substr(w[2L], 1, 2))),
              up(paste0(substr(w1, 1, 2), substr(w[2L], 1, 1))))
  cand <- c(cand, up(substr(w1, 1, 3)))
  # Last resort: first letter plus each letter of the alphabet.
  cand <- c(cand, paste0(up(substr(w1, 1, 1)), LETTERS))
  unique(cand[nzchar(cand)])
}

# The curated codes shipped with the package, as name -> code. Read once per
# call; returns an empty map if the file is missing so the derived scheme still
# works from a bare install.
.ecg_codes <- function() {
  f <- system.file("extdata", "fake_lake", "ECG.csv", package = "pcountr")
  if (!nzchar(f) || !file.exists(f)) return(stats::setNames(character(0), character(0)))
  d <- tryCatch(
    utils::read.csv(f, stringsAsFactors = FALSE, colClasses = "character",
                    encoding = "UTF-8"),
    error = function(e) NULL)
  if (is.null(d) || !all(c("code", "name") %in% names(d)))
    return(stats::setNames(character(0), character(0)))
  d <- d[nzchar(trimws(d$code)) & nzchar(trimws(d$name)), , drop = FALSE]
  # Letters-only codes: skip the specials ("#B", ".") so a taxon never inherits
  # a prefix that means something else in the counting app.
  d <- d[grepl("^[A-Za-z]+$", trimws(d$code)), , drop = FALSE]
  stats::setNames(trimws(d$code), trimws(d$name))
}

# Assign a code to each name, avoiding `taken` and each other. Deterministic
# given the input order, so the same query yields the same codes.
.suggest_codes <- function(names, taken = character(0)) {
  ecg  <- .ecg_codes()
  used <- toupper(taken)
  out  <- character(length(names))
  for (i in seq_along(names)) {
    nm <- names[i]
    pick <- NA_character_
    # 1. a curated code for this exact name
    if (nm %in% names(ecg)) {
      c0 <- ecg[[nm]]
      if (!toupper(c0) %in% used) pick <- c0
    }
    # 2. otherwise derive one
    if (is.na(pick)) {
      for (c0 in .code_candidates(nm)) {
        if (!toupper(c0) %in% used) { pick <- c0; break }
      }
    }
    if (is.na(pick)) pick <- ""            # give up rather than invent noise
    out[i] <- pick
    if (nzchar(pick)) used <- c(used, toupper(pick))
  }
  out
}

# Great-circle distance in km, vectorised over lat2/long2. Base R.
.haversine_km <- function(lat1, long1, lat2, long2) {
  r   <- 6371.0088
  p   <- pi / 180
  dla <- (lat2  - lat1)  * p
  dlo <- (long2 - long1) * p
  a   <- sin(dla / 2)^2 +
         cos(lat1 * p) * cos(lat2 * p) * sin(dlo / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

# A GeoJSON polygon circumscribing `km` around a point. Longitude degrees are
# scaled by cos(lat) so the box stays roughly square on the ground. The box
# only has to contain the circle -- true distances are computed afterwards.
.geojson_box <- function(lat, long, km) {
  dlat <- km / 111.32
  dlon <- km / (111.32 * cos(lat * pi / 180))
  w <- long - dlon; e <- long + dlon
  s <- lat  - dlat; n <- lat  + dlat
  f <- function(x) formatC(x, digits = 6, format = "f")
  sprintf(
    paste0('{"type":"Polygon","coordinates":[[',
           '[%s,%s],[%s,%s],[%s,%s],[%s,%s],[%s,%s]]]}'),
    f(w), f(s), f(e), f(s), f(e), f(n), f(w), f(n), f(w), f(s))
}

#' Build a starting dictionary from nearby Neotoma records
#'
#' Finds the Neotoma records nearest a coordinate, tallies which taxa occur
#' most widely among them, and returns a starting point for a dictionary. It
#' is deliberately a *draft*: entry codes are left blank, because codes are
#' the analyst's own muscle memory and nobody should inherit someone else's.
#'
#' Taxa are ranked by the number of distinct **sites** they occur in, not by
#' abundance. A taxon present in one site but two hundred of its samples is a
#' local peculiarity; a taxon present at twelve sites is what an analyst
#' should expect to meet down the microscope. Ranking by abundance would
#' return little beyond *Pinus*, *Artemisia* and Poaceae.
#'
#' Proximity is used rather than a political boundary because vegetation does
#' not stop at state lines. A 250 km search around a site in western Montana
#' reaches into Idaho and Wyoming and finds more relevant neighbours than the
#' state would.
#'
#' @section What this is not:
#' The result is a plain data frame, not a `pollen_dictionary`, because it is
#' expected to be reviewed before use. With `suggest_codes = TRUE` it would
#' load as-is, but the codes are guesses and the groups are Neotoma's rather
#' than yours. With `suggest_codes = FALSE` it cannot load at all until you
#' fill the `code` column, since [read_dic_csv()] drops rows with a blank code.
#'
#' Groups are imported from Neotoma's `ecologicalgroup` as a starting value;
#' they encode your sum decisions, so edit them freely. Check the finished
#' dictionary with [standardize_dic()].
#'
#' @section Cost:
#' One slow spatial query, then one download per dataset among the
#' `max_sites` nearest sites. Expect the whole call to take **a few
#' minutes**, depending on the radius and how many records lie within it.
#' Run it once per site; it is not something to loop over. Requires the
#' **neotoma2** package and a network connection.
#'
#' @param lat,long Latitude and longitude in decimal degrees (WGS 84).
#' @param radius_km Search radius. The default is generous on purpose --
#'   a smaller box is no faster.
#' @param max_sites Maximum number of nearest sites to download. This is the
#'   knob that bounds cost.
#' @param datasettype A Neotoma datasettype, passed through verbatim; see
#'   `neotoma2::get_table("datasettypes")`. Charcoal types carry no taxon
#'   vocabulary and will yield a near-empty result.
#' @param n Number of taxa to return.
#' @param suggest_codes Fill the `code` column with suggestions (default
#'   `TRUE`). Where a taxon name matches an entry in the dictionary shipped
#'   with the package, that curated code is reused; otherwise a code is built
#'   from the name -- initials for a two-word name (*Acer negundo* becomes
#'   `AN`), the first two letters for a single word (*Abies* becomes `AB`),
#'   with longer forms only when those are taken. Suggestions are a starting
#'   point and are meant to be edited: codes are typed hundreds of times per
#'   sample and are properly a matter of personal habit. Set `FALSE` to leave
#'   the column blank.
#' @param file Optional path; when given, the draft is written as CSV.
#' @return A `data.frame` with the columns [read_dic_csv()] expects
#'   (`code`, `alias`, `group`, `name`, `is_special`, `value`), invisibly if
#'   `file` is supplied. `code` is blank throughout except for the spike.
#' @seealso [standardize_dic()], [read_dic_csv()]
#' @export
build_dic_neotoma <- function(lat, long,
                              radius_km  = 250,
                              max_sites  = 20,
                              datasettype = "pollen",
                              n          = 50,
                              suggest_codes = TRUE,
                              file       = NULL) {

  if (!requireNamespace("neotoma2", quietly = TRUE)) {
    stop("build_dic_neotoma() needs the neotoma2 package.\n",
         "  install.packages(\"neotoma2\")", call. = FALSE)
  }
  stopifnot(is.numeric(lat),  length(lat)  == 1L, !is.na(lat),
            is.numeric(long), length(long) == 1L, !is.na(long),
            lat >= -90, lat <= 90, long >= -180, long <= 180,
            is.numeric(radius_km), radius_km > 0,
            is.numeric(max_sites), max_sites >= 1,
            is.numeric(n), n >= 1,
            is.logical(suggest_codes), length(suggest_codes) == 1L,
            !is.na(suggest_codes),
            is.character(datasettype), length(datasettype) == 1L)

  # ---- 1. enumerate candidate records (the one slow call) -----------------
  message("Querying Neotoma within ", radius_km, " km (this is slow)...")
  sites <- neotoma2::get_datasets(
    loc         = .geojson_box(lat, long, radius_km),
    datasettype = datasettype,
    all_data    = TRUE)

  if (length(sites) == 0L) {
    stop("No ", datasettype, " records found within ", radius_km, " km. ",
         "Try a larger radius_km.", call. = FALSE)
  }

  # ---- 2. rank by true distance ------------------------------------------
  xy <- neotoma2::coordinates(sites)
  if (nrow(xy) != length(sites)) {
    stop("Could not match coordinates to sites (", nrow(xy), " vs ",
         length(sites), "). Please report this.", call. = FALSE)
  }
  xy$dist_km <- .haversine_km(lat, long, xy$lat, xy$long)

  # Sites are selected by matching siteid, never by row position. Two traps
  # make that necessary: coordinates() is not documented to return rows in
  # object order, and filtering or sorting `xy` below immediately breaks any
  # correspondence between its row numbers and positions in `sites`. Getting
  # this wrong downloads the wrong sites and still yields a plausible-looking
  # taxon list, so it fails silently.
  obj_ids <- vapply(sites@sites, function(z) z@siteid, integer(1L))

  # The bounding box is wider than the circle at its corners, so drop the
  # overshoot, then sort by true distance.
  xy <- xy[xy$dist_km <= radius_km, , drop = FALSE]
  xy <- xy[order(xy$dist_km), , drop = FALSE]
  if (nrow(xy) == 0L) {
    stop("No ", datasettype, " sites fall within ", radius_km,
         " km once the bounding-box corners are trimmed. ",
         "Try a larger radius_km.", call. = FALSE)
  }

  use  <- utils::head(seq_len(nrow(xy)), max_sites)
  keep <- match(xy$siteid[use], obj_ids)
  if (anyNA(keep)) {
    stop("Could not locate site(s) ",
         paste(xy$siteid[use][is.na(keep)], collapse = ", "),
         " in the query result. Please report this.", call. = FALSE)
  }

  message(sprintf(
    "Found %d sites within %g km; using the nearest %d (furthest %.0f km).",
    nrow(xy), radius_km, length(keep), max(xy$dist_km[use])))

  # ---- 3. download only those sites --------------------------------------
  sel <- sites[keep]
  message("Downloading ", nrow(neotoma2::getids(sel)), " datasets...")
  dl  <- neotoma2::get_downloads(sel, all_data = TRUE)
  s   <- .quiet_samples(dl)

  # ---- 4/5. tally and assemble -------------------------------------------
  out <- .dic_from_samples(s, n = n, datasettype = datasettype,
                           suggest_codes = suggest_codes)

  if (isTRUE(suggest_codes)) {
    message(sprintf(
      "%d taxa returned with suggested codes. Review `code` and `group`, then\n%s",
      nrow(out),
      "load with read_dic(). Codes are a starting point, not a convention."))
  } else {
    message(sprintf("%d taxa returned. Fill in `code` (and check `group`) %s",
                    nrow(out),
                    "before loading with read_dic()."))
  }

  if (!is.null(file)) {
    # fileEncoding is explicit because Neotoma ships diacritics -- a western
    # Montana pollen query returns "Isoetes" spelled with a diaeresis -- and
    # read_dic_csv() reads with encoding = "UTF-8". Without this the round
    # trip depends on the machine's native encoding.
    write.csv(out, file = file, row.names = FALSE, fileEncoding = "UTF-8")
    message("Written to ", file)
    return(invisible(out))
  }
  out
}
