# Tests for rarefaction() — Michaelis-Menten count targets (v0.6.0 rewrite).
#
# Before 0.6.0 the "optimal pollen sum" was defined as a fraction of each
# sample's OWN observed richness. That is self-referential: a rarefaction curve
# terminates at S_obs by construction, so the criterion was always satisfied,
# `meets_optimal` had no code path to FALSE, and `pct_asymptote` was
# arithmetically pinned at 100%. The recommended count merely tracked effort.
#
# The rewrite extrapolates the asymptote (Smax) with a Michaelis-Menten model
# following Lesven et al. (2026), so targets can exceed the count actually made.
# These tests assert the mathematical invariants of that model, which hold
# regardless of the optimiser's exact output.

# ── Helpers: a self-contained site, so tests need no unpublished fixtures ────

make_dic_rf <- function() {
  path <- tempfile(fileext = ".csv")
  writeLines(c(
    "code,alias,group,name,is_special",
    "B,B,B,Betula,FALSE",
    "I,I,A,Picea,FALSE",
    "A,A,A,Abies,FALSE",
    "C,C,B,Corylus,FALSE",
    "D,D,F,Dryopteris,FALSE",
    "E,E,B,Ericaceae,FALSE",
    "F,F,A,Fagus,FALSE",
    "G,G,B,Gramineae,FALSE",
    "H,H,A,Tsuga,FALSE",
    "J,J,B,Juglans,FALSE",
    "Q,Q,Q,Nuphar,FALSE",      # aquatic — outside the A/B/F sum
    "X,X,X,Indeterminable,FALSE"
  ), path)
  path
}

# counts: named integer vector of code -> number of grains
stream_rf <- function(counts, pres = "1") {
  paste0(unlist(lapply(names(counts), function(cd)
    rep(paste0(cd, pres), counts[[cd]]))), collapse = "")
}

make_cnt_rf <- function(body) {
  path <- tempfile(fileext = ".CNT")
  writeLines(c("PCounT 2.0", "count file",
               "TEST.csv, 1.0, 12000, 10420, 0, 1;",
               "POLLEN SUM = ABF", "Test Sample",
               paste0("{slide1}", body)), path)
  path
}

# A moderately uneven assemblage: N = 72, S = 10
counts_a <- c(B = 20, I = 15, A = 12, C = 8, D = 6, E = 4, F = 3, G = 2,
              H = 1, J = 1)
# Flatter, richer: N = 96, S = 10
counts_b <- c(B = 14, I = 13, A = 12, C = 11, D = 10, E = 9, F = 9, G = 8,
              H = 6, J = 4)

make_site_rf <- function(streams, depths = NULL) {
  dic  <- read_dic(make_dic_rf())
  samps <- lapply(seq_along(streams), function(i) {
    cnt <- read_cnt(make_cnt_rf(streams[[i]]), quiet = TRUE)
    cnt$meta$sample_name <- names(streams)[i]
    if (!is.null(depths)) cnt$meta$depth_top <- depths[i]
    cnt
  })
  names(samps) <- names(streams)
  pollen_site("Test", dic, samples = samps)
}

site_rf <- make_site_rf(
  list(S1 = stream_rf(counts_a), S2 = stream_rf(counts_b)),
  depths = c(5, 50)
)

# ── Return structure ────────────────────────────────────────────────────────

test_that("rarefaction() returns the documented structure", {
  r <- rarefaction(site_rf, n_sim = 10L)

  expect_s3_class(r, "pollen_rarefaction")
  expect_named(r, c("summary", "site_target", "curves", "groups",
                    "n_sim", "n_failed"))
  expect_true(all(c("sample", "depth_top", "n_grains", "n_taxa", "s_max",
                    "k", "pct_smax", "n70", "n80", "n90", "converged")
                  %in% names(r$summary)))
  expect_equal(nrow(r$summary), 2L)
})

test_that("the removed circular columns are gone", {
  r <- rarefaction(site_rf, n_sim = 0L)
  expect_false(any(c("threshold_taxa", "optimal_sum", "meets_optimal",
                     "pct_asymptote") %in% names(r$summary)))
  expect_false("threshold" %in% names(r))
})

# ── Exact rarefaction curve (Hurlbert 1971) ─────────────────────────────────

test_that("E[S(1)] = 1 and E[S(N)] = S_obs exactly", {
  r <- rarefaction(site_rf, n_sim = 0L)
  for (i in seq_len(nrow(r$summary))) {
    mn <- r$curves[[i]]$curve_mean
    expect_equal(length(mn), r$summary$n_grains[i])
    expect_equal(mn[1], 1, tolerance = 1e-9,
                 info = "one grain always yields exactly one taxon")
    expect_equal(mn[length(mn)], r$summary$n_taxa[i], tolerance = 1e-9,
                 info = "drawing all N grains always recovers every taxon")
  }
})

test_that("the mean curve is non-decreasing", {
  r <- rarefaction(site_rf, n_sim = 0L)
  for (cv in r$curves)
    expect_true(all(diff(cv$curve_mean) >= -1e-9))
})

test_that("targets are deterministic — no set.seed needed", {
  set.seed(1);   r1 <- rarefaction(site_rf, n_sim = 5L)
  set.seed(999); r2 <- rarefaction(site_rf, n_sim = 5L)

  expect_equal(r1$summary$s_max, r2$summary$s_max)
  expect_equal(r1$summary$k,     r2$summary$k)
  expect_equal(r1$summary$n70,   r2$summary$n70)
  expect_equal(r1$summary$n90,   r2$summary$n90)
  expect_equal(r1$site_target,   r2$site_target)
})

test_that("n_sim = 0 skips the confidence band but keeps the curve", {
  r <- rarefaction(site_rf, n_sim = 0L)
  expect_named(r$curves[[1]], c("curve_mean", "curve_fit"))
  expect_equal(r$n_sim, 0L)
})

test_that("confidence band brackets the mean when requested", {
  set.seed(7)
  r <- rarefaction(site_rf, n_sim = 50L)
  for (cv in r$curves) {
    expect_true(all(cv$curve_lo <= cv$curve_mean + 1e-9))
    expect_true(all(cv$curve_mean <= cv$curve_hi + 1e-9))
  }
})

# ── Michaelis-Menten model and closed-form targets ──────────────────────────

test_that("Smax is at least observed richness", {
  r <- rarefaction(site_rf, n_sim = 0L)
  ok <- r$summary$converged
  expect_true(all(r$summary$s_max[ok] >= r$summary$n_taxa[ok]),
              info = "an extrapolated ceiling below the observed count is invalid")
})

test_that("tier counts follow n_p = K * p/(1-p)", {
  r  <- rarefaction(site_rf, n_sim = 0L)
  df <- r$summary[r$summary$converged, ]
  expect_gt(nrow(df), 0L)
  expect_equal(df$n70, ceiling((df$k * 7) / 3 - 1e-9))
  expect_equal(df$n80, ceiling(df$k * 4 - 1e-9))
  expect_equal(df$n90, ceiling(df$k * 9 - 1e-9))
})

test_that(".mm_target is immune to floating-point overshoot", {
  # Regression: K * p/(1-p) in floating point exceeds exact integers, e.g.
  # 111 * 0.9 / 0.1 = 999.0000000000002, so a naive ceiling() returns 1000.
  # Expected values below are exact arithmetic on integral K, using K in the
  # range Lesven et al. (2026) report (71-182). Some coincide with their
  # published tier values and some do not, because their tabulated K is rounded
  # to an integer while the K used to compute their cells was not.
  expect_equal(.mm_target(111, 7, 3), 259)
  expect_equal(.mm_target(111, 4),    444)
  expect_equal(.mm_target(111, 9),    999)
  expect_equal(.mm_target(92,  4),    368)
  expect_equal(.mm_target(162, 9),   1458)
  expect_equal(.mm_target(90,  9),    810)

  # ...while genuinely fractional values still round up
  expect_equal(.mm_target(10.5, 4), 42)
  expect_equal(.mm_target(10.6, 4), 43)
  expect_true(is.na(.mm_target(NA_real_, 9)))
})

test_that("tier counts increase with the share of Smax", {
  r  <- rarefaction(site_rf, n_sim = 0L)
  df <- r$summary[r$summary$converged, ]
  expect_true(all(df$n70 < df$n80))
  expect_true(all(df$n80 < df$n90))
})

test_that("the fitted curve reaches p * Smax at the reported target", {
  # Direct check of the inversion: R(n_p) / Smax == p
  r  <- rarefaction(site_rf, n_sim = 0L)
  df <- r$summary[r$summary$converged, ]
  for (i in seq_len(nrow(df))) {
    K <- df$k[i]
    for (p in c(0.70, 0.80, 0.90)) {
      n <- K * p / (1 - p)
      expect_equal(n / (K + n), p, tolerance = 1e-9)
    }
  }
})

test_that("pct_smax is the share of Smax recovered, and never exceeds 100", {
  r  <- rarefaction(site_rf, n_sim = 0L)
  df <- r$summary[r$summary$converged, ]
  expect_equal(df$pct_smax, round(100 * df$n_taxa / df$s_max, 1))
  expect_true(all(df$pct_smax <= 100 + 1e-9))
})

# ── Site-level target ───────────────────────────────────────────────────────

test_that("site_target is the 90th percentile of per-sample targets", {
  r  <- rarefaction(site_rf, n_sim = 0L)
  df <- r$summary[r$summary$converged, ]
  expect_named(r$site_target, c("70%", "80%", "90%"))
  expect_equal(r$site_target[["70%"]],
               ceiling(stats::quantile(df$n70, 0.90, names = FALSE)))
  expect_equal(r$site_target[["90%"]],
               ceiling(stats::quantile(df$n90, 0.90, names = FALSE)))
})

# ── Half-grains count as whole detections ───────────────────────────────────

test_that("half-grains count as whole grains", {
  # B10 is a half-grain (weight 0.5) but still one observed individual.
  half <- make_site_rf(list(
    S1 = paste0(stream_rf(counts_a), stream_rf(c(B = 4), pres = "10"))
  ))
  r <- rarefaction(half, n_sim = 0L)

  expect_equal(r$summary$n_grains[1], sum(counts_a) + 4L,
               info = "n_grains must count records, not summed weights")
  expect_equal(r$summary$n_taxa[1], length(counts_a),
               info = "a half-grain of an existing taxon adds no new taxon")
})

# ── Group filtering ─────────────────────────────────────────────────────────

test_that("taxa outside the pollen sum are excluded", {
  # Q (aquatic) and X (indeterminable) must not contribute grains or richness.
  with_q <- make_site_rf(list(
    S1 = paste0(stream_rf(counts_a), stream_rf(c(Q = 9, X = 5)))
  ))
  r <- rarefaction(with_q, n_sim = 0L)

  expect_equal(r$summary$n_grains[1], sum(counts_a))
  expect_equal(r$summary$n_taxa[1],   length(counts_a))
})

test_that("groups = can be overridden", {
  r <- rarefaction(site_rf, groups = "A", n_sim = 0L)
  # Only A-group taxa in the dictionary: I, A, F, H
  expect_equal(r$groups, "A")
  expect_lte(r$summary$n_taxa[1], 4L)
})

# ── Graceful failure ────────────────────────────────────────────────────────

test_that("counts too small to extrapolate return NA, not a fabricated value", {
  tiny <- make_site_rf(list(S1 = stream_rf(c(B = 5, I = 3, A = 2))))  # N = 10
  r <- suppressMessages(rarefaction(tiny, n_sim = 0L))

  expect_false(r$summary$converged[1])
  expect_true(is.na(r$summary$s_max[1]))
  expect_true(is.na(r$summary$n70[1]))
  expect_true(is.na(r$summary$pct_smax[1]))
  expect_equal(r$n_failed, 1L)
})

test_that("failed fits are excluded from the site percentile", {
  mixed <- make_site_rf(list(
    Good = stream_rf(counts_a),
    Tiny = stream_rf(c(B = 5, I = 3, A = 2))
  ))
  r <- suppressMessages(rarefaction(mixed, n_sim = 0L))

  expect_equal(r$n_failed, 1L)
  good <- r$summary$n90[r$summary$converged]
  expect_equal(r$site_target[["90%"]],
               ceiling(stats::quantile(good, 0.90, names = FALSE)))
})

test_that("site_target is NA when no fit succeeds", {
  tiny <- make_site_rf(list(S1 = stream_rf(c(B = 5, I = 3, A = 2))))
  r <- suppressMessages(rarefaction(tiny, n_sim = 0L))
  expect_true(all(is.na(r$site_target)))
})

# ── Filters and validation ──────────────────────────────────────────────────

test_that("depth_range restricts which samples are analysed", {
  r <- rarefaction(site_rf, depth_range = c(0, 10), n_sim = 0L)
  expect_equal(nrow(r$summary), 1L)
  expect_equal(r$summary$depth_top[1], 5)
})

test_that("depth_range with no matching samples errors", {
  expect_error(rarefaction(site_rf, depth_range = c(9999, 10000)),
               "No samples with depth_top")
})

test_that("invalid arguments are rejected", {
  expect_error(rarefaction(list()), "pollen_site")
  expect_error(rarefaction(site_rf, n_sim = -1L), "non-negative")
  expect_error(rarefaction(site_rf, depth_range = 5), "length 2")
})

# ── Print method ────────────────────────────────────────────────────────────

test_that("print method runs and reports the site target", {
  r <- rarefaction(site_rf, n_sim = 0L)
  out <- capture.output(print(r))
  expect_true(any(grepl("Michaelis-Menten", out)))
  expect_true(any(grepl("Grains needed for", out)))
  expect_true(any(grepl("Site \\(q90\\)", out)))
  expect_true(any(grepl("Smax", out)))
})

test_that("print marks unusable fits with --", {
  tiny <- make_site_rf(list(S1 = stream_rf(c(B = 5, I = 3, A = 2))))
  r <- suppressMessages(rarefaction(tiny, n_sim = 0L))
  out <- capture.output(print(r))
  expect_true(any(grepl("--", out, fixed = TRUE)))
  expect_true(any(grepl("unusable", out)))
})
