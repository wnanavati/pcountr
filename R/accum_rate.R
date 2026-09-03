#' Compute accumulation rates (PAR / influx) for a site
#'
#' Calculates concentration, deposition time, and influx for each depth-bearing
#' sample in a loaded site. Both total and per-taxon values are returned.
#'
#' `PAR` is kept as the conventional acronym. It originates in palynology as
#' "pollen accumulation rate", but the calculation itself depends only on a
#' count sum, a spike and a sample quantity, so it applies to any proxy counted
#' the same way.
#'
#' @section Equations:
#' \deqn{\text{deposition time} = \frac{age_{bottom} - age_{top}}{depth_{bottom} - depth_{top}} \quad [\text{yr/cm}]}
#' \deqn{\text{concentration} = \frac{\text{count sum}}{\text{spike counted}} \times \frac{\text{spike tablets} \times \text{spike density}}{\text{sample quantity}} \quad [\text{counts/cm}^3 \text{ or counts/g}]}
#' \deqn{\text{PAR} = \frac{\text{concentration}}{\text{deposition time}} \quad [\text{counts/cm}^2/\text{yr}]}
#'
#' Per-taxon concentrations and influx are computed the same way using each
#' taxon's weighted count in place of the total count sum.
#'
#' @section Required inputs:
#' All of the following must be set (non-NA, positive where applicable) for
#' every depth-bearing sample. If any are missing the function stops and lists
#' every deficiency so they can all be corrected at once:
#' \itemize{
#'   \item `depth_top` and `depth_bottom` (depth_bottom > depth_top)
#'   \item `age_top` and `age_bottom` (age_bottom > age_top; ages increase
#'     downcore)
#'   \item `sample_quantity` > 0
#'   \item `spike_tablets` and `spike_density` > 0
#'   \item `spike_n` > 0 (at least one tracer microsphere counted)
#' }
#' Samples with no `depth_top` are skipped with a message (consistent with
#' [site_matrix()]); all other required fields are errors, not warnings.
#'
#' @param site A `pollen_site` with a `samples` list (from [read_site()]).
#' @return A list with three elements:
#'   \describe{
#'     \item{`data`}{Data frame with one row per sample:
#'       `sample`, `depth_top`, `depth_bottom`, `age_top`, `age_bottom`,
#'       `deposition_time` (yr/cm), `concentration` (counts per sample-unit),
#'       `influx` (counts/cm\eqn{^2}/yr).}
#'     \item{`taxon_concentration`}{Numeric matrix (samples x taxa):
#'       per-taxon concentration for all non-special taxa.}
#'     \item{`taxon_influx`}{Numeric matrix (samples x taxa):
#'       per-taxon PAR (counts/cm\eqn{^2}/yr).}
#'   }
#' @seealso [count_metrics()], [site_matrix()]
#' @export
accum_rate <- function(site) {
  stopifnot(inherits(site, "pollen_site"))

  if (is.null(site$samples) || !length(site$samples))
    stop("`site` has no samples loaded. Run read_site() first.")

  dic <- site$dictionary

  # Samples with depth_top ------------------------------------------------
  has_depth <- .has_depth_top(site$samples)
  if (any(!has_depth))
    message("Skipping ", sum(!has_depth),
            " sample(s) with no depth_top: ",
            paste(names(site$samples)[!has_depth], collapse = ", "))

  depth_samples <- site$samples[has_depth]
  if (!length(depth_samples))
    stop("No samples have depth_top set. Use set_metadata() first.")

  # Validate all required fields -- collect every error before stopping -----
  all_errors <- unlist(lapply(names(depth_samples), function(nm) {
    s <- depth_samples[[nm]]
    .check_par_inputs(nm, s$meta, s$spike_n)
  }))
  if (length(all_errors))
    stop("Missing or invalid inputs for accumulation rate. ",
         "Fix the following before calling accum_rate():\n",
         paste0("  - ", all_errors, collapse = "\n"))

  # Scalar quantities per sample ------------------------------------------
  keys         <- names(depth_samples)
  depth_top    <- vapply(depth_samples, function(s) s$meta$depth_top,    NA_real_)
  depth_bottom <- vapply(depth_samples, function(s) s$meta$depth_bottom, NA_real_)
  age_top      <- vapply(depth_samples, function(s) s$meta$age_top,      NA_real_)
  age_bottom   <- vapply(depth_samples, function(s) s$meta$age_bottom,   NA_real_)

  dep_time <- (age_bottom - age_top) / (depth_bottom - depth_top)   # yr/cm

  # Total concentration via count_metrics() (uses total pollen sum) -------
  conc <- vapply(depth_samples, function(s) {
    count_metrics(s)$concentration
  }, NA_real_)

  total_par <- conc / dep_time   # counts/cm^2/yr

  # Summary data frame -----------------------------------------------------
  data_df <- data.frame(
    sample          = unname(keys),
    depth_top       = unname(depth_top),
    depth_bottom    = unname(depth_bottom),
    age_top         = unname(age_top),
    age_bottom      = unname(age_bottom),
    deposition_time = unname(dep_time),
    concentration   = unname(conc),
    influx          = unname(total_par),
    stringsAsFactors = FALSE,
    row.names        = NULL
  )

  # Per-taxon matrices -----------------------------------------------------
  dic_nonspc <- dic[!dic$is_special, , drop = FALSE]
  all_codes  <- sort(unique(unlist(lapply(depth_samples, function(s) {
    intersect(s$grains$code[!grepl("^[#.]", s$grains$code)], dic_nonspc$code)
  }))))

  n   <- length(depth_samples)
  nc  <- length(all_codes)

  taxon_conc   <- matrix(0, nrow = n, ncol = nc,
                         dimnames = list(keys, all_codes))
  taxon_influx <- matrix(0, nrow = n, ncol = nc,
                         dimnames = list(keys, all_codes))

  for (i in seq_len(n)) {
    s   <- depth_samples[[i]]
    m   <- s$meta
    spk <- (m$spike_tablets * m$spike_density) / (s$spike_n * m$sample_quantity)

    g   <- s$grains
    tx  <- tapply(g$weight[g$code %in% all_codes],
                  g$code[g$code %in% all_codes], sum)
    hits <- intersect(names(tx), all_codes)
    taxon_conc[i, hits]   <- as.numeric(tx[hits]) * spk
    taxon_influx[i, hits] <- taxon_conc[i, hits] / dep_time[i]
  }

  list(
    data                = data_df,
    taxon_concentration = taxon_conc,
    taxon_influx        = taxon_influx
  )
}


# --- internal validation ---------------------------------------------------

# Returns a character vector of error strings (empty = all good).
.check_par_inputs <- function(key, meta, spike_n) {
  errs <- character(0)

  flag <- function(cond, msg)
    if (isTRUE(cond)) errs <<- c(errs, paste0(key, ": ", msg))

  flag(is.null(meta$depth_bottom) || is.na(meta$depth_bottom),
       "depth_bottom is NA")
  flag(is.null(meta$age_top)  || is.na(meta$age_top),
       "age_top is NA")
  flag(is.null(meta$age_bottom) || is.na(meta$age_bottom),
       "age_bottom is NA")
  flag(is.null(meta$sample_quantity) || is.na(meta$sample_quantity) ||
         meta$sample_quantity <= 0,
       "sample_quantity is missing or <= 0")
  flag(is.null(meta$spike_tablets) || is.na(meta$spike_tablets) ||
         meta$spike_tablets <= 0,
       "spike_tablets is missing or <= 0")
  flag(is.null(meta$spike_density) || is.na(meta$spike_density) ||
         meta$spike_density <= 0,
       "spike_density is missing or <= 0")
  flag(is.null(spike_n) || is.na(spike_n) || spike_n <= 0,
       "spike_n (tracer microspheres counted) is 0 or missing")

  # Interval sign checks (only when both endpoints are present)
  if (!is.null(meta$depth_top)    && !is.na(meta$depth_top) &&
      !is.null(meta$depth_bottom) && !is.na(meta$depth_bottom) &&
      meta$depth_bottom <= meta$depth_top)
    errs <- c(errs, sprintf(
      "%s: depth_bottom (%g) must be > depth_top (%g)",
      key, meta$depth_bottom, meta$depth_top))

  if (!is.null(meta$age_top)    && !is.na(meta$age_top) &&
      !is.null(meta$age_bottom) && !is.na(meta$age_bottom) &&
      meta$age_bottom <= meta$age_top)
    errs <- c(errs, sprintf(
      "%s: age_bottom (%g) must be > age_top (%g) -- ages increase downcore",
      key, meta$age_bottom, meta$age_top))

  errs
}
