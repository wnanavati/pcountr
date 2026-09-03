#' Compute PCount-equivalent metrics for a sample
#'
#' Reproduces the quantities in a PCount `.RPT` report: per-group sums, the
#' basic and total count sums, tracer-spike count, sum/spike ratio,
#' concentration, traverse count and the mean per traverse (returned as
#' `mean_grains_per_traverse`, which keeps its historical name).
#'
#' Concentration follows the tracer (Stockmarr) equation:
#' \deqn{C = \frac{\Sigma P}{\Sigma spike} \times \frac{tablets \times density}{quantity}}
#'
#' The concentration *unit* depends on the sample's recorded units: `counts/cm3`
#' when the sample quantity is a volume (ml), or `counts/g` when it is a mass
#' (g). Samples with no recorded units get `counts/unit`.
#'
#' @param x A `pollen_count`.
#' @param dictionary Optional `pollen_dictionary`; defaults to `x$site`'s
#'   dictionary if present. Required to map taxon codes to groups for the sum.
#' @return A list of metrics.
#' @export
count_metrics <- function(x, dictionary = NULL) {
  stopifnot(inherits(x, "pollen_count"))
  if (is.null(dictionary) && !is.null(x$site)) dictionary <- x$site$dictionary
  if (is.null(dictionary)) {
    stop("A dictionary is required (pass `dictionary=` or attach a site).")
  }

  g <- x$grains
  # Exclude specials (codes beginning '#') from the sum entirely.
  is_special <- grepl("^#", g$code)
  grp <- dictionary$group[match(g$code, dictionary$code)]

  # Per-group weighted sums (sum groups only).
  group_sums <- tapply(g$weight[!is_special], grp[!is_special], sum)
  group_sums[is.na(group_sums)] <- 0
  gs <- function(k) if (k %in% names(group_sums)) as.numeric(group_sums[k]) else 0

  basic_groups <- x$meta$pollen_sum_groups
  basic_sum <- sum(vapply(basic_groups, gs, 0))
  # "Total" adds aquatics (Q) to the basic sum, matching PCount's TOTAL line.
  total_groups <- union(basic_groups, "Q")
  total_sum <- sum(vapply(total_groups, gs, 0))

  spike <- x$spike_n
  tablets <- x$meta$spike_tablets
  density <- x$meta$spike_density
  qty <- x$meta$sample_quantity
  spike_added <- tablets * density
  ratio <- if (spike > 0) total_sum / spike else NA_real_

  conc_method <- x$meta$conc_method %||% "spike"
  concentration <- switch(conc_method,
    spike      = if (spike > 0 && !is.na(qty) && qty > 0 &&
                     !is.na(spike_added) && is.finite(spike_added) && spike_added > 0)
                   ratio * spike_added / qty else NA_real_,
    volumetric = if (!is.na(qty) && qty > 0) total_sum / qty else NA_real_,
    none       = NA_real_,
    NA_real_
  )
  conc_unit <- switch(x$meta$units %||% "",
                      "ml" = "counts/cm3",
                      "g"  = "counts/g",
                      "counts/unit")

  n_trav <- length(x$traverses)
  mean_per_trav <- if (n_trav > 0) total_sum / n_trav else NA_real_

  list(
    group_sums = group_sums,
    basic_sum = basic_sum,
    total_sum = total_sum,
    spike = spike,
    spike_added = spike_added,
    ratio = ratio,
    concentration = concentration,
    concentration_unit = conc_unit,
    n_traverses = n_trav,
    mean_grains_per_traverse = mean_per_trav
  )
}

#' Tabulate counts by taxon and preservation state
#'
#' Produces a taxon x preservation-class table. Half-weight fragments (code `0`)
#' contribute their 0.5 weight; the `0` itself is reported as a pseudo-class so
#' that, for example, a class-8 fragment appears under both `8` accounting and
#' a `80` fragment column, mirroring PCount's report layout.
#'
#' When `collapse_multistate = TRUE`, entries carrying more than one
#' preservation state are attributed to a single class using the site precedence
#' (see [default_precedence]); otherwise each distinct preservation string is
#' its own column.
#'
#' @param x A `pollen_count`.
#' @param collapse_multistate Logical; attribute multi-state entries to one class.
#' @return A matrix of weighted counts (taxa in rows, preservation in columns).
#' @export
preservation_table <- function(x, collapse_multistate = FALSE) {
  stopifnot(inherits(x, "pollen_count"))
  g <- x$grains
  if (!nrow(g)) return(matrix(numeric(0), 0, 0))

  # Reconstruct the raw preservation label as PCount wrote it: base digit plus
  # a trailing 0 for fragments (e.g. "8" -> "80" when half). Entries made as a
  # modifier alone (e.g. hidden with no base state) have no base digit, so fall
  # back to the pres string.
  lbl <- ifelse(is.na(g$base) | !nzchar(g$base), g$pres, g$base)
  lbl[is.na(lbl)] <- ""
  raw_label <- ifelse(g$weight == 0.5, paste0(lbl, "0"), lbl)

  if (collapse_multistate) {
    prec <- if (!is.null(x$site)) x$site$precedence else default_precedence
    pick <- function(set) {
      # pres is a concatenated digit string (e.g. "19"), one character per state
      if (is.na(set) || !nzchar(set)) return("")
      parts <- strsplit(set, "")[[1]]
      hit <- prec[prec %in% parts]
      if (length(hit)) hit[1] else parts[1]
    }
    raw_label <- vapply(seq_len(nrow(g)), function(i) pick(g$pres[i]), "")
  }

  tab <- tapply(g$weight, list(g$code, raw_label), sum)
  tab[is.na(tab)] <- 0
  tab
}
