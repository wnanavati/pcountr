# write_pangaea.R — export a site as a PANGAEA-ready tabular data file.
#
# PANGAEA (https://www.pangaea.de) wants TAB-delimited UTF-8 with the event
# label first, the "3rd geocode" (depth) next, then parameters in columns, and
# column headers carrying the full parameter name with its unit in square
# brackets. Tables of different structure must be submitted as separate files,
# so one call writes one table and `what` chooses which.
#
# Note on scope: PANGAEA's own author guide asks submitters to prefer a
# community repository where one exists, which for pollen is Neotoma. This
# export is aimed at the multi-proxy and marine cases where PANGAEA is the
# natural home, not at displacing write_tlx().

#' Export a site to a PANGAEA-ready data table
#'
#' Writes one TAB-delimited UTF-8 table in the layout PANGAEA expects: the
#' event label, depth as the third geocode, age, then one column per taxon
#' with its unit in square brackets.
#'
#' @section Choosing a table:
#' PANGAEA requires tables of differing structure to be submitted as separate
#' files, so each call writes one table. `what` selects it:
#' \describe{
#'   \item{`"counts"`}{Raw weighted counts, `[#]`.}
#'   \item{`"percent"`}{Percentages of the analyst-defined sum, `[%]`.}
#'   \item{`"concentration"`}{Concentrations, `[#/cm**3]` or `[#/g]`.}
#'   \item{`"accumulation"`}{Accumulation rates, `[#/cm**2/a]`.}
#' }
#'
#' @section Units and conversions:
#' Depth is converted from centimetres to metres, PANGAEA's convention for
#' `Depth, sediment/rock`. Ages are written as years before present on the
#' 1950 CE datum and labelled `[a BP]`. Nothing else is rescaled.
#'
#' @section An editable draft, not a finished submission:
#' Event, position, elevation and date are written as columns whether or not
#' the site carries them, so blanks can be filled in the file itself. This
#' mirrors [write_tlx()], whose output is completed in Tilia before a steward
#' sees it. Anything still unset is listed after writing.
#'
#' Depth is the exception. It is PANGAEA's third geocode and cannot be left
#' blank: samples without a `depth_top` are dropped by [site_matrix()], so a
#' site with none would produce a table with no rows. `write_pangaea()` stops
#' in that case rather than writing an empty file.
#'
#' @section What this does not do:
#' It does not map taxon names onto PANGAEA's controlled parameter
#' vocabulary; names are written as they appear in the dictionary, and a
#' PANGAEA data editor harmonizes them during curation. Campaign and
#' device/method are not part of the data table — they are entered through
#' PANGAEA's submission form.
#'
#' @param site A `pollen_site` with samples loaded. Georeferencing from
#'   [pollen_site()] is used when present and left blank when not.
#' @param file Output path. `.txt` is appended when absent.
#' @param what Which table to write. One of `"counts"` (default),
#'   `"percent"`, `"concentration"`, `"accumulation"`.
#' @param taxon_label Dictionary field for column names: `"name"` (default)
#'   or `"alias"`. PANGAEA expects full names, not codes.
#' @param min_present Minimum number of samples a taxon must appear in to be
#'   included. Default `0` keeps all taxa.
#' @param event_label Event label for the first column. Defaults to the
#'   site's `event_label`, then its `name`.
#' @param digits Decimal places for the parameter columns. `NULL` (default)
#'   writes full precision.
#' @param quiet If `TRUE`, suppress the site-metadata summary.
#' @return `file`, invisibly.
#' @seealso [write_tlx()] for Neotoma, [site_matrix()] for the underlying
#'   matrices.
#' @export
write_pangaea <- function(site,
                          file,
                          what        = c("counts", "percent",
                                          "concentration", "accumulation"),
                          taxon_label = c("name", "alias"),
                          min_present = 0,
                          event_label = NULL,
                          digits      = NULL,
                          quiet       = FALSE) {
  stopifnot(inherits(site, "pollen_site"))
  what        <- match.arg(what)
  taxon_label <- match.arg(taxon_label)

  if (!length(site$samples))
    stop("`site` has no samples loaded. Run read_site() first.", call. = FALSE)

  # Georeferencing is written as columns whether or not it is set, so an
  # analyst can fill it in the file itself -- the same way a .tlx is finished
  # in Tilia before it reaches a steward. Unset fields are left empty and
  # listed after writing.
  lat <- site$latitude  %||% NA_real_
  lon <- site$longitude %||% NA_real_

  # Depth is PANGAEA's third geocode, so unlike the site-level fields above it
  # cannot be left blank: site_matrix() drops depth-less samples and the table
  # would have no rows. Catch it here so the message names PANGAEA's
  # requirement rather than surfacing site_matrix()'s error for a function the
  # user did not call.
  if (!any(vapply(site$samples, function(s) {
        v <- s$meta$depth_top
        !is.null(v) && length(v) == 1L && !is.na(v)
      }, logical(1)))) {
    stop("PANGAEA requires depth as the third geocode, and no sample has a ",
         "`depth_top`.\n  Assign depths with set_metadata(), or pass a ",
         "metadata sheet to read_site(metadata = ).", call. = FALSE)
  }

  if (!grepl("\\.(txt|tab|tsv)$", file, ignore.case = TRUE))
    file <- paste0(file, ".txt")

  mat <- site_matrix(site, taxon_label = taxon_label, min_present = min_present)

  tbl <- switch(what,
                counts        = mat$TaxaCount,
                percent       = mat$TaxaPerc,
                concentration = mat$TaxaConc,
                accumulation  = mat$TaxaAccRate)
  if (is.null(tbl) || !length(tbl))
    stop("No ", what, " values are available for this site.", call. = FALSE)

  unit <- switch(what,
                 counts        = "#",
                 percent       = "%",
                 concentration = .pangaea_conc_unit(site),
                 accumulation  = "#/cm**2/a")

  ev <- event_label %||% site$event_label %||% NA_character_
  if (is.na(ev)) ev <- site$name

  # --- assemble: event, position, 3rd geocode, age, then parameters --------
  # Columns are kept even when empty: a blank column is a prompt to fill it
  # in, whereas a missing one is easy to overlook before submission.
  # Event and position are written per row, taken from each sample. A folder
  # may hold one core (every row identical) or surface samples from many
  # places (every row different); PANGAEA's Event column exists precisely so
  # one dataset can span several events, so both export correctly.
  keys <- rownames(tbl)
  # A sample's own value wins; the site fills gaps, matching write_site().
  # Without the fallback, read_site(latitude = ) would set the site but leave
  # every exported row blank.
  pull <- function(field, default) {
    fallback <- site[[field]]
    if (is.null(fallback) || (length(fallback) == 1L && is.na(fallback)))
      fallback <- default
    vapply(keys, function(k) {
      v <- site$samples[[k]]$meta[[field]]
      if (is.null(v) || (length(v) == 1L && is.na(v))) fallback else v
    }, default, USE.NAMES = FALSE)
  }
  ev_col <- pull("event_label", NA_character_)
  ev_col[is.na(ev_col)] <- ev          # fall back to the site-level label

  out <- data.frame(
    `Event`                    = ev_col,
    `Latitude`                 = pull("latitude",  NA_real_),
    `Longitude`                = pull("longitude", NA_real_),
    `Elevation [m]`            = pull("elevation", NA_real_),
    `Date/Time`                = pull("collection_date", NA_character_),
    `Depth, sediment/rock [m]` = round(mat$DepTop / 100, 4),
    `Depth bot [m]`            = round(mat$DepBot / 100, 4),
    `Age [a BP]`               = mat$AgeTop,
    `Sample label`             = keys,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  vals <- as.data.frame(tbl, stringsAsFactors = FALSE)
  if (!is.null(digits)) vals[] <- lapply(vals, round, digits = digits)
  names(vals) <- paste0(colnames(tbl), " [", unit, "]")

  out <- cbind(out, vals)

  utils::write.table(out, file, sep = "\t", quote = FALSE, row.names = FALSE,
                     na = "", fileEncoding = "UTF-8")

  if (!quiet) .pangaea_report(site, file, what, nrow(out), ncol(vals))
  invisible(file)
}

# Concentration unit follows the sample's own units flag, which read_cnt() and
# the counting app record. PANGAEA writes exponents as ** in column headers.
.pangaea_conc_unit <- function(site) {
  u <- unique(vapply(site$samples,
                     function(s) s$meta$units %||% NA_character_,
                     NA_character_))
  u <- u[!is.na(u)]
  if (length(u) == 1L && identical(u, "g")) "#/g" else "#/cm**3"
}

# The file is a draft to be finished before submission, as a .tlx is finished
# in Tilia. Report coverage per sample rather than per site: with provenance
# held on each sample, site$latitude is NA whenever samples legitimately
# differ, so checking the site would tell a correctly filled transect that
# its latitude was missing.
.pangaea_report <- function(site, file, what, n_rows, n_par) {
  message("Wrote ", n_rows, " samples x ", n_par, " parameters (", what,
          ") to:\n  ", normalizePath(file, winslash = "/", mustWork = FALSE))

  # Count a field blank only if neither the sample nor the site supplies it,
  # matching what pull() actually wrote -- otherwise a site-level value would
  # populate the column while the report called it missing.
  fields <- c("latitude", "longitude", "elevation", "collection_date", "device")
  gaps <- vapply(fields, function(f) {
    sv <- site[[f]]
    if (!is.null(sv) && !(length(sv) == 1L && is.na(sv))) return(0L)
    sum(vapply(site$samples, function(s) {
      v <- s$meta[[f]]
      is.null(v) || (length(v) == 1L && is.na(v))
    }, logical(1)))
  }, integer(1))

  n <- length(site$samples)
  missing <- gaps[gaps > 0L]
  if (length(missing)) {
    message("\nIncomplete before submission:")
    for (f in names(missing))
      message(sprintf("  %-16s %d of %d samples blank", f, missing[[f]], n))
    message("Fill them in the file, or set them per sample with ",
            "set_metadata() / apply_metadata().")
  }
  message("\nPANGAEA also asks for a device or method and a campaign label ",
          "on its\nsubmission form; neither is part of the data table.")
}
