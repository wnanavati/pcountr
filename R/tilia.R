# tilia.R -- Tilia / Neotoma taxon lookup integration
#
# Two functions: a pure reader for Tilia's lookup XML, and a reconciler that
# checks a pcountr dictionary against it. See DESIGN.md section 13 for why the
# lookup is treated as an authority to check against rather than a source to
# copy from.

# TaxaGroup codes that contain palynomorphs. The pollen lookup file is the whole
# Neotoma taxonomy -- 8,500 diatoms and 15,000 insects included -- so restricting
# to these avoids matching a pollen taxon against a beetle.
.palyn_taxa_groups <- function() {
  c("VPL",  # Vascular plants
    "BRY",  # Bryophytes
    "UPA",  # Unidentified palynomorphs
    "ALG",  # Algae
    "FUN",  # Fungi
    "ACR",  # Acritarchs
    "DIN",  # Dinoflagellates
    "PLA",  # Plants undiff.
    "LAB",  # Laboratory analyses (spike markers)
    "CHR")  # Charcoal
}

.tilia_files <- function() {
  c(pollen           = "NeotomaPollenTaxa.xml",
    pollentrap       = "NeotomaPollenTrapTaxa.xml",
    diatom           = "NeotomaDiatomTaxa.xml",
    plantmacrofossil = "NeotomaPlantMacrofossilTaxa.xml",
    phytolith        = "NeotomaPhytolithTaxa.xml",
    charcoal         = "NeotomaCharcoalTaxa.xml",
    macrocharcoal    = "NeotomaMacrocharcoalTaxa.xml",
    microcharcoal    = "NeotomaMicrocharcoalTaxa.xml",
    testateamoebae   = "NeotomaTestateAmoebaeTaxa.xml",
    ostracode        = "NeotomaOstracodeTaxa.xml",
    vertebrate       = "NeotomaVertebrateFaunaTaxa.xml")
}

# Tilia's own documentation gives %LOCALAPPDATA%\\Tilia\\Lookup, while some
# installs use ProgramData. Both are checked, first existing wins, so a user
# does not have to know which their install chose. options(pcountr.tilia_lookup)
# overrides, and the ProgramData path is the fallback when neither exists so
# that the error message names a concrete location.
.tilia_default_path <- function() {
  p <- getOption("pcountr.tilia_lookup", NULL)
  if (!is.null(p) && nzchar(p)) return(p)
  local_app <- Sys.getenv("LOCALAPPDATA", "")
  cands <- c(
    if (nzchar(local_app)) file.path(gsub("\\\\", "/", local_app), "Tilia", "Lookup"),
    "C:/ProgramData/Tilia/Lookup",
    "C:/Users/Public/AppData/Local/Tilia/Lookup"
  )
  hit <- cands[dir.exists(cands)]
  if (length(hit)) hit[1L] else "C:/ProgramData/Tilia/Lookup"
}

# Session cache, keyed on file path + mtime. Parsing the pollen file takes a few
# seconds, and the interactive workflow re-reads it often.
.tilia_cache <- new.env(parent = emptyenv())


#' Read a Tilia taxon lookup file
#'
#' Parses one of Tilia's Neotoma taxon lookup files into a data frame. This is a
#' pure reader: it returns what the file contains and makes no judgements about
#' it. Reconciliation against a dictionary is [standardize_dic()]'s job.
#'
#' Tilia stores its lookups as XML, one file per proxy, under
#' `%LOCALAPPDATA%/Tilia/Lookup` or `C:/ProgramData/Tilia/Lookup` depending on
#' the install; both are checked. **Tilia runs only on Windows**, so on macOS
#' and Linux use [neotoma_taxonomy()] instead, which fetches the same taxonomy
#' from Neotoma's API. Each taxon carries a Neotoma taxon ID, an
#' accepted name, a Tilia display abbreviation, a three-letter `TaxaGroup`
#' (the organism or proxy dimension) and a four-letter `EcolGroup` (the
#' ecological dimension within it) -- for example `TRSH` trees and shrubs,
#' `UPHE` upland herbs, `VACR` terrestrial vascular cryptogams, `AQVP` aquatic
#' vascular plants.
#'
#' Note that the `Code` field holds Tilia's *display* abbreviation (`Ane.s.`,
#' `Pla.sp1LLC`) and not a keystroke code. Counting codes are one or two
#' characters chosen by the analyst and belong in the dictionary, not here.
#'
#' @section What is returned:
#' A data frame of accepted taxa, with two attributes:
#'   \describe{
#'     \item{`synonyms`}{Data frame of `name` and `taxon_id`: deprecated names
#'       mapped to the accepted taxon they now refer to. This is Neotoma's own
#'       synonymy, so matches drawn from it are authoritative rather than
#'       guessed.}
#'     \item{`groups`}{Data frame of the `TaxaGroup` / `EcolGroup` hierarchy
#'       declared at the head of the file, with names.}
#'   }
#'
#' @section Size:
#' The pollen file is around 11 MB and holds roughly 49,000 taxa, because it
#' contains the entire Neotoma taxonomy rather than only palynomorphs. Parsing
#' takes a few seconds; the result is cached for the session, keyed on the file's
#' path and modification time. [standardize_dic()] restricts matching to
#' palynomorph `TaxaGroup`s by default.
#'
#' @param path Directory holding the lookup files, or the full path to a single
#'   `.xml` file. `NULL` (default) uses `getOption("pcountr.tilia_lookup")` if
#'   set, otherwise the first of `%LOCALAPPDATA%/Tilia/Lookup` or
#'   `C:/ProgramData/Tilia/Lookup` that exists.
#' @param type Which lookup to read when `path` is a directory. One of
#'   `"pollen"` (default), `"pollentrap"`, `"diatom"`, `"plantmacrofossil"`,
#'   `"phytolith"`, `"charcoal"`, `"macrocharcoal"`, `"microcharcoal"`,
#'   `"testateamoebae"`, `"ostracode"`, `"vertebrate"`. Ignored when `path`
#'   points at a file.
#'
#' @return A `tilia_lookup` data frame: `taxon_id`, `name`, `author`, `code`,
#'   `taxa_group`, `ecol_group`, `higher_id`, plus the `synonyms` and `groups`
#'   attributes described above.
#'
#' @seealso [standardize_dic()], [neotoma_taxonomy()], [read_dic()]
#' @export
read_tilia_lookup <- function(path = NULL, type = "pollen") {
  if (!requireNamespace("xml2", quietly = TRUE))
    stop("Reading Tilia lookup files needs the 'xml2' package.\n",
         "  install.packages(\"xml2\")", call. = FALSE)

  if (is.null(path)) path <- .tilia_default_path()

  if (grepl("\\.xml$", path, ignore.case = TRUE)) {
    file <- path
  } else {
    files <- .tilia_files()
    type  <- match.arg(type, names(files))
    file  <- file.path(path, files[[type]])
  }

  if (!file.exists(file))
    stop("Tilia lookup file not found:\n  ", file, "\n",
         "Set the location with path = or ",
         "options(pcountr.tilia_lookup = \"...\").", call. = FALSE)

  key <- paste0(normalizePath(file, winslash = "/"), "|",
                as.numeric(file.mtime(file)))
  if (!is.null(.tilia_cache[[key]])) return(.tilia_cache[[key]])

  doc <- xml2::read_xml(file)

  nodes <- xml2::xml_find_all(doc, "/TiliaTaxa/Taxa/Taxon")
  if (!length(nodes))
    stop("No <Taxon> records found in ", basename(file),
         " -- is this a Tilia lookup file?", call. = FALSE)

  fld <- function(tag) {
    v <- xml2::xml_text(xml2::xml_find_first(nodes, paste0("./", tag)))
    v[is.na(v)] <- NA_character_
    v
  }

  out <- data.frame(
    taxon_id   = xml2::xml_attr(nodes, "ID"),
    name       = fld("Name"),
    author     = fld("Author"),
    code       = fld("Code"),
    taxa_group = fld("TaxaGroup"),
    ecol_group = fld("EcolGroup"),
    higher_id  = fld("HigherID"),
    stringsAsFactors = FALSE,
    row.names  = NULL
  )
  out <- out[!is.na(out$name) & nzchar(out$name), , drop = FALSE]

  # Neotoma's own synonymy: deprecated name -> accepted taxon_id
  snodes <- xml2::xml_find_all(doc, "/TiliaTaxa/Synonyms/Synonym")
  syn <- if (length(snodes)) {
    data.frame(
      name     = xml2::xml_text(xml2::xml_find_first(snodes, "./Name")),
      taxon_id = xml2::xml_text(xml2::xml_find_first(snodes, "./TaxonID")),
      stringsAsFactors = FALSE, row.names = NULL)
  } else {
    data.frame(name = character(0), taxon_id = character(0),
               stringsAsFactors = FALSE)
  }
  syn <- syn[!is.na(syn$name) & nzchar(syn$name), , drop = FALSE]

  # The TaxaGroup / EcolGroup hierarchy declared at the head of the file
  gnodes <- xml2::xml_find_all(doc, "/TiliaTaxa/EcologicalGroups/TaxaGroup")
  grp <- if (length(gnodes)) {
    do.call(rbind, lapply(gnodes, function(g) {
      eg <- xml2::xml_find_all(g, "./EcologicalGroup")
      if (!length(eg)) return(NULL)
      data.frame(
        taxa_group      = xml2::xml_attr(g, "Code"),
        taxa_group_name = xml2::xml_attr(g, "Name"),
        ecol_group      = xml2::xml_text(xml2::xml_find_first(eg, "./Code")),
        ecol_group_name = xml2::xml_text(xml2::xml_find_first(eg, "./Name")),
        stringsAsFactors = FALSE, row.names = NULL)
    }))
  } else NULL

  attr(out, "synonyms") <- syn
  attr(out, "groups")   <- grp
  attr(out, "source")   <- file
  attr(out, "title")    <- xml2::xml_text(
                             xml2::xml_find_first(doc, "/TiliaTaxa/Title"))
  class(out) <- c("tilia_lookup", "data.frame")

  assign(key, out, envir = .tilia_cache)
  out
}


#' @export
print.tilia_lookup <- function(x, ...) {
  src <- attr(x, "source") %||% "?"
  # basename() on a URL leaves only the last path segment ("v2.0"), which tells
  # the reader nothing; show the host for an API source and the file name for a
  # Tilia lookup.
  src <- if (grepl("^https?://", src))
           sub("^https?://([^/]+).*$", "\\1", src) else basename(src)

  cat("<tilia_lookup>", attr(x, "title") %||% "", "\n")
  cat("  source  :", src, "\n")
  nsyn <- nrow(attr(x, "synonyms") %||% data.frame())
  cat("  taxa    :", nrow(x), "accepted;", nsyn, "synonyms\n")
  pal <- sum(x$taxa_group %in% .palyn_taxa_groups(), na.rm = TRUE)
  # Only worth saying when there are any. A diatom or ostracode lookup is not
  # a deficient pollen lookup, and reporting "0 palynomorphs" reads as though
  # it were.
  if (pal > 0L) cat("  of which", pal, "are palynomorphs\n")
  tg <- sort(table(x$taxa_group), decreasing = TRUE)
  if (length(tg))
    cat("  largest :",
        paste(sprintf("%s (%d)", names(tg)[seq_len(min(5, length(tg)))],
                      as.integer(tg)[seq_len(min(5, length(tg)))]),
              collapse = ", "), "\n")
  # On a taxa_group-filtered lookup the synonymy is deliberately left whole,
  # because a deprecated name may point at an accepted taxon inside the filter
  # even when the deprecated taxon itself sits outside it. Say so, or the count
  # looks like a filtering bug.
  if (length(tg) == 1L && nsyn > 0L)
    cat("  synonymy kept whole across all groups; targets resolve by id\n")
  invisible(x)
}


# Orthographic normalisation for matching. Deliberately narrow: it folds
# diacritics, punctuation and abbreviation variants, and nothing else.
#
# It must NOT strip "-type", "cf." or "aff.". Those encode how precise a
# determination is -- "Betula-type" is a morphotype resembling Betula, not a
# determination of Betula -- so folding them would silently change the meaning
# of a taxon rather than its spelling.
.norm_taxon <- function(s) {
  s <- as.character(s)
  s[is.na(s)] <- ""
  s <- tolower(s)
  # Fold Latin-1 diacritics explicitly, with \u escapes so this file stays
  # ASCII. iconv(to = "ASCII//TRANSLIT") would be shorter but its output is
  # platform-dependent and can emit "?" on Windows, which would silently break
  # matching for names such as Isoetes / Iso[e-diaeresis]tes.
  s <- chartr(
    paste0("\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e8\u00e9\u00ea\u00eb",
           "\u00ec\u00ed\u00ee\u00ef\u00f2\u00f3\u00f4\u00f5\u00f6\u00f9",
           "\u00fa\u00fb\u00fc\u00fd\u00f1\u00e7"),
    "aaaaaaeeeeiiiiooooouuuuync", s)
  s <- gsub("\\bc\\.\\s*f\\.", "cf.", s)      # "c.f." -> "cf."
  s <- gsub("\\bsubgen\\.", "subg.", s)
  s <- gsub("\\bsubfam\\.", "subf.", s)
  s <- gsub("[^a-z0-9]+", " ", s)
  trimws(s)
}

# Normalised Levenshtein similarity in [0, 1]
.taxon_sim <- function(x, pool) {
  d <- utils::adist(x, pool)[1, ]
  1 - d / pmax(nchar(x), nchar(pool))
}


#' Reconcile a dictionary against a Tilia/Neotoma lookup
#'
#' Checks each taxon name in a `pollen_dictionary` against a Tilia lookup and
#' reports what it found. By default nothing is changed: the point is to show you
#' the differences and let you decide. Names can then be adopted selectively with
#' `apply`.
#'
#' @section Why reconcile rather than replace:
#' A lookup cannot serve as a counting dictionary. Its `Code` field holds Tilia's
#' display abbreviation, not the one- or two-character keystroke code you type at
#' the microscope, and it lists tens of thousands of taxa where a working
#' dictionary holds tens. The lookup is an authority to check against; your
#' dictionary stays yours.
#'
#' The payoff is chiefly Neotoma submission via [write_tlx()]: names that match
#' Neotoma's authority list need no reconciliation on upload. It also surfaces
#' deprecated names and misfiled groups you may want to correct regardless.
#'
#' @section The status column:
#' Each row is classified by how its name matched, in this order:
#'   \describe{
#'     \item{`exact`}{Name found verbatim among accepted taxa. Nothing to do.}
#'     \item{`alias`}{Matched an entry in your own `aliases` file. Your
#'       assertion, so safe to apply in bulk.}
#'     \item{`variant`}{Differs from an accepted name only in orthography --
#'       diacritics, `c.f.`/`cf.`, `subgen.`/`subg.`. Safe to apply
#'       mechanically.}
#'     \item{`synonym`}{Neotoma's own synonymy maps the name to a different
#'       accepted taxon. Authoritative, but a taxonomic judgement: review it,
#'       and note the revision can run either way. Modern segregates such as
#'       *Spinulum annotinum* may be *newer* than the lookup's
#'       *Lycopodium annotinum*.}
#'     \item{`suggestion`}{No authoritative match; the closest name by string
#'       similarity is shown with its score. **Never applied as a class** --
#'       only ever by code or name. String similarity is unreliable on taxon
#'       names, and no cutoff makes it reliable: `Cerealia undiff.` scores 0.75
#'       against *Sordaria* undiff., a fungus, while the correct
#'       `Dendrolycopodium obscurum` -> *Lycopodium obscurum* scores only 0.72.
#'       Scores also tie, in which case the candidate shown is whichever comes
#'       first in the pool rather than the best answer.}
#'     \item{`unmatched`}{No match and no candidate above `cutoff`.}
#'   }
#'
#' @section Ecological groups are yours, and are not compared by default:
#' `ecol_group` reports the lookup's four-letter ecological group for reference,
#' which is useful when preparing a Neotoma upload. **No comparison against your
#' own `group` is made**, and `group_differs` is `NA` unless you supply
#' `group_map`.
#'
#' This is on the reasoning that an ecological group is in practice a "sum by"
#' list, and that the baggage around ecological affinity makes a single
#' standardised list impractical to hold centrally. Cyperaceae, for instance, is
#' `UPHE` in the lookup but is legitimately aquatic in some settings, and the
#' analyst who saw the landscape is better placed to judge than an authority
#' file. `pcountr` already treats this as local configuration: `pollen_sum` is
#' the sum-by list, set per site.
#'
#' If you do want the comparison, pass a mapping from your codes to the lookup's,
#' e.g. `group_map = c(A = "TRSH", B = "UPHE", F = "VACR", Q = "AQVP",
#' X = "UNID")`, and rows that disagree are flagged. Even then nothing is
#' changed: reassigning a group moves a taxon between pollen sums and so alters
#' every percentage, concentration and accumulation rate.
#'
#' @section Building an alias file:
#' Some names have no automatic answer because the equivalence is a judgement
#' about your own conventions -- whether `Monolete spore undiff.` is Neotoma's
#' `Filicopsida (monolete) undiff.`, or how you treat reworked pre-Quaternary
#' grains. Point `aliases` at a path that does not exist yet and a template is
#' written for you, pre-filled with the unresolved names and a blank
#' `accepted_name` column. Fill it in once and those rows resolve as `alias`
#' from then on.
#'
#' Nothing of the sort ships with `pcountr`: such mappings are lab conventions,
#' not universal facts, and a package asserting them on your behalf would be
#' making a scientific claim it cannot stand behind.
#'
#' @param dic A `pollen_dictionary` (from [read_dic()]) or a data frame with
#'   `code`, `name` and `group` columns.
#' @param lookup A `tilia_lookup` from [read_tilia_lookup()] or
#'   [neotoma_taxonomy()]. `NULL` (default)
#'   calls it with default arguments.
#' @param aliases Optional path to a two-column CSV (`name`, `accepted_name`) of
#'   your own equivalences. If the file does not exist, a template is written
#'   from the unresolved rows and nothing is applied.
#' @param apply What to adopt. `"none"` (default) changes nothing. Otherwise a
#'   character vector combining the classes `"variant"`, `"synonym"`, `"alias"`
#'   with any individual dictionary `code`s or `name`s. `"suggestion"` is not
#'   accepted as a class -- name those rows individually. Any element matching
#'   neither a class nor a row is an error.
#' @param taxa_groups Lookup `TaxaGroup` codes to match against. Defaults to the
#'   palynomorph groups; `NULL` matches against everything in the file.
#' @param group_map Optional named character vector mapping your `group` codes to
#'   lookup `ecol_group` codes, used only to compute `group_differs`. `NULL`
#'   (default) makes no comparison and leaves `group_differs` as `NA`; see the
#'   section on ecological groups for why that is the default.
#' @param cutoff Minimum similarity for a `suggestion`. Default `0.55`.
#' @param quiet Suppress the applied-changes message.
#'
#' @return The dictionary, unchanged unless `apply` says otherwise, with the
#'   reconciliation report attached as `attr(x, "report")` and an extra
#'   `standardized_dic` class so that printing shows the report. The object
#'   remains a valid `pollen_dictionary` for [write_dic_csv()] and everything
#'   else.
#'
#' @seealso [read_tilia_lookup()], [read_dic()], [write_dic_csv()], [write_tlx()]
#' @export
standardize_dic <- function(dic,
                            lookup      = NULL,
                            aliases     = NULL,
                            apply       = "none",
                            taxa_groups = .palyn_taxa_groups(),
                            group_map   = NULL,
                            cutoff      = 0.55,
                            quiet       = FALSE) {

  if (!is.data.frame(dic) || !all(c("code", "name") %in% names(dic)))
    stop("`dic` must be a pollen_dictionary or a data frame with `code` and ",
         "`name` columns.", call. = FALSE)
  # With no lookup supplied, prefer a local Tilia install -- it is offline and
  # is whatever version the analyst's Tilia is pinned to -- and fall back to
  # Neotoma's API, which is the only route on macOS and Linux since Tilia is
  # Windows-only.
  if (is.null(lookup)) {
    lookup <- tryCatch(read_tilia_lookup(), error = function(e) NULL)
    if (is.null(lookup)) {
      message("No Tilia lookup files found; using Neotoma's API instead.")
      lookup <- neotoma_taxonomy()
      if (is.null(lookup))
        stop("Could not obtain a taxonomy from Tilia or from the Neotoma API.",
             call. = FALSE)
    }
  }
  if (!inherits(lookup, "tilia_lookup"))
    stop("`lookup` must come from read_tilia_lookup() or neotoma_taxonomy().",
         call. = FALSE)

  # ---- the pool of accepted taxa, and Neotoma's synonymy -------------------
  pool <- if (is.null(taxa_groups)) lookup else
            lookup[lookup$taxa_group %in% taxa_groups, , drop = FALSE]
  if (!nrow(pool))
    stop("No taxa left after filtering by taxa_groups.", call. = FALSE)

  acc_name <- pool$name
  acc_ecol <- stats::setNames(pool$ecol_group, pool$name)
  acc_id   <- stats::setNames(pool$taxon_id,   pool$name)
  id2name  <- stats::setNames(pool$name,       pool$taxon_id)

  nacc <- .norm_taxon(acc_name)
  nacc_map <- stats::setNames(acc_name, nacc)
  nacc_map <- nacc_map[!duplicated(names(nacc_map))]

  syn <- attr(lookup, "synonyms")
  if (is.null(syn)) syn <- data.frame(name = character(0),
                                      taxon_id = character(0))
  syn_map  <- stats::setNames(syn$taxon_id, syn$name)
  nsyn     <- .norm_taxon(syn$name)
  nsyn_map <- stats::setNames(syn$taxon_id, nsyn)
  nsyn_map <- nsyn_map[!duplicated(names(nsyn_map))]

  # ---- user alias file ------------------------------------------------------
  al_map <- character(0)
  alias_template <- FALSE
  if (!is.null(aliases)) {
    if (file.exists(aliases)) {
      # colClasses = "character" matters: a freshly written template has an
      # all-blank accepted_name column, which read.csv would otherwise return
      # as logical NA, and trimws(NA) becomes the string "NA".
      a <- utils::read.csv(aliases, stringsAsFactors = FALSE,
                           colClasses = "character")
      if (!all(c("name", "accepted_name") %in% names(a)))
        stop("`aliases` file needs `name` and `accepted_name` columns: ",
             aliases, call. = FALSE)
      a <- a[!is.na(a$accepted_name) & nzchar(trimws(a$accepted_name)), ,
             drop = FALSE]
      al_map <- stats::setNames(trimws(a$accepted_name), trimws(a$name))
    } else {
      alias_template <- TRUE
    }
  }

  # ---- classify every row --------------------------------------------------
  n     <- nrow(dic)
  nm    <- as.character(dic$name)
  nnm   <- .norm_taxon(nm)
  grp   <- if ("group" %in% names(dic)) as.character(dic$group) else rep(NA_character_, n)

  status <- rep(NA_character_, n)
  target <- rep(NA_character_, n)
  simv   <- rep(NA_real_,      n)

  for (i in seq_len(n)) {
    if (!nzchar(nm[i])) { status[i] <- "unmatched"; next }

    if (nm[i] %in% acc_name) { status[i] <- "exact"; target[i] <- nm[i]; next }

    if (nm[i] %in% names(al_map)) {
      status[i] <- "alias"; target[i] <- al_map[[nm[i]]]; next
    }

    # Neotoma synonymy, raw name.
    #
    # Single-bracket indexing, not [[: a synonym's target may lie outside the
    # filtered pool -- 439 of the 2,182 synonyms in the pollen lookup point at
    # non-palynomorph taxa -- and [[ on an absent name throws "subscript out of
    # bounds". [ yields NA, so such rows fall through to fuzzy matching instead,
    # which is the right outcome: the accepted taxon is out of scope for this
    # dictionary.
    if (nm[i] %in% names(syn_map)) {
      tgt <- unname(id2name[ syn_map[[nm[i]]] ])
      if (length(tgt) && !is.na(tgt)) {
        target[i] <- tgt
        status[i] <- if (identical(.norm_taxon(nm[i]), .norm_taxon(tgt)))
                       "variant" else "synonym"
        next
      }
    }

    # orthographic match against accepted names
    if (nnm[i] %in% names(nacc_map)) {
      status[i] <- "variant"; target[i] <- nacc_map[[nnm[i]]]; next
    }

    # Neotoma synonymy, normalised name. Abbreviation differences such as
    # "subgen." for "subg." otherwise hide authoritative answers here.
    if (nnm[i] %in% names(nsyn_map)) {
      tgt <- unname(id2name[ nsyn_map[[nnm[i]]] ])   # [ not [[; see above
      if (length(tgt) && !is.na(tgt)) {
        target[i] <- tgt
        status[i] <- if (identical(nnm[i], .norm_taxon(tgt)))
                       "variant" else "synonym"
        next
      }
    }

    s <- .taxon_sim(nm[i], acc_name)
    j <- which.max(s)
    if (length(j) && is.finite(s[j]) && s[j] >= cutoff) {
      status[i] <- "suggestion"; target[i] <- acc_name[j]
      simv[i]   <- round(s[j], 2)
    } else {
      status[i] <- "unmatched"
    }
  }

  eg  <- unname(acc_ecol[target]); eg[is.na(eg)] <- NA_character_
  # group_differs stays NA unless the caller supplies a mapping, on the
  # reasoning that a dictionary's groups encode the analyst's own pollen-sum
  # decisions and are not the lookup's to correct (see the section in
  # ?standardize_dic). No comparison is made by default, and NA records
  # "not compared" rather than "compared and agreed".
  exp <- if (is.null(group_map)) rep(NA_character_, length(grp))
         else unname(group_map[grp])
  report <- data.frame(
    code          = as.character(dic$code),
    name          = nm,
    status        = status,
    accepted_name = target,
    similarity    = simv,
    taxon_id      = unname(acc_id[target]),
    group         = grp,
    ecol_group    = eg,
    group_differs = if (is.null(group_map)) rep(NA, length(grp))
                    else !is.na(eg) & !is.na(exp) & eg != exp,
    stringsAsFactors = FALSE, row.names = NULL
  )

  # ---- alias template ------------------------------------------------------
  if (alias_template) {
    todo <- report[report$status %in% c("suggestion", "unmatched"), , drop = FALSE]
    utils::write.csv(
      data.frame(code = todo$code, name = todo$name,
                 accepted_name = "", note = todo$status,
                 suggested = ifelse(is.na(todo$accepted_name), "",
                                    todo$accepted_name),
                 stringsAsFactors = FALSE),
      aliases, row.names = FALSE)
    message("Wrote an alias template with ", nrow(todo), " unresolved name(s):\n  ",
            aliases, "\nFill in `accepted_name` where you want a mapping, then ",
            "re-run with the same `aliases =` path.")
  }

  # ---- apply ---------------------------------------------------------------
  CLASSES <- c("variant", "synonym", "alias")
  apply   <- as.character(apply)
  changed <- integer(0)

  if (!(length(apply) == 1L && identical(apply, "none"))) {
    if ("suggestion" %in% apply)
      stop("`apply` will not take \"suggestion\" as a class -- string ",
           "similarity is unreliable on taxon names. Name those rows ",
           "individually by code instead.", call. = FALSE)
    if ("all" %in% apply)
      stop("`apply` has no \"all\" shorthand, by design. Name the classes ",
           "you trust.", call. = FALSE)

    cls  <- intersect(apply, CLASSES)
    rest <- setdiff(apply, c(CLASSES, "none"))

    bad <- rest[!(rest %in% report$code | rest %in% report$name)]
    if (length(bad))
      stop("`apply` element(s) match no class, code or name in the ",
           "dictionary:\n  ", paste(bad, collapse = ", "), call. = FALSE)

    sel <- report$status %in% cls |
           report$code %in% rest | report$name %in% rest
    sel <- sel & !is.na(report$accepted_name) &
           report$accepted_name != report$name
    changed <- which(sel)

    if (length(changed)) {
      dic$name[changed] <- report$accepted_name[changed]
      if (!quiet) {
        message("standardize_dic(): applied ", length(changed), " change(s)")
        for (i in changed)
          message(sprintf("  %-5s %-32s -> %-32s [%s%s]",
                          report$code[i],
                          substr(report$name[i], 1, 31),
                          substr(report$accepted_name[i], 1, 31),
                          report$status[i],
                          if (is.na(report$similarity[i])) ""
                            else paste0(", ", report$similarity[i])))
      }
      report$applied <- seq_len(nrow(report)) %in% changed
    }
  }
  if (is.null(report$applied)) report$applied <- FALSE

  attr(dic, "report") <- report
  attr(dic, "lookup_title") <- attr(lookup, "title")
  attr(dic, "n_pool") <- nrow(pool)
  if (!inherits(dic, "standardized_dic"))
    class(dic) <- c("standardized_dic", class(dic))
  dic
}


#' @export
print.standardized_dic <- function(x, ...) {
  r <- attr(x, "report")
  cat("Dictionary standardisation report\n")
  cat("  dictionary :", nrow(r), "taxa\n")
  cat("  lookup     :", attr(x, "lookup_title") %||% "?", "-",
      format(attr(x, "n_pool") %||% NA), "taxa matched against\n\n")

  for (k in c("exact", "variant", "synonym", "alias", "suggestion", "unmatched")) {
    m <- sum(r$status == k, na.rm = TRUE)
    if (m) cat(sprintf("    %-14s%4d\n", k, m))
  }
  compared <- any(!is.na(r$group_differs))
  if (compared)
    cat(sprintf("    %-14s%4d\n", "group differs",
                sum(r$group_differs, na.rm = TRUE)))

  if (any(r$applied)) {
    cat("\n  ", sum(r$applied), " name(s) applied.\n", sep = "")
  } else {
    cat("\n  Nothing changed. See ?standardize_dic for `apply`.\n")
  }

  blocks <- list(
    c("variant",    "orthographic only, safe to apply"),
    c("synonym",    "deprecated name; accepted name available (review)"),
    c("alias",      "from your alias file"),
    c("suggestion", "ADVISORY ONLY, never applied as a class"),
    c("unmatched",  "no match found")
  )
  hdr <- sprintf("  %-5s%-32s%-11s%-32s%4s%5s%6s",
                 "code", "name", "status", "accepted name", "sim", "grp", "ecol")
  # ecol_group is derived from accepted_name. On a suggestion the accepted name
  # is only a candidate, and on an unmatched row there is none at all, so
  # printing its ecological group beside the analyst's own group would attribute
  # a group the taxon does not have -- Microcharcoal is not an alga because its
  # nearest string match happens to be. Blanked here; the column is unchanged in
  # attr(x, "report").
  ecol_shown <- function(i) {
    if (r$status[i] %in% c("suggestion", "unmatched")) return("")
    if (is.na(r$ecol_group[i])) return("-")
    r$ecol_group[i]
  }
  for (b in blocks) {
    rows <- which(r$status == b[1])
    if (!length(rows)) next
    cat("\n-- ", toupper(b[1]), " - ", b[2], " (", length(rows), ")\n", sep = "")
    cat(hdr, "\n"); cat("  ", strrep("-", 94), "\n", sep = "")
    for (i in rows)
      cat(sprintf("  %-5s%-32s%-11s%-32s%4s%5s%6s%s\n",
                  r$code[i], substr(r$name[i], 1, 31), r$status[i],
                  substr(ifelse(is.na(r$accepted_name[i]), "",
                                r$accepted_name[i]), 1, 31),
                  ifelse(is.na(r$similarity[i]), "",
                         formatC(r$similarity[i], format = "f", digits = 2)),
                  ifelse(is.na(r$group[i]), "-", r$group[i]),
                  ecol_shown(i),
                  if (isTRUE(r$group_differs[i])) "  <<" else ""))
  }

  gd <- if (compared) which(r$group_differs & r$status == "exact") else integer(0)
  if (length(gd)) {
    cat("\n-- GROUP DIFFERS - name matches exactly, group does not (",
        length(gd), ")\n", sep = "")
    cat(hdr, "\n"); cat("  ", strrep("-", 94), "\n", sep = "")
    for (i in gd)
      cat(sprintf("  %-5s%-32s%-11s%-32s%4s%5s%6s  <<\n",
                  r$code[i], substr(r$name[i], 1, 31), r$status[i],
                  substr(r$accepted_name[i], 1, 31), "",
                  ifelse(is.na(r$group[i]), "-", r$group[i]),
                  ifelse(is.na(r$ecol_group[i]), "-", r$ecol_group[i])))
  }

  if (compared) {
    cat("\n  '<<' = your group disagrees with the lookup's ecological group.\n")
    cat("  Groups are never changed automatically -- see ?standardize_dic.\n")
  } else {
    cat("\n  ecol_group is the lookup's ecological group, shown for reference;\n")
    cat("  blank where the accepted name is only a candidate or absent.\n")
    cat("  Groups are not compared -- an ecological group is a local 'sum by'\n")
    cat("  choice. Pass group_map = to compare anyway.\n")
  }
  cat("  This object is still a pollen_dictionary; attr(x, \"report\") is the table.\n")
  invisible(x)
}
