# neotoma_taxonomy.R -- Neotoma's taxonomy over the API.
#
# Why this exists: read_tilia_lookup() reads the XML files that Tilia installs,
# and Tilia runs only on Windows. macOS and Linux analysts could not use
# standardize_dic() at all. This fetches the same taxonomy from Neotoma's API
# instead, so reconciliation works everywhere.
#
# Design notes, all measured against the live API rather than assumed:
#
#   * The synonymy IS available from the API, contrary to what DESIGN.md
#     section 13 said. `dbtables/synonyms` returns
#     `invalidtaxonid -> validtaxonid`, which is exactly the mapping Tilia's
#     XML stores as <Synonym><TaxonID>. Verified row-for-row: synonym 3 is
#     invalidtaxonid 14747 -> validtaxonid 62, and the XML has
#     <Synonym ID="14747"><Name>Iva ciliata-type</Name><TaxonID>62</TaxonID>.
#
#   * The taxa table comes from `/data/taxa`, not `dbtables/taxa`. The dbtables
#     route is leaner but has no `ecolgroup` column; getting ecological groups
#     from `dbtables/ecolgroups` would mean a second unfilterable table plus a
#     choice of "ecolset" (there is one per proxy: 1 = Default plant,
#     8 = Default diatom, 10 = Default palynomorph, ...). `/data/taxa` returns
#     the group already resolved, which avoids that decision entirely.
#
#   * Nothing filters server-side. `taxagroupid=DIA` is silently ignored on
#     both routes -- vascular-plant rows still come back -- so the whole table
#     must be paged and filtered here. `taxa_group` is therefore applied to the
#     cached copy, not to the request.
#
#   * The response carries a `publication` string that is roughly 60% of the
#     payload and of no use here, so it is dropped as each page arrives. The
#     download is tens of MB; the cached object is a small fraction of that.
#
#   * One table, all proxies. Tilia ships eleven per-proxy XML files and
#     pcountr defaulted to the pollen one, which baked pollen into the file
#     layout. `/data/taxa` is a single table spanning vascular plants,
#     diatoms, ostracodes, phytoliths and the rest, distinguished by
#     `taxagroupid`. Diatom and ostracode analysts get a real vocabulary from
#     the same call that serves palynologists.
#
# On the HTTP dependency: `neotoma2::get_table()` reaches only the `dbtables/`
# routes, so it cannot supply `ecolgroup`. Rather than route around that with a
# second table and an ecolset guess, this reads the two routes directly and
# parses with jsonlite, which imports nothing beyond base R and methods.

.NEOTOMA_API <- "https://api.neotomadb.org/v2.0"

# The API base and the cache directory are both overridable by option. This is
# not a user-facing feature so much as a testability one: the graceful-failure
# path -- API unreachable and no cache present -- is the branch CRAN policy
# cares most about, and it cannot be exercised without pointing the base
# somewhere that refuses instantly and the cache somewhere disposable.
.neotoma_api <- function() {
  getOption("pcountr.neotoma_api", .NEOTOMA_API)
}

.neotoma_cache_dir <- function() {
  getOption("pcountr.cache_dir", tools::R_user_dir("pcountr", "cache"))
}

# Page through one API route and rbind the results. `keep` names the columns
# to retain, so a verbose field never reaches memory more than one page at a
# time. Returns NULL on any network failure, so callers can fail gracefully --
# CRAN policy requires that a missing internet resource not error.
.neotoma_page <- function(route, keep = NULL, page = 2000L,
                          max_pages = 200L, quiet = FALSE) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Reading the Neotoma taxonomy needs the jsonlite package.\n",
         "  install.packages(\"jsonlite\")", call. = FALSE)
  }
  chunks <- list()
  offset <- 0L
  for (i in seq_len(max_pages)) {
    u <- sprintf("%s/%s?limit=%d&offset=%d", .neotoma_api(), route,
                 as.integer(page), as.integer(offset))
    # suppressWarnings as well as tryCatch: an unreachable host makes
    # url()/fromJSON() emit a warning ("Timeout of N seconds was reached",
    # "cannot open URL") *before* it errors. Catching only the error lets that
    # warning escape, which CRAN treats as a check warning -- the very thing
    # the graceful-failure rule exists to prevent.
    res <- tryCatch(suppressWarnings(jsonlite::fromJSON(u)),
                    error = function(e) NULL)
    if (is.null(res) || is.null(res$data)) return(NULL)
    d <- res$data
    if (!is.data.frame(d) || nrow(d) == 0L) break
    if (!is.null(keep)) d <- d[, intersect(keep, names(d)), drop = FALSE]
    chunks[[length(chunks) + 1L]] <- d
    if (!quiet && i %% 5L == 0L)
      message("  ...", format(offset + nrow(d), big.mark = ","), " rows")
    if (nrow(d) < page) break
    offset <- offset + nrow(d)
  }
  if (!length(chunks)) return(NULL)
  do.call(rbind, chunks)
}

.neotoma_cache_file <- function() {
  file.path(.neotoma_cache_dir(), "neotoma_taxonomy.rds")
}

# R_user_dir() returns a native path, and file.path() then joins with "/", so
# the result mixes separators on Windows. Only cosmetic, but the path appears
# in user-facing messages.
.neotoma_cache_display <- function(p = .neotoma_cache_file()) {
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

# Turn the two raw API tables into a tilia_lookup object. Split out from
# neotoma_taxonomy() so the whole transformation -- which taxa count as
# accepted, how the synonymy is keyed, what the columns are called -- can be
# tested against fixtures without touching the network.
#
# `taxa` is /data/taxa: taxonid, taxonname, author, taxoncode, ecolgroup,
# highertaxonid, taxagroupid. `syn` is dbtables/synonyms: invalidtaxonid,
# validtaxonid.
.neotoma_assemble <- function(taxa, syn) {
  # Names keyed by id, so a deprecated taxon can be resolved to its name.
  id2name <- stats::setNames(as.character(taxa$taxonname),
                             as.character(taxa$taxonid))

  syn_df <- data.frame(
    name     = unname(id2name[as.character(syn$invalidtaxonid)]),
    taxon_id = as.character(syn$validtaxonid),
    stringsAsFactors = FALSE)
  # A synonym whose deprecated taxon is absent from the taxon list cannot be
  # resolved to a name; drop those rather than carry NA keys.
  syn_df <- syn_df[!is.na(syn_df$name) & nzchar(syn_df$name), , drop = FALSE]
  rownames(syn_df) <- NULL

  # Accepted taxa are those never used as a synonym's *invalid* side. This is
  # equivalent to dbtables/taxa's `valid` flag, which /data/taxa omits.
  deprecated <- as.character(syn$invalidtaxonid)

  out <- data.frame(
    taxon_id   = as.character(taxa$taxonid),
    name       = as.character(taxa$taxonname),
    author     = as.character(taxa$author),
    code       = as.character(taxa$taxoncode),
    taxa_group = as.character(taxa$taxagroupid),
    ecol_group = as.character(taxa$ecolgroup),
    higher_id  = as.character(taxa$highertaxonid),
    stringsAsFactors = FALSE)
  out <- out[!out$taxon_id %in% deprecated, , drop = FALSE]
  out <- out[!is.na(out$name) & nzchar(out$name), , drop = FALSE]
  rownames(out) <- NULL

  attr(out, "synonyms") <- syn_df
  attr(out, "groups")   <- data.frame(
    taxa_group = sort(unique(out$taxa_group[!is.na(out$taxa_group)])),
    stringsAsFactors = FALSE)
  attr(out, "source")  <- .neotoma_api()
  attr(out, "title")   <- "Neotoma taxonomy (API)"
  attr(out, "fetched") <- Sys.time()
  class(out) <- c("tilia_lookup", "data.frame")
  out
}

#' Neotoma's taxonomy, fetched from the API
#'
#' Returns Neotoma's taxon list and its synonymy in the same shape as
#' [read_tilia_lookup()], so it can be passed to [standardize_dic()]
#' interchangeably. Use this when Tilia's lookup files are unavailable --
#' Tilia installs only on Windows, so on macOS and Linux this is the only
#' route to reconciliation.
#'
#' Unlike Tilia, which ships a separate lookup file per proxy, Neotoma stores
#' one taxonomy covering vascular plants, diatoms, ostracodes, phytoliths and
#' the rest, distinguished by `taxa_group`. Filter with `taxa_group` to get the
#' vocabulary for your proxy; the cached copy always holds everything, so
#' switching proxies costs no further download.
#'
#' @section Caching:
#' The first call downloads the full taxon table -- tens of megabytes, since
#' the API cannot filter server-side -- and caches a compact version under
#' [tools::R_user_dir()]. Later calls read the cache and are immediate. Pass
#' `refresh = TRUE` to re-download; `neotoma_taxonomy_cache()` reports where
#' the cache lives and how old it is, and can clear it.
#'
#' Because the taxonomy is live, a reconciliation run today may differ from one
#' next year. The object records when it was fetched, and printing it shows
#' that date; cite it if reproducibility matters.
#'
#' @section Testing hooks:
#' `options(pcountr.neotoma_api =)` and `options(pcountr.cache_dir =)` override
#' the API base and the cache location. These exist so the package's own tests
#' can exercise the offline path without a network call or touching a real
#' cache; they are not intended for normal use.
#'
#' @section Attribution:
#' Neotoma data are made available under CC BY 4.0. If you use this in
#' published work, cite the database (Williams et al., 2018) alongside
#' `pcountr`.
#'
#' @param taxa_group Optional character vector of Neotoma taxa-group codes to
#'   keep, e.g. `"VPL"` for vascular plants or `"DIA"` for diatoms. `NULL`
#'   (default) keeps every group.
#' @param refresh If `TRUE`, ignore any cached copy and re-download.
#' @param quiet Suppress progress messages.
#' @return A data frame of class `tilia_lookup` with columns `taxon_id`,
#'   `name`, `author`, `code`, `taxa_group`, `ecol_group` and `higher_id`,
#'   carrying the synonymy as `attr(, "synonyms")` and the fetch time as
#'   `attr(, "fetched")`. Returns `NULL` invisibly, with a message, if the API
#'   cannot be reached and no cache exists.
#' @references Williams, J.W., Grimm, E.C., Blois, J.L., et al. (2018). The
#'   Neotoma Paleoecology Database, a multiproxy, international,
#'   community-curated data resource. *Quaternary Research*, 89(1), 156-177.
#'   \doi{10.1017/qua.2017.105}
#' @seealso [standardize_dic()], [read_tilia_lookup()],
#'   [neotoma_taxonomy_cache()]
#' @export
neotoma_taxonomy <- function(taxa_group = NULL, refresh = FALSE,
                             quiet = FALSE) {
  stopifnot(is.logical(refresh), length(refresh) == 1L,
            is.logical(quiet), length(quiet) == 1L)
  if (!is.null(taxa_group) && !is.character(taxa_group))
    stop("`taxa_group` must be a character vector or NULL.", call. = FALSE)

  cache <- .neotoma_cache_file()
  obj   <- NULL

  if (!refresh && file.exists(cache)) {
    obj <- tryCatch(readRDS(cache), error = function(e) NULL)
    if (!is.null(obj) && !quiet)
      message("Using cached Neotoma taxonomy from ",
              format(attr(obj, "fetched"), "%Y-%m-%d"),
              " (refresh = TRUE to update).")
  }

  if (is.null(obj)) {
    if (!quiet)
      message("Downloading the Neotoma taxonomy. This is a large, one-time ",
              "fetch;\nthe result is cached for later calls.")

    taxa <- .neotoma_page(
      "data/taxa",
      keep  = c("taxonid", "taxonname", "author", "taxoncode",
                "ecolgroup", "highertaxonid", "taxagroupid"),
      quiet = quiet)
    if (is.null(taxa)) {
      message("Could not reach the Neotoma API and no cached taxonomy is ",
              "available.\nCheck your connection, or use read_tilia_lookup() ",
              "if Tilia is installed.")
      return(invisible(NULL))
    }

    syn <- .neotoma_page("data/dbtables/synonyms",
                         keep  = c("invalidtaxonid", "validtaxonid"),
                         quiet = TRUE)
    if (is.null(syn)) {
      message("Fetched the taxon list but could not reach the synonymy ",
              "table.\nReconciliation would miss deprecated names, so this ",
              "result is not cached.")
      return(invisible(NULL))
    }

    obj <- .neotoma_assemble(taxa, syn)

    dir.create(dirname(cache), recursive = TRUE, showWarnings = FALSE)
    saveRDS(obj, cache, compress = "xz")
    if (!quiet)
      message("Cached ", format(nrow(obj), big.mark = ","), " accepted taxa and ",
              format(nrow(attr(obj, "synonyms")), big.mark = ","),
              " synonyms to\n  ", .neotoma_cache_display(cache))
  }

  if (!is.null(taxa_group)) {
    keep_syn <- attr(obj, "synonyms")
    fetched  <- attr(obj, "fetched")
    sub <- obj[obj$taxa_group %in% taxa_group, , drop = FALSE]
    if (nrow(sub) == 0L)
      stop("No taxa in group(s): ", paste(taxa_group, collapse = ", "),
           ".\nAvailable groups: ",
           paste(sort(unique(obj$taxa_group)), collapse = ", "), call. = FALSE)
    rownames(sub) <- NULL
    # The synonymy is kept whole on purpose: a deprecated name may point at an
    # accepted taxon inside the filtered group even when the deprecated taxon
    # itself is not, and standardize_dic() resolves targets by id.
    attr(sub, "synonyms") <- keep_syn
    attr(sub, "groups")   <- attr(obj, "groups")
    attr(sub, "source")   <- attr(obj, "source")
    attr(sub, "title")    <- paste0("Neotoma taxonomy (API; ",
                                    paste(taxa_group, collapse = "+"), ")")
    attr(sub, "fetched")  <- fetched
    class(sub) <- c("tilia_lookup", "data.frame")
    obj <- sub
  }
  obj
}

#' Inspect or clear the cached Neotoma taxonomy
#'
#' [neotoma_taxonomy()] caches its download under [tools::R_user_dir()]. This
#' reports where that file is and how old it is, and can delete it.
#'
#' @param clear If `TRUE`, delete the cached file.
#' @return A list with the cache `path`, whether it `exists`, its `size` in
#'   bytes and the `fetched` time, invisibly.
#' @seealso [neotoma_taxonomy()]
#' @export
neotoma_taxonomy_cache <- function(clear = FALSE) {
  path <- .neotoma_cache_file()
  ok   <- file.exists(path)
  info <- list(path = path, exists = ok,
               size = if (ok) file.info(path)$size else NA_real_,
               fetched = NA)
  if (ok) {
    obj <- tryCatch(readRDS(path), error = function(e) NULL)
    info$fetched <- if (is.null(obj)) NA else attr(obj, "fetched")
  }
  if (clear && ok) {
    unlink(path)
    message("Deleted ", .neotoma_cache_display(path))
    info$exists <- FALSE
  } else if (!ok) {
    message("No cached Neotoma taxonomy. It will be created on first use of ",
            "neotoma_taxonomy().")
  } else {
    message("Cached Neotoma taxonomy\n  path   : ", .neotoma_cache_display(path),
            "\n  size   : ", format(round(info$size / 1024), big.mark = ","), " KB",
            "\n  fetched: ", format(info$fetched, "%Y-%m-%d %H:%M"))
  }
  invisible(info)
}
