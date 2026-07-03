#' Export a pollen site to Tilia XML format (.tlx)
#'
#' Writes a four-page Tilia XML spreadsheet file from a loaded `pollen_site`.
#' Pages 0--3 (Data, Percents, Concentrations, Accumulation) all share the
#' same nine sample-metadata header rows (rows 3--11) in every column, matching
#' the structure Tilia itself produces. Pages 0 and 1 are suitable for Neotoma
#' upload after populating site and collection-unit metadata in Tilia.
#'
#' @section Row layout (all pages):
#' \describe{
#'   \item{Row 1}{Depth top -- used by Tilia as the column display header.}
#'   \item{Row 2}{Sample name label (text).}
#'   \item{Row 3 -- \code{#Chron1}}{Age top (cal yr BP).}
#'   \item{Row 4 -- \code{#Chron2}}{Age bottom (cal yr BP).}
#'   \item{Row 5 -- \code{#Depth1}}{Depth top (cm).}
#'   \item{Row 6 -- \code{#Depth2}}{Depth bottom (cm).}
#'   \item{Row 7 -- \code{Lyc.spik:counted:number}}{Lycopodium spike counted.}
#'   \item{Row 8 -- \code{samp.quant:volume:ml} or \code{:weight:g}}{Sample quantity.}
#'   \item{Row 9 -- \code{Lyc.tab:quantity added:number}}{Tablets added.}
#'   \item{Row 10 -- \code{Lyc.tab:concentration:number/tablet}}{Tablet density.}
#'   \item{Row 11 -- \code{dep.time}}{Deposition time (yr/cm), computed from the
#'     sample age and depth intervals.}
#'   \item{Row 12+}{Taxa. Data/Percents use all observed codes; Concentrations
#'     and Accumulation use non-special codes only (matching [site_matrix()]).}
#' }
#'
#' @section Percentage denominator:
#' Percentages are computed over taxa whose dictionary group code is in
#' `groups`. The denominator uses weighted grain counts for each sample.
#'
#' @param site A `pollen_site` with samples loaded (from [read_site()]).
#' @param file Output file path (e.g. `"MySite_2026.tlx"`). The directory
#'   must already exist.
#' @param groups Character vector of dictionary group codes forming the
#'   percentage denominator. Defaults to `site$pollen_sum`.
#' @return `file` invisibly.
#' @seealso [site_matrix()], [read_site()]
#' @export
write_tlx <- function(site, file, groups = NULL) {

  stopifnot(inherits(site, "pollen_site"))
  if (!nzchar(file)) stop("`file` must be a non-empty path string.")

  groups <- .resolve_groups(groups, site)
  dic    <- site$dictionary
  samps  <- site$samples

  if (!length(samps))
    stop("`site` has no samples. Run read_site() first.")

  # ---------------------------------------------------------------------------
  # Order samples: depth_top > trailing number in sample_name > age_top
  # ---------------------------------------------------------------------------
  order_key <- vapply(samps, function(s) {
    dt <- s$meta$depth_top
    if (!is.null(dt) && length(dt) == 1L && !is.na(dt)) return(as.numeric(dt))
    sn <- s$meta$sample_name
    if (!is.null(sn) && length(sn) == 1L && !is.na(sn) && nzchar(sn)) {
      num <- suppressWarnings(as.numeric(gsub(".*?(\\d+)\\s*$", "\\1", sn)))
      if (!is.na(num)) return(num)
    }
    at <- s$meta$age_top
    if (!is.null(at) && length(at) == 1L && !is.na(at)) return(as.numeric(at))
    NA_real_
  }, NA_real_)

  if (any(is.na(order_key)))
    stop("Cannot determine stratigraphic position for sample(s): ",
         paste(names(samps)[is.na(order_key)], collapse = ", "),
         ".\nProvide depth_top, sample_name, or age_top.")

  samps  <- samps[order(order_key)]
  n_samp <- length(samps)

  # ---------------------------------------------------------------------------
  # Taxa codes
  # all_codes : every observed code in dictionary order (Data / Percents)
  # conc_codes: non-special subset (Concentrations / Accumulation)
  # ---------------------------------------------------------------------------
  obs_codes <- unique(unlist(lapply(samps, function(s) {
    s$grains$code[s$grains$weight > 0]
  })))
  all_codes <- dic$code[dic$code %in% obs_codes]
  if (!length(all_codes))
    stop("No taxa with positive counts found in the site.")

  is_spc <- dic$is_special[match(all_codes, dic$code)]
  is_spc[is.na(is_spc)] <- FALSE
  conc_codes <- all_codes[!is_spc & !grepl("^[#.]", all_codes)]

  # ---------------------------------------------------------------------------
  # Per-sample metadata
  # ---------------------------------------------------------------------------
  .gmeta <- function(s, field) {
    v <- s$meta[[field]]
    if (is.null(v) || length(v) != 1L || is.na(v)) NA_real_ else as.numeric(v)
  }
  .gfield <- function(s, field) {
    v <- s[[field]]
    if (is.null(v) || length(v) != 1L || is.na(v)) NA_real_ else as.numeric(v)
  }

  depth_top <- vapply(samps, .gmeta,  NA_real_, "depth_top")
  depth_bot <- vapply(samps, .gmeta,  NA_real_, "depth_bottom")
  age_top   <- vapply(samps, .gmeta,  NA_real_, "age_top")
  age_bot   <- vapply(samps, .gmeta,  NA_real_, "age_bottom")
  samp_qty  <- vapply(samps, .gmeta,  NA_real_, "sample_quantity")
  spike_n   <- vapply(samps, .gfield, NA_real_, "spike_n")
  spike_tab <- vapply(samps, .gmeta,  NA_real_, "spike_tablets")
  spike_den <- vapply(samps, .gmeta,  NA_real_, "spike_density")
  samp_name <- vapply(samps, function(s) {
    v <- s$meta$sample_name
    if (is.null(v) || length(v) != 1L || is.na(v) || !nzchar(v)) NA_character_
    else as.character(v)
  }, NA_character_)

  # Deposition time: yr / cm
  dep_time  <- (age_bot - age_top) / (depth_bot - depth_top)
  dep_time[!is.finite(dep_time) | dep_time <= 0] <- NA_real_

  # Dominant sample-quantity unit (ml vs g)
  samp_units <- vapply(samps, function(s) {
    v <- s$meta$units
    if (is.null(v) || !nzchar(trimws(v))) "" else trimws(v)
  }, "")
  dom_unit <- if (sum(samp_units == "g") > sum(samp_units != "g")) "g" else "ml"
  sq_code  <- paste0("samp.quant:", if (dom_unit == "g") "weight:g" else "volume:ml")

  # ---------------------------------------------------------------------------
  # Metadata row definitions (rows 3-11, shared by all four pages)
  # ---------------------------------------------------------------------------
  META_START <- 3L
  META_CODES <- c("#Chron1",
                  "#Chron2",
                  "#Depth1",
                  "#Depth2",
                  "Lyc.spik:counted:number",
                  sq_code,
                  "Lyc.tab:quantity added:number",
                  "Lyc.tab:concentration:number/tablet",
                  "dep.time")
  META_NAMES <- c("Age top (cal yr BP)",
                  "Age bottom (cal yr BP)",
                  "Depth top (cm)",
                  "Depth bottom (cm)",
                  "Lycopodium spike",
                  "Sample quantity",
                  "Lycopodium tablets",
                  "Lycopodium tablets",
                  "Deposition time")
  META_UNITS <- c("", "", "", "",
                  "number",
                  dom_unit,
                  "number",
                  "number/tablet",
                  "")
  # #Chron1/#Chron2: no group; #Depth1/#Depth2: no group (user preference);
  # spike/sample/tablets/tablet-conc: CONC; dep.time: no group
  META_GRPS  <- c("", "", "", "",
                  "CONC", "CONC", "CONC", "CONC", "")
  # Per-sample values for each metadata row (same on all pages)
  META_VALS  <- list(age_top, age_bot, depth_top, depth_bot,
                     spike_n, samp_qty, spike_tab, spike_den, dep_time)

  n_meta    <- length(META_CODES)    # 9
  TAXA_START <- META_START + n_meta  # 12

  # ---------------------------------------------------------------------------
  # Count and percentage matrices (all_codes)
  # ---------------------------------------------------------------------------
  count_mat <- matrix(0, nrow = n_samp, ncol = length(all_codes),
                      dimnames = list(names(samps), all_codes))
  for (i in seq_len(n_samp)) {
    g <- samps[[i]]$grains
    for (code in all_codes) {
      w <- g$weight[g$code == code]
      if (length(w)) count_mat[i, code] <- sum(w)
    }
  }

  pct_mat <- matrix(NA_real_, nrow = n_samp, ncol = length(all_codes),
                    dimnames = list(names(samps), all_codes))
  for (i in seq_len(n_samp)) {
    g     <- samps[[i]]$grains
    grp   <- dic$group[match(g$code, dic$code)]
    denom <- sum(g$weight[!is.na(grp) & grp %in% groups], na.rm = TRUE)
    if (!is.na(denom) && denom > 0)
      for (code in all_codes) {
        w <- g$weight[g$code == code]
        pct_mat[i, code] <- if (length(w)) sum(w) / denom * 100 else 0
      }
  }

  # ---------------------------------------------------------------------------
  # Concentration and accumulation matrices (conc_codes only)
  # ---------------------------------------------------------------------------
  cf <- (spike_tab * spike_den) / (spike_n * samp_qty)
  cf[!is.finite(cf) | cf <= 0] <- NA_real_

  conc_mat <- matrix(NA_real_, nrow = n_samp, ncol = length(conc_codes),
                     dimnames = list(names(samps), conc_codes))
  for (i in seq_len(n_samp))
    conc_mat[i, ] <-
      if (!is.na(cf[i])) count_mat[i, conc_codes] * cf[i] else NA_real_

  accrate_mat <- matrix(NA_real_, nrow = n_samp, ncol = length(conc_codes),
                        dimnames = list(names(samps), conc_codes))
  for (i in seq_len(n_samp))
    accrate_mat[i, ] <-
      if (!is.na(dep_time[i])) conc_mat[i, ] / dep_time[i] else NA_real_

  # ---------------------------------------------------------------------------
  # XML helpers
  # ---------------------------------------------------------------------------
  ind <- function(n) paste(rep("  ", n), collapse = "")

  fmt_val <- function(x) {
    if (is.null(x) || (length(x) == 1L && is.na(x))) return(NULL)
    if (isTRUE(x == round(x))) as.character(as.integer(x)) else as.character(x)
  }

  xml_esc <- function(s) {
    s <- gsub("&",  "&amp;",  s, fixed = TRUE)
    s <- gsub("<",  "&lt;",   s, fixed = TRUE)
    s <- gsub(">",  "&gt;",   s, fixed = TRUE)
    s <- gsub("\"", "&quot;", s, fixed = TRUE)
    s
  }

  ctext <- function(row, txt, d = 3) {
    if (is.null(txt) || is.na(txt) || !nzchar(as.character(txt))) return("")
    paste0(ind(d), "<cell row=\"", row, "\">\n",
           ind(d+1), "<text>", xml_esc(as.character(txt)), "</text>\n",
           ind(d), "</cell>")
  }

  cval <- function(row, val, fmt = NULL, d = 3) {
    v <- fmt_val(val)
    if (is.null(v)) return("")
    fa <- if (!is.null(fmt)) paste0(" format=\"", fmt, "\"") else ""
    paste0(ind(d), "<cell row=\"", row, "\"", fa, ">\n",
           ind(d+1), "<value>", v, "</value>\n",
           ind(d), "</cell>")
  }

  # ---------------------------------------------------------------------------
  # Sum rows
  # ---------------------------------------------------------------------------
  sum_rows <- list(
    list(code = "SUM(A)",     name = "Trees and shrubs",        grp = "Terr"),
    list(code = "SUM(B)",     name = "Upland herbs",            grp = "Terr"),
    list(code = "SUM(F)",     name = "Vascular Cryptogams",     grp = "All"),
    list(code = "SUM(Q)",     name = "Aquatic vascular plants", grp = "All"),
    list(code = "SUM(X)",     name = "Unknown",                 grp = "All"),
    list(code = "SSUM(Terr)", name = "Terrestrial",             grp = "A;B"),
    list(code = "SSUM(All)",  name = "All pollen and spores",   grp = "A;B;F;Q;X")
  )

  grp_sum_vals <- function(mat_row, codes) {
    grps <- dic$group[match(codes, dic$code)]
    grps[is.na(grps)] <- ""
    A <- sum(mat_row[grps == "A"], na.rm = TRUE)
    B <- sum(mat_row[grps == "B"], na.rm = TRUE)
    F <- sum(mat_row[grps == "F"], na.rm = TRUE)
    Q <- sum(mat_row[grps == "Q"], na.rm = TRUE)
    X <- sum(mat_row[grps == "X"], na.rm = TRUE)
    c(A, B, F, Q, X, A + B, A + B + F + Q + X)
  }

  # ---------------------------------------------------------------------------
  # build_sheet: unified builder for all four pages
  #
  # page      : 0-3
  # name      : "Data" | "Percents" | "Concentrations" | "Accumulation"
  # mat       : matrix of taxon values (rows = samples, cols = codes)
  # codes     : column names of mat (all_codes or conc_codes)
  # taxon_fmt : format string for taxon cells (NULL = integer-like)
  # taxon_unit: unit string written to Col 4 for every taxon row
  # ---------------------------------------------------------------------------
  build_sheet <- function(page, name, mat, codes,
                          taxon_fmt = NULL, taxon_unit = "") {
    n_taxa  <- length(codes)
    SUM_START <- TAXA_START + n_taxa

    ln <- character(0)
    ln <- c(ln, paste0(ind(1), "<SpreadSheet page=\"", page,
                       "\" name=\"", xml_esc(name), "\">"))

    # --- Col 1: codes (metadata rows, taxon rows, sum rows) ----------------
    ln <- c(ln, paste0(ind(2), "<Col ID=\"1\" Width=\"64\">"))
    for (mi in seq_along(META_CODES))
      ln <- c(ln, ctext(META_START + mi - 1L, META_CODES[mi]))
    for (ti in seq_along(codes))
      ln <- c(ln, ctext(TAXA_START + ti - 1L, codes[ti]))
    for (si in seq_along(sum_rows))
      ln <- c(ln, ctext(SUM_START + si - 1L, sum_rows[[si]]$code))
    ln <- c(ln, paste0(ind(2), "</Col>"))

    # --- Col 2: names -------------------------------------------------------
    ln <- c(ln, paste0(ind(2), "<Col ID=\"2\" Width=\"180\">"))
    for (mi in seq_along(META_NAMES))
      ln <- c(ln, ctext(META_START + mi - 1L, META_NAMES[mi]))
    for (ti in seq_along(codes)) {
      nm <- dic$name[match(codes[ti], dic$code)]
      ln <- c(ln, ctext(TAXA_START + ti - 1L,
                        if (is.na(nm)) codes[ti] else nm))
    }
    for (si in seq_along(sum_rows))
      ln <- c(ln, ctext(SUM_START + si - 1L, sum_rows[[si]]$name))
    ln <- c(ln, paste0(ind(2), "</Col>"))

    # --- Col 4: units -------------------------------------------------------
    ln <- c(ln, paste0(ind(2), "<Col ID=\"4\" Width=\"96\">"))
    for (mi in seq_along(META_UNITS))
      if (nzchar(META_UNITS[mi]))
        ln <- c(ln, ctext(META_START + mi - 1L, META_UNITS[mi]))
    if (nzchar(taxon_unit))
      for (ti in seq_along(codes))
        ln <- c(ln, ctext(TAXA_START + ti - 1L, taxon_unit))
    for (si in seq_along(sum_rows))
      ln <- c(ln, ctext(SUM_START + si - 1L, "percent"))
    ln <- c(ln, paste0(ind(2), "</Col>"))

    # --- Col 7: groups ------------------------------------------------------
    ln <- c(ln, paste0(ind(2), "<Col ID=\"7\" Width=\"64\">"))
    for (mi in seq_along(META_GRPS))
      if (nzchar(META_GRPS[mi]))
        ln <- c(ln, ctext(META_START + mi - 1L, META_GRPS[mi]))
    for (ti in seq_along(codes)) {
      g <- dic$group[match(codes[ti], dic$code)]
      ln <- c(ln, ctext(TAXA_START + ti - 1L,
                        if (is.na(g) || !nzchar(g)) "LABO" else g))
    }
    for (si in seq_along(sum_rows))
      ln <- c(ln, ctext(SUM_START + si - 1L, sum_rows[[si]]$grp))
    ln <- c(ln, paste0(ind(2), "</Col>"))

    # --- Sample columns (Col 8+) -------------------------------------------
    for (ci in seq_len(n_samp)) {
      ln <- c(ln, paste0(ind(2), "<Col ID=\"", 7L + ci, "\" Width=\"64\">"))

      # Row 1: depth top (column display header)
      ln <- c(ln, cval(1L, depth_top[ci]))

      # Row 2: sample name label
      if (!is.na(samp_name[ci]) && nzchar(samp_name[ci]))
        ln <- c(ln, ctext(2L, samp_name[ci]))

      # Rows 3-11: metadata (same values on every page)
      for (mi in seq_along(META_VALS))
        ln <- c(ln, cval(META_START + mi - 1L, META_VALS[[mi]][ci]))

      # Rows 12+: taxon values
      for (ti in seq_along(codes))
        ln <- c(ln, cval(TAXA_START + ti - 1L,
                         mat[ci, codes[ti]], fmt = taxon_fmt))

      # Sum rows
      gs <- grp_sum_vals(mat[ci, ], codes)
      for (si in seq_along(sum_rows))
        ln <- c(ln, cval(SUM_START + si - 1L, gs[si], fmt = taxon_fmt))

      ln <- c(ln, paste0(ind(2), "</Col>"))
    }

    ln <- c(ln, paste0(ind(1), "</SpreadSheet>"))
    ln[nzchar(ln)]
  }

  # ---------------------------------------------------------------------------
  # Assemble and write
  # ---------------------------------------------------------------------------
  now <- format(Sys.time(), "%d-%b-%Y %I:%M:%S %p")

  header <- c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    paste0("<!--written ", now, "-->"),
    "<TiliaFile>",
    "<Version>",
    "  <Application>Tilia</Application>",
    "  <MajorVersion>3</MajorVersion>",
    "  <MinorVersion>0</MinorVersion>",
    "  <Release>3</Release>",
    "</Version>",
    "<SpreadSheetBook>",
    paste0(ind(1), "<SpreadSheetOptions>"),
    paste0(ind(2), "<HeaderRow>0</HeaderRow>"),
    paste0(ind(2), "<FontName>Arial</FontName>"),
    paste0(ind(2), "<FontSize>9</FontSize>"),
    paste0(ind(2), "<DefaultColWidth>64</DefaultColWidth>"),
    paste0(ind(2), "<DefaultRowHeight>18</DefaultRowHeight>"),
    paste0(ind(2), "<PercentDecimalPlaces>1</PercentDecimalPlaces>"),
    paste0(ind(2), "<CheckDupCodes>True</CheckDupCodes>"),
    paste0(ind(2), "<CaseSensitiveCodes>False</CaseSensitiveCodes>"),
    paste0(ind(2), "<CodesVisible>True</CodesVisible>"),
    paste0(ind(2), "<ElementsVisible>True</ElementsVisible>"),
    paste0(ind(2), "<UnitsVisible>True</UnitsVisible>"),
    paste0(ind(2), "<ContextsVisible>False</ContextsVisible>"),
    paste0(ind(2), "<TaphonomyVisible>False</TaphonomyVisible>"),
    paste0(ind(2), "<GroupsVisible>True</GroupsVisible>"),
    paste0(ind(1), "</SpreadSheetOptions>")
  )

  footer <- c(
    "</SpreadSheetBook>",
    "<Site></Site>",
    "<CollectionUnit></CollectionUnit>",
    "<Datasets>",
    paste0(ind(1), "<Dataset>"),
    paste0(ind(2), "<DatasetType>pollen</DatasetType>"),
    paste0(ind(2), "<IsSSamp>False</IsSSamp>"),
    paste0(ind(2), "<WhitmoreData>False</WhitmoreData>"),
    paste0(ind(2), "<IsAggregate>False</IsAggregate>"),
    paste0(ind(1), "</Dataset>"),
    "</Datasets>",
    "</TiliaFile>"
  )

  all_lines <- c(
    header,
    build_sheet(0L, "Data",           count_mat,   all_codes,   NULL,  ""),
    build_sheet(1L, "Percents",        pct_mat,     all_codes,   "0.",  "percent"),
    build_sheet(2L, "Concentrations",  conc_mat,    conc_codes,  "0.",  ""),
    build_sheet(3L, "Accumulation",    accrate_mat, conc_codes,  "0.",  ""),
    footer
  )

  # UTF-8 BOM to match Tilia's own output
  all_lines[1] <- paste0("\xEF\xBB\xBF", all_lines[1])
  writeLines(all_lines, file, useBytes = FALSE)
  invisible(file)
}
