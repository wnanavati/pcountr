# traverses.R — summarize a site at traverse resolution.
#
# A count is normally reduced to one row per sample, which discards where on
# the slide each identification was made. pcountr keeps the counting sequence
# and its traverse labels, so that spatial structure survives: this function
# exposes it as a tidy table.
#
# Marker counts come from the event stream rather than the grains data frame,
# because spikes are not grains and are held only as events.

#' Summarize a site at traverse resolution
#'
#' Returns one row per sample and traverse, with identification and marker
#' counts, richness, and the traverse's position on the slide where the label
#' records one.
#'
#' @section Why this exists:
#' Reducing a count to per-sample totals discards the position of every
#' identification. Because pcountr preserves the counting sequence and the
#' traverse labels interleaved with it, counts remain addressable by location
#' on the slide — which makes it possible to ask whether assemblage
#' composition varies across a coverslip, and whether spreading a given
#' counting effort over more of the slide changes the answer.
#'
#' @section Position parsing:
#' Traverse labels are free text. Where a label begins with a number, that
#' number is taken as `position`, and a trailing compass letter as
#' `direction` — so `"118.0N"` gives `118.0` and `"N"`. Analysts who record
#' stage coordinates in millimetres therefore get a usable distance axis;
#' labels that are not numeric yield `NA` and the row is still returned.
#' `dist_start` is the distance from the sample's first traverse, which is
#' the more portable measure when the stage datum differs between slides.
#'
#' @param site A `pollen_site` with samples loaded.
#' @param taxa If `TRUE`, return one row per sample, traverse and taxon
#'   instead of the traverse summary. Useful for composition-against-position
#'   analyses.
#' @return A data frame. With `taxa = FALSE` (default), one row per sample and
#'   traverse:
#'   \describe{
#'     \item{`sample`}{Sample key within the site.}
#'     \item{`traverse`}{Traverse label, verbatim.}
#'     \item{`ordinal`}{Counting order of this traverse within the sample.}
#'     \item{`n_traverses`}{Traverses in that sample, for scaling `ordinal`.}
#'     \item{`position`,`direction`}{Parsed from the label; `NA` if absent.}
#'     \item{`dist_start`}{Absolute distance in `position` units from the
#'       sample's first traverse.}
#'     \item{`n_ident`}{Identifications counted toward sums.}
#'     \item{`n_marker`}{Tracer-spike markers counted.}
#'     \item{`n_special`}{Identifications excluded from sums (`#` codes).}
#'     \item{`richness`}{Distinct non-special codes in the traverse.}
#'     \item{`sum_weight`}{Summed entry weights, so half-weight fragments
#'       contribute 0.5.}
#'   }
#'   With `taxa = TRUE`: `sample`, `traverse`, `ordinal`, `position`, `code`,
#'   `n`, `weight`.
#' @seealso [extract_remarks()] for the same idea applied to inline remarks.
#' @export
extract_traverses <- function(site, taxa = FALSE) {
  if (!inherits(site, "pollen_site"))
    stop("`site` must be a pollen_site object.", call. = FALSE)
  if (!length(site$samples))
    stop("`site` has no samples loaded. Run read_site() first.", call. = FALSE)

  special <- .special_codes(site)
  out <- lapply(names(site$samples), function(k)
    .traverses_one(site$samples[[k]], k, special, taxa))
  out <- out[vapply(out, nrow, 0L) > 0L]

  if (!length(out)) {
    cols <- if (taxa)
      c("sample", "traverse", "ordinal", "position", "code", "n", "weight")
    else
      c("sample", "traverse", "ordinal", "n_traverses", "position",
        "direction", "dist_start", "n_ident", "n_marker", "n_special",
        "richness", "sum_weight")
    return(stats::setNames(
      data.frame(matrix(nrow = 0, ncol = length(cols))), cols))
  }
  do.call(rbind, out)
}

# Codes the dictionary marks as excluded from sums. Falls back to the prefix
# rule when no dictionary is attached, matching read_dic_csv()'s inference.
.special_codes <- function(site) {
  d <- site$dictionary
  if (is.null(d) || !nrow(d)) return(character(0))
  d$code[isTRUE(d$is_special) | d$is_special %in% TRUE |
           grepl("^[#.]", d$code)]
}

.traverses_one <- function(cnt, key, special, taxa) {
  evs <- cnt$events
  if (is.null(evs) || !length(evs)) return(data.frame())

  type <- vapply(evs, function(e) e$type %||% "", "")
  trav <- vapply(evs, function(e) {
    v <- e$traverse
    if (is.null(v) || (length(v) == 1L && is.na(v))) NA_character_
    else as.character(v)
  }, NA_character_)

  keep <- type %in% c("grain", "spike") & !is.na(trav)
  if (!any(keep)) return(data.frame())

  code <- vapply(evs, function(e) as.character(e$code %||% NA_character_),
                 NA_character_)
  wt   <- vapply(evs, function(e) as.numeric(e$weight %||% 1), 0)

  type <- type[keep]; trav <- trav[keep]
  code <- code[keep]; wt <- wt[keep]

  # Counting order, not alphabetical: traverses are spatial positions visited
  # in sequence, so their order is data.
  labs <- unique(trav)
  pos  <- .parse_traverse_pos(labs)

  if (taxa) {
    g <- type == "grain"
    if (!any(g)) return(data.frame())
    agg <- stats::aggregate(
      list(n = rep(1L, sum(g)), weight = wt[g]),
      by = list(traverse = trav[g], code = code[g]), FUN = sum)
    idx <- match(agg$traverse, labs)
    return(data.frame(
      sample   = key,
      traverse = agg$traverse,
      ordinal  = idx,
      position = pos$position[idx],
      code     = agg$code,
      n        = agg$n,
      weight   = agg$weight,
      row.names = NULL, stringsAsFactors = FALSE
    ))
  }

  per <- lapply(seq_along(labs), function(i) {
    sel <- trav == labs[i]
    cd  <- code[sel]; tp <- type[sel]; w <- wt[sel]
    is_sp  <- tp == "spike"
    is_spc <- tp == "grain" & cd %in% special
    is_id  <- tp == "grain" & !is_spc
    data.frame(
      n_ident    = sum(is_id),
      n_marker   = sum(is_sp),
      n_special  = sum(is_spc),
      richness   = length(unique(cd[is_id])),
      sum_weight = sum(w[is_id]),
      stringsAsFactors = FALSE
    )
  })

  data.frame(
    sample      = key,
    traverse    = labs,
    ordinal     = seq_along(labs),
    n_traverses = length(labs),
    position    = pos$position,
    direction   = pos$direction,
    dist_start  = abs(pos$position - pos$position[1]),
    do.call(rbind, per),
    row.names = NULL, stringsAsFactors = FALSE
  )
}

# "118.0N" -> 118.0 / "N". Labels are free text, so anything that does not
# start with a number simply yields NA rather than being coerced.
.parse_traverse_pos <- function(labs) {
  num <- suppressWarnings(as.numeric(sub("^\\s*(-?[0-9.]+).*$", "\\1", labs)))
  num[!grepl("^\\s*-?[0-9]", labs)] <- NA_real_
  # The compass letter is only meaningful on a numeric label: without the
  # leading-number requirement, a label like "edge" parses as East.
  has_dir <- grepl("^\\s*-?[0-9.]+\\s*[NSEWnsew]\\s*$", labs)
  dir <- rep(NA_character_, length(labs))
  dir[has_dir] <- toupper(sub("^.*?([NSEWnsew])\\s*$", "\\1", labs[has_dir]))
  list(position = num, direction = dir)
}
