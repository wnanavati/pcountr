#' Rarefaction analysis of pollen richness per sample
#'
#' Determines the minimum pollen count (optimal pollen sum) needed for a
#' statistically representative sample, following the simulation approach of
#' Buzas & Hayek (2005) and as applied in palynological practice: pollen grains
#' in each sample are randomly rearranged `n_sim` times, and cumulative taxon
#' richness is tracked across each permutation. The optimal pollen sum is the
#' smallest count at which the mean rarefaction curve reaches `threshold`
#' (default 90%) of the sample's observed richness.
#'
#' Only taxa whose dictionary group codes are in `groups` contribute to the
#' analysis — the same denominator used by [site_matrix()]. Half-grain weights
#' (preservation code 0, weight 0.5) are rounded up to 1 for integer-count
#' rarefaction.
#'
#' Results are stochastic. For reproducibility, call [base::set.seed()] before
#' this function.
#'
#' @param site A `pollen_site` with samples loaded (from [read_site()]).
#' @param groups Character vector of dictionary group codes to include
#'   (e.g. `c("A","B")`). Defaults to `site$pollen_sum`.
#' @param n_sim Number of random permutations per sample. Default `100L`.
#' @param threshold Fraction of observed richness defining the optimal pollen
#'   sum. Default `0.90` (90%).
#' @param depth_range Numeric vector `c(min, max)` of `depth_top` values
#'   (inclusive) to restrict which samples are analysed. `NULL` uses all
#'   samples.
#' @param age_range Numeric vector `c(min, max)` of `age_top` values
#'   (inclusive) to restrict which samples are analysed. `NULL` uses all
#'   samples. Applied after `depth_range`.
#'
#' @return An object of class `pollen_rarefaction`, a named list:
#'   \describe{
#'     \item{`summary`}{Data frame with one row per sample:
#'       `sample`, `depth_top`, `n_grains` (grains in the ΣP denominator),
#'       `n_taxa` (observed richness), `threshold_taxa` (90% of `n_taxa`),
#'       `optimal_sum` (recommended minimum count), `meets_optimal` (logical),
#'       `pct_asymptote` (% of asymptote the actual count achieves).}
#'     \item{`curves`}{Named list, one element per sample. Each element is a
#'       list with `curve_mean`, `curve_lo` (2.5th percentile), and `curve_hi`
#'       (97.5th percentile) — numeric vectors of length `n_grains`.}
#'     \item{`groups`}{Group codes used.}
#'     \item{`threshold`}{The threshold fraction supplied.}
#'     \item{`n_sim`}{Number of permutations used.}
#'   }
#' @references
#'   Buzas, M.A. & Hayek, L.C. (2005). On richness and evenness within and
#'   between communities. *Paleobiology*, 31(2), 199-220.
#' @seealso [site_matrix()], [read_site()]
#' @importFrom stats quantile
#' @export
rarefaction <- function(site,
                        groups      = NULL,
                        n_sim       = 100L,
                        threshold   = 0.90,
                        depth_range = NULL,
                        age_range   = NULL) {

  stopifnot(inherits(site, "pollen_site"))
  n_sim <- as.integer(n_sim)
  if (n_sim < 1L) stop("`n_sim` must be a positive integer.")
  if (threshold <= 0 || threshold >= 1)
    stop("`threshold` must be strictly between 0 and 1 (e.g. 0.90).")
  if (!is.null(depth_range)) {
    if (!is.numeric(depth_range) || length(depth_range) != 2L)
      stop("`depth_range` must be a numeric vector of length 2: c(min, max).")
    depth_range <- sort(depth_range)
  }
  if (!is.null(age_range)) {
    if (!is.numeric(age_range) || length(age_range) != 2L)
      stop("`age_range` must be a numeric vector of length 2: c(min, max).")
    age_range <- sort(age_range)
  }

  groups <- .resolve_groups(groups, site)
  dic    <- site$dictionary
  samps  <- site$samples

  if (!length(samps))
    stop("`site` has no samples. Run read_site() first.")

  # ---------------------------------------------------------------------------
  # Optional sample filters
  # ---------------------------------------------------------------------------
  if (!is.null(depth_range)) {
    samps <- Filter(function(s) {
      dt <- s$meta$depth_top
      !is.null(dt) && length(dt) == 1L && !is.na(dt) &&
        dt >= depth_range[1] && dt <= depth_range[2]
    }, samps)
    if (!length(samps))
      stop("No samples with depth_top in [", depth_range[1], ", ",
           depth_range[2], "].")
  }
  if (!is.null(age_range)) {
    samps <- Filter(function(s) {
      at <- s$meta$age_top
      !is.null(at) && length(at) == 1L && !is.na(at) &&
        at >= age_range[1] && at <= age_range[2]
    }, samps)
    if (!length(samps))
      stop("No samples with age_top in [", age_range[1], ", ",
           age_range[2], "].")
  }

  # ---------------------------------------------------------------------------
  # Per-sample rarefaction
  # ---------------------------------------------------------------------------
  per_sample <- lapply(names(samps), function(nm) {
    s   <- samps[[nm]]
    g   <- s$grains

    # Keep only grains whose group is in the ΣP denominator
    grp   <- dic$group[match(g$code, dic$code)]
    g_sub <- g[!is.na(grp) & grp %in% groups, , drop = FALSE]

    if (nrow(g_sub) == 0L) {
      message("Skipping ", nm, ": no grains in the specified groups.")
      return(NULL)
    }

    # Integer counts: ceiling for half-grains, then expand to grain vector
    taxon_counts <- tapply(g_sub$weight, g_sub$code,
                           function(w) ceiling(sum(w)))
    taxon_counts <- taxon_counts[taxon_counts > 0L]

    if (!length(taxon_counts)) {
      message("Skipping ", nm, ": all group counts are zero after rounding.")
      return(NULL)
    }

    grains_vec <- rep(names(taxon_counts), times = as.integer(taxon_counts))
    N          <- length(grains_vec)
    S_obs      <- length(taxon_counts)            # observed richness

    # Threshold taxa count (target for optimal sum)
    threshold_taxa <- threshold * S_obs           # may be non-integer

    # -------------------------------------------------------------------
    # 100 permutations — fast O(N) per permutation using duplicated()
    # -------------------------------------------------------------------
    sim_mat <- matrix(0L, nrow = n_sim, ncol = N)
    for (k in seq_len(n_sim)) {
      perm            <- sample(grains_vec)
      sim_mat[k, ]    <- cumsum(!duplicated(perm))
    }

    curve_mean <- colMeans(sim_mat)
    curve_lo   <- apply(sim_mat, 2L, quantile, probs = 0.025, names = FALSE)
    curve_hi   <- apply(sim_mat, 2L, quantile, probs = 0.975, names = FALSE)
    # With only n_sim draws, the empirical percentile can sit in the majority
    # cluster while a few outliers pull the mean in the other direction.
    # Clamp so the interval always contains the point estimate.
    curve_lo <- pmin(curve_lo, curve_mean)
    curve_hi <- pmax(curve_hi, curve_mean)

    # Optimal sum: first n where mean curve >= threshold * S_obs
    opt_idx     <- which(curve_mean >= threshold_taxa)[1L]
    optimal_sum <- if (is.na(opt_idx)) NA_integer_ else as.integer(opt_idx)

    # % of asymptote achieved by actual count
    pct_asymptote <- round(curve_mean[N] / S_obs * 100, 1)

    list(
      nm             = nm,
      depth_top      = {v <- s$meta$depth_top;
                        if (is.null(v) || length(v) != 1L) NA_real_
                        else as.numeric(v)},
      n_grains       = N,
      n_taxa         = S_obs,
      threshold_taxa = as.integer(ceiling(threshold_taxa)),
      optimal_sum    = optimal_sum,
      pct_asymptote  = pct_asymptote,
      curve_mean     = curve_mean,
      curve_lo       = curve_lo,
      curve_hi       = curve_hi
    )
  })

  names(per_sample) <- names(samps)
  # Drop skipped samples
  per_sample <- Filter(Negate(is.null), per_sample)

  if (!length(per_sample))
    stop("No samples could be rarefied (check group codes and grain data).")

  # ---------------------------------------------------------------------------
  # Summary data frame
  # ---------------------------------------------------------------------------
  summary_df <- data.frame(
    sample         = vapply(per_sample, `[[`, "", "nm"),
    depth_top      = vapply(per_sample, `[[`, NA_real_, "depth_top"),
    n_grains       = vapply(per_sample, `[[`, NA_integer_, "n_grains"),
    n_taxa         = vapply(per_sample, `[[`, NA_integer_, "n_taxa"),
    threshold_taxa = vapply(per_sample, `[[`, NA_integer_, "threshold_taxa"),
    optimal_sum    = vapply(per_sample, function(r) {
                       v <- r$optimal_sum
                       if (is.null(v)) NA_integer_ else v
                     }, NA_integer_),
    meets_optimal  = vapply(per_sample, function(r) {
                       if (is.na(r$optimal_sum)) NA else
                         r$n_grains >= r$optimal_sum
                     }, NA),
    pct_asymptote  = vapply(per_sample, `[[`, NA_real_, "pct_asymptote"),
    stringsAsFactors = FALSE
  )

  # Curves list (lighter — drop nm field)
  curves <- lapply(per_sample, function(r)
    list(curve_mean = r$curve_mean,
         curve_lo   = r$curve_lo,
         curve_hi   = r$curve_hi))

  structure(
    list(summary   = summary_df,
         curves    = curves,
         groups    = groups,
         threshold = threshold,
         n_sim     = n_sim),
    class = "pollen_rarefaction"
  )
}


#' @export
print.pollen_rarefaction <- function(x, ...) {
  pct <- round(x$threshold * 100)
  cat(sprintf(
    "Pollen rarefaction  [groups: %s | threshold: %d%% | sims: %d]\n\n",
    paste(x$groups, collapse = "+"), pct, x$n_sim))

  df <- x$summary
  df$meets <- ifelse(is.na(df$meets_optimal), "NA",
                     ifelse(df$meets_optimal, "yes", "NO"))
  df$depth_top <- ifelse(is.na(df$depth_top), "--",
                         formatC(df$depth_top, format = "f", digits = 1))
  df$optimal_sum <- ifelse(is.na(df$optimal_sum), "NA",
                           as.character(df$optimal_sum))

  cat(sprintf("%-12s %6s %7s %6s %5s %11s %8s %8s\n",
              "Sample", "Depth", "Grains", "Taxa",
              "Tgt", "OptimalSum", "Meets?", "%Asymp"))
  cat(strrep("-", 70), "\n")
  for (i in seq_len(nrow(df))) {
    cat(sprintf("%-12s %6s %7d %6d %5d %11s %8s %7.1f%%\n",
                df$sample[i],
                df$depth_top[i],
                df$n_grains[i],
                df$n_taxa[i],
                df$threshold_taxa[i],
                df$optimal_sum[i],
                df$meets[i],
                df$pct_asymptote[i]))
  }
  invisible(x)
}
