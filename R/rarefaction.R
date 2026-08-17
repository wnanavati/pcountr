#' Rarefaction analysis and pollen count targets
#'
#' Estimates how many grains a sample would need for a given share of its
#' taxonomic richness. For each sample the rarefaction curve is computed, a
#' Michaelis-Menten model is fitted to it to extrapolate maximum richness
#' (`Smax`), and the grain counts required to recover 70%, 80%, and 90% of
#' `Smax` are derived. A site-level count target is reported as the 90th
#' percentile of the per-sample targets.
#'
#' @section Why the asymptote must be extrapolated:
#' A rarefaction curve computed from a sample terminates, by construction, at
#' that sample's observed richness: drawing all `N` grains always recovers every
#' taxon present. Any criterion phrased as a fraction of *observed* richness is
#' therefore self-referential — it is satisfied automatically at the count the
#' analyst happened to make, and the count it recommends simply scales with
#' effort. Versions of `pcountr` before 0.6.0 made this error.
#'
#' The asymptote must instead be **extrapolated beyond the observed count**.
#' Following Lesven et al. (2026), richness is modelled as
#'
#' \deqn{R(n) = \frac{S_{max} \cdot n}{K + n}}{R(n) = Smax * n / (K + n)}
#'
#' where `Smax` is maximum (asymptotic) richness and `K` is the grain count at
#' which half of `Smax` is recovered. Because `Smax` lies beyond what was
#' observed, a sample can genuinely fall short, and the recommended count no
#' longer tracks the count already made.
#'
#' Inverting the model gives the count needed for a proportion `p` of `Smax` in
#' closed form:
#'
#' \deqn{n_p = K \cdot \frac{p}{1 - p}}{n_p = K * p / (1 - p)}
#'
#' so 70%, 80%, and 90% of `Smax` require `7K/3`, `4K`, and `9K` grains
#' respectively. Every reported target depends only on `K` — the steepness of
#' the curve — so two samples may need identical counts while having different
#' ceilings.
#'
#' This relationship is consistent with Table 3 of Lesven et al. (2026): solving
#' for `K` independently from each of their published 60%, 80%, and 90% columns
#' yields values agreeing to within 0.4 grains at every one of their ten sites.
#' Their tabulated figures cannot be reproduced digit-for-digit, because each
#' cell is rounded independently and the `K` column is itself rounded to an
#' integer.
#'
#' @section What this function does not do:
#' No adequacy verdict is returned. Whether a count is sufficient depends on the
#' analytical objective, which is the analyst's to set: Lesven et al. (2026)
#' found ~250 grains adequate for reconstructing dominant vegetation
#' assemblages (~70% of richness) but recommended ~1000 grains for biodiversity
#' assessment or detection of rare taxa (85-95% of richness). The `pct_smax`
#' column reports what a count actually recovered; the tier columns report what
#' further effort would buy.
#'
#' @section Computation:
#' Lesven et al. estimated the curve by resampling (1000 random draws without
#' replacement at each increment), and Iglesias et al. by 100 random
#' rearrangements. `pcountr` departs from both and computes the curve
#' **analytically**, from the exact expectation given by Hurlbert (1971):
#'
#' \deqn{E[S(n)] = \sum_i \left[ 1 - {{N - N_i} \choose n} / {N \choose n} \right]}{E[S(n)] = sum_i [ 1 - C(N - N_i, n) / C(N, n) ]}
#'
#' summed over the `S` taxa present, with `N` grains in total and `N_i` of the
#' *i*th taxon. The implementation evaluates the algebraically identical
#' `S - sum_i C(N - N_i, n) / C(N, n)` on the log scale.
#'
#' Consequently `Smax`, `K`, and the tier counts are **deterministic** and need
#' no [base::set.seed()]. Permutations (`n_sim`) are used only for the confidence
#' band returned in `curves`, and do not affect any reported target.
#'
#' The model is fitted by separable least squares: for a given `K`, `Smax` has a
#' closed-form least-squares solution, so only `K` is optimised numerically
#' (via [stats::optimize()]) over `log(K)`. Reducing the problem to one
#' well-conditioned dimension makes the search robust and removes any dependence
#' on starting values. Note that [stats::optimize()] assumes the objective is
#' unimodal over the interval and returns a local optimum; for the rarefaction
#' curves tested this coincided with a dense grid search, but it is not
#' guaranteed in general. Lesven et al. fitted the same model by
#' Levenberg-Marquardt; both approaches minimise the same sum of squares.
#'
#' Only taxa whose dictionary group codes are in `groups` contribute — the same
#' denominator used by [site_matrix()] and [count_metrics()]. Non-pollen-sum
#' groups (e.g. aquatics `Q`, indeterminable `X`) are excluded. Each recorded
#' grain counts as one detection, so half-grains (preservation modifier `0`,
#' weight 0.5) count as whole grains: a fragment is still an observed
#' individual, and rounding summed weights would bias precisely the rare taxa
#' that determine where the curve flattens.
#'
#' @section Interpretation and limits:
#' `Smax` is a model extrapolation, not an observation. Lesven et al. fitted
#' curves from 1000-grain counts and found that *none* reached a true asymptote
#' within that range; fits from ~300-grain counts sit on the steep limb of the
#' curve, where `Smax` is poorly constrained. Treat the targets as provisional
#' and inspect `s_max` and `k` rather than relying on a single number. Fits that fail the sanity checks return `NA`
#' rather than a fabricated value.
#'
#' Richness also depends on taxonomic resolution: a dictionary that lumps types
#' yields lower `Smax` and smaller targets. Targets are sample- and
#' site-specific and should not be transferred between sites without
#' recomputing.
#'
#' @param site A `pollen_site` with samples loaded (from [read_site()]).
#' @param groups Character vector of dictionary group codes to include
#'   (e.g. `c("A","B")`). Defaults to `site$pollen_sum`.
#' @param n_sim Number of permutations used for the confidence band on the
#'   returned curves. Does not affect `Smax`, `K`, or any target. Default
#'   `100L`; set to `0L` to skip.
#' @param depth_range Numeric vector `c(min, max)` of `depth_top` values
#'   (inclusive) to restrict which samples are analysed. `NULL` uses all
#'   samples.
#' @param age_range Numeric vector `c(min, max)` of `age_top` values
#'   (inclusive) to restrict which samples are analysed. `NULL` uses all
#'   samples. Applied after `depth_range`.
#'
#' @return An object of class `pollen_rarefaction`, a named list:
#'   \describe{
#'     \item{`summary`}{Data frame, one row per sample: `sample`, `depth_top`,
#'       `n_grains` (grains in the sum), `n_taxa` (observed richness), `s_max`,
#'       `k`, `pct_smax`, `n70`, `n80`, `n90` (grains needed for those shares of
#'       `s_max`), and `converged`.
#'
#'       `pct_smax` is the share of `s_max` the fitted curve reaches at the count
#'       actually made, `100 * n_grains / (k + n_grains)`. It is model-based, so
#'       it agrees with the tier columns exactly: `pct_smax >= 70` if and only if
#'       `n_grains >= n70`. Note it is *not* `n_taxa / s_max`, which reads higher
#'       because the least-squares fit sits a little below observed richness at
#'       `n = n_grains`; compare `n_taxa` against `s_max` directly if you want
#'       the raw observed share.}
#'     \item{`site_target`}{Named numeric vector (`70%`, `80%`, `90%`): the 90th
#'       percentile of the per-sample targets across samples with usable fits.}
#'     \item{`curves`}{Named list, one element per sample, each with
#'       `curve_mean` (analytic expectation), `curve_fit` (fitted
#'       Michaelis-Menten curve), and — when `n_sim > 0` — `curve_lo` and
#'       `curve_hi` (2.5th and 97.5th percentiles of the permutations).}
#'     \item{`groups`}{Group codes used.}
#'     \item{`n_sim`}{Permutations used for the confidence band.}
#'     \item{`n_failed`}{Number of samples whose fit was not usable.}
#'   }
#'
#' @references
#'   Lesven, J.A., Gaboriau, D.M., Richard, P.J.H., Ali, A.A., Asselin, H.,
#'   Blache, M., Girardin, M.P., Jean-Sépet, M., Moroy, N. & Bergeron, Y.
#'   (2026). Objective-specific pollen count thresholds for robust and relevant
#'   assemblages in boreal and northern temperate forests of eastern Canada.
#'   *Palaeogeography, Palaeoclimatology, Palaeoecology*, 699, 113994.
#'   \doi{10.1016/j.palaeo.2026.113994}
#'
#'   Iglesias, V., Quintana, F., Nanavati, W. & Whitlock, C. (2017).
#'   Interpreting modern and fossil pollen data along a steep environmental
#'   gradient in northern Patagonia. *The Holocene*, 27(7), 1008-1018.
#'   \doi{10.1177/0959683616678467}
#'
#'   Hurlbert, S.H. (1971). The nonconcept of species diversity: a critique and
#'   alternative parameters. *Ecology*, 52(4), 577-586.
#'   \doi{10.2307/1934145}
#'
#' @seealso [site_matrix()], [count_metrics()], [read_site()]
#' @importFrom stats quantile optimize
#' @export
rarefaction <- function(site,
                        groups      = NULL,
                        n_sim       = 100L,
                        depth_range = NULL,
                        age_range   = NULL) {

  stopifnot(inherits(site, "pollen_site"))
  n_sim <- as.integer(n_sim)
  if (is.na(n_sim) || n_sim < 0L)
    stop("`n_sim` must be a non-negative integer.")
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
  # Per-sample curve, fit, and targets
  # ---------------------------------------------------------------------------
  per_sample <- lapply(names(samps), function(nm) {
    s <- samps[[nm]]
    g <- s$grains

    # Keep only grains whose group is in the pollen sum
    grp   <- dic$group[match(g$code, dic$code)]
    g_sub <- g[!is.na(grp) & grp %in% groups, , drop = FALSE]

    if (nrow(g_sub) == 0L) {
      message("Skipping ", nm, ": no grains in the specified groups.")
      return(NULL)
    }

    # One recorded grain = one detection (half-grains count as whole)
    taxon_counts <- table(g_sub$code)
    taxon_counts <- as.integer(taxon_counts[taxon_counts > 0L])
    N     <- sum(taxon_counts)
    S_obs <- length(taxon_counts)

    curve_mean <- .rarefy_expected(taxon_counts)
    fit        <- .fit_mm(seq_len(N), curve_mean, S_obs)

    # Permutation band (presentation only; not used for any target)
    curve_lo <- curve_hi <- NULL
    if (n_sim > 0L) {
      grains_vec <- rep(seq_along(taxon_counts), times = taxon_counts)
      sim_mat    <- matrix(0L, nrow = n_sim, ncol = N)
      for (k in seq_len(n_sim)) {
        perm         <- sample(grains_vec)
        sim_mat[k, ] <- cumsum(!duplicated(perm))
      }
      curve_lo <- apply(sim_mat, 2L, stats::quantile, probs = 0.025,
                        names = FALSE)
      curve_hi <- apply(sim_mat, 2L, stats::quantile, probs = 0.975,
                        names = FALSE)
      curve_lo <- pmin(curve_lo, curve_mean)
      curve_hi <- pmax(curve_hi, curve_mean)
    }

    list(
      nm         = nm,
      depth_top  = {v <- s$meta$depth_top
                    if (is.null(v) || length(v) != 1L) NA_real_
                    else as.numeric(v)},
      n_grains   = N,
      n_taxa     = S_obs,
      s_max      = fit$s_max,
      k          = fit$k,
      # Share of Smax reached at the count actually made, from the fitted curve:
      # R(N)/Smax = N/(K+N). Model-based, so it is exactly consistent with the
      # tier columns (N >= K*p/(1-p) if and only if N/(K+N) >= p). Using observed
      # richness over Smax instead would read higher, because the least-squares
      # fit sits slightly below observed richness at n = N.
      pct_smax   = if (is.na(fit$k)) NA_real_
                   else round(100 * N / (fit$k + N), 1),
      n70        = .mm_target(fit$k, 7, 3),   # p/(1-p) = 7/3
      n80        = .mm_target(fit$k, 4),      #           4
      n90        = .mm_target(fit$k, 9),      #           9
      converged  = fit$ok,
      curve_mean = curve_mean,
      curve_fit  = if (is.na(fit$s_max)) rep(NA_real_, N)
                   else fit$s_max * seq_len(N) / (fit$k + seq_len(N)),
      curve_lo   = curve_lo,
      curve_hi   = curve_hi
    )
  })

  names(per_sample) <- names(samps)
  per_sample <- Filter(Negate(is.null), per_sample)

  if (!length(per_sample))
    stop("No samples could be rarefied (check group codes and grain data).")

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------
  summary_df <- data.frame(
    sample    = vapply(per_sample, `[[`, "",         "nm"),
    depth_top = vapply(per_sample, `[[`, NA_real_,   "depth_top"),
    n_grains  = vapply(per_sample, `[[`, NA_integer_,"n_grains"),
    n_taxa    = vapply(per_sample, `[[`, NA_integer_,"n_taxa"),
    s_max     = vapply(per_sample, `[[`, NA_real_,   "s_max"),
    k         = vapply(per_sample, `[[`, NA_real_,   "k"),
    pct_smax  = vapply(per_sample, `[[`, NA_real_,   "pct_smax"),
    n70       = vapply(per_sample, `[[`, NA_real_,   "n70"),
    n80       = vapply(per_sample, `[[`, NA_real_,   "n80"),
    n90       = vapply(per_sample, `[[`, NA_real_,   "n90"),
    converged = vapply(per_sample, `[[`, NA,         "converged"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )

  # Site target: 90th percentile across usable fits
  ok <- summary_df$converged & !is.na(summary_df$n70)
  site_target <- if (!any(ok)) {
    c("70%" = NA_real_, "80%" = NA_real_, "90%" = NA_real_)
  } else {
    vapply(c(n70 = "n70", n80 = "n80", n90 = "n90"), function(cl)
      ceiling(stats::quantile(summary_df[[cl]][ok], probs = 0.90,
                              names = FALSE)),
      numeric(1))
  }
  names(site_target) <- c("70%", "80%", "90%")

  curves <- lapply(per_sample, function(r)
    Filter(Negate(is.null),
           list(curve_mean = r$curve_mean,
                curve_fit  = r$curve_fit,
                curve_lo   = r$curve_lo,
                curve_hi   = r$curve_hi)))

  structure(
    list(summary     = summary_df,
         site_target = site_target,
         curves      = curves,
         groups      = groups,
         n_sim       = n_sim,
         n_failed    = sum(!summary_df$converged)),
    class = "pollen_rarefaction"
  )
}


# --- internal helpers --------------------------------------------------------

# Exact expected rarefaction curve (Hurlbert 1971):
#   E[S(n)] = S - sum_i C(N - N_i, n) / C(N, n)
# Computed on the log scale; terms with n > N - N_i contribute 0.
.rarefy_expected <- function(taxon_counts) {
  N  <- sum(taxon_counts)
  n  <- seq_len(N)
  ln <- suppressWarnings(lchoose(N, n))
  out <- vapply(n, function(nn) {
    terms <- suppressWarnings(lchoose(N - taxon_counts, nn))
    length(taxon_counts) - sum(exp(terms - ln[nn]))
  }, numeric(1))
  # Guard against tiny negative/regression from floating point
  out <- pmin(pmax(out, 0), length(taxon_counts))
  cummax(out)
}

# Fit R(n) = Smax * n / (K + n) by separable least squares.
# For fixed K, Smax has a closed-form LS solution, so only K is optimised.
.fit_mm <- function(n, R, s_obs) {
  bad <- list(s_max = NA_real_, k = NA_real_, ok = FALSE)
  N <- max(n)
  if (N < 30L || s_obs < 4L) return(bad)   # too little curve to extrapolate

  sse <- function(K) {
    x <- n / (K + n)
    denom <- sum(x * x)
    if (!is.finite(denom) || denom <= 0) return(Inf)
    s <- sum(R * x) / denom
    sum((R - s * x)^2)
  }

  # K is a scale parameter spanning orders of magnitude, so optimise log(K):
  # better conditioned than a linear search over c(0, 100N), where a small true
  # K sits in a tiny fraction of the interval.
  opt <- try(stats::optimize(function(lk) sse(exp(lk)),
                             interval = c(log(1e-6), log(100 * N)),
                             tol = 1e-10),
             silent = TRUE)
  if (inherits(opt, "try-error")) return(bad)

  K <- exp(opt$minimum)
  x <- n / (K + n)
  S <- sum(R * x) / sum(x * x)

  # Sanity checks: the ceiling cannot sit below what was observed, and a K far
  # beyond the count means the curve carries no saturation information.
  ok <- is.finite(K) && is.finite(S) && K > 0 && S > 0 &&
        S >= s_obs && K < 20 * N
  if (!ok) return(bad)

  list(s_max = S, k = K, ok = TRUE)
}

# Grains needed for proportion p of Smax: n_p = K * p / (1 - p).
#
# The multiplier is supplied as an exact rational (num/den) rather than computed
# from p, and a small tolerance is subtracted before rounding up. Evaluating
# K * p / (1 - p) in floating point overshoots exact integers: K = 111, p = 0.9
# gives 999.0000000000002, so a naive ceiling() returns 1000 instead of 999.
# This bit the 80% and 90% tiers for every integer K.
.mm_target <- function(K, num, den = 1) {
  if (is.na(K) || !is.finite(K)) return(NA_real_)
  ceiling((K * num) / den - 1e-9)
}


#' @export
print.pollen_rarefaction <- function(x, ...) {
  cat(sprintf(
    "Pollen rarefaction  [groups: %s | sims: %d | Michaelis-Menten]\n\n",
    paste(x$groups, collapse = "+"), x$n_sim))

  df <- x$summary
  fmt <- function(v, digits = 0) {
    ifelse(is.na(v), "--", formatC(v, format = "f", digits = digits))
  }

  # Spanning header sits above the three tier columns (which start at col 46)
  cat(strrep(" ", 45), "Grains needed for % of Smax\n", sep = "")
  cat(sprintf("%-11s %6s %6s %4s %4s %6s   %6s %6s %6s\n",
              "Sample", "Depth", "Grains", "Taxa", "Smax", "%Smax",
              "70%", "80%", "90%"))
  cat(strrep("-", 65), "\n", sep = "")

  for (i in seq_len(nrow(df))) {
    cat(sprintf("%-11s %6s %6d %4d %4s %6s   %6s %6s %6s\n",
                df$sample[i],
                fmt(df$depth_top[i], 1),
                df$n_grains[i],
                df$n_taxa[i],
                fmt(df$s_max[i], 0),
                if (is.na(df$pct_smax[i])) "--"
                  else sprintf("%.1f%%", df$pct_smax[i]),
                fmt(df$n70[i]), fmt(df$n80[i]), fmt(df$n90[i])))
  }

  cat(strrep("-", 65), "\n", sep = "")
  st <- x$site_target
  cat(sprintf("%-11s %6s %6s %4s %4s %6s   %6s %6s %6s\n",
              "Site (q90)", "", "", "", "", "",
              fmt(st[["70%"]]), fmt(st[["80%"]]), fmt(st[["90%"]])))

  cat("\nSmax = extrapolated richness (Michaelis-Menten).\n")
  cat("%Smax = share of Smax the fitted curve reaches at this count",
      "(= N/(K+N)); consistent\n  with the tier columns. Compare Taxa against",
      "Smax for the raw observed share.\n")
  if (x$n_failed > 0L)
    cat(sprintf("%d of %d fits unusable (--); excluded from the site percentile.\n",
                x$n_failed, nrow(df)))
  cat("Smax is extrapolated, not observed; from short counts treat targets as",
      "lower bounds.\n")
  cat("No adequacy verdict is implied - see ?rarefaction for objective-specific",
      "guidance.\n")
  invisible(x)
}
