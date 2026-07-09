#' Convert a loaded pollen site to a wide taxa matrix
#'
#' Returns a list of parallel matrices and vectors suitable for downstream
#' analysis and plotting (e.g. `rioja::strat.plot()`). All non-special taxa
#' present in at least `min_present` samples are included.
#'
#' Percentages (`TaxaPerc`) are computed as:
#' \deqn{p_{ij} = 100 \times w_{ij} / D_i}
#' where \eqn{w_{ij}} is the weighted count of taxon \eqn{j} in sample
#' \eqn{i} and \eqn{D_i} is the sum of all grain weights in `groups`.
#'
#' Concentrations (`TaxaConc`) use the Stockmarr equation per taxon:
#' \deqn{c_{ij} = \frac{w_{ij}}{S_i} \times \frac{A_i \times \rho_i}{V_i}}
#' where \eqn{S_i} is spike counted, \eqn{A_i} is spike tablets/volume added,
#' \eqn{\rho_i} is spike concentration, and \eqn{V_i} is sample size.
#' Returns `NA` for any sample missing required inputs.
#'
#' Accumulation rates (`TaxaAccRate`) are concentration divided by linear
#' deposition time: \eqn{(AgeBot - AgeTop) / (DepBot - DepTop)}.
#' Returns `NA` for any sample missing depth or age intervals.
#'
#' Samples lacking a `depth_top` value are excluded; a message lists them.
#'
#' @param site A `pollen_site` with a `samples` list (from [read_site()]).
#' @param groups Character vector of dictionary group codes forming the
#'   percentage denominator (e.g. `c("A","B","F")`). Defaults to
#'   `site$pollen_sum`.
#' @param taxon_label Dictionary field for column names: `"name"` (default),
#'   `"alias"`, or `"code"`. When `"alias"` is chosen and a taxon has no
#'   alias, the code is used as fallback.
#' @param min_present Minimum number of samples a taxon must appear in (with
#'   non-zero percentage) to be included. Default `0` keeps all taxa.
#' @return A named list. Vectors are parallel to matrix rows (one entry per
#'   sample, ordered shallowest first):
#'   \describe{
#'     \item{`DepTop`}{Top-of-interval depth (cm).}
#'     \item{`DepBot`}{Bottom-of-interval depth (cm); `NA` where not recorded.}
#'     \item{`AgeTop`}{Top-of-interval age (years BP); `NA` where not recorded.}
#'     \item{`AgeBot`}{Bottom-of-interval age (years BP); `NA` where not recorded.}
#'     \item{`SampleSize`}{Sample quantity (ml or g).}
#'     \item{`SpikeCount`}{Number of spike grains counted.}
#'     \item{`SpikeAdded`}{Spike tablets or volume added to the sample.}
#'     \item{`SpikeConc`}{Concentration of the spike (grains per tablet or per ml).}
#'     \item{`TaxaCount`}{Raw weighted counts matrix (samples x taxa).}
#'     \item{`TaxaPerc`}{Percentage matrix (samples x taxa).}
#'     \item{`TaxaConc`}{Concentration matrix (samples x taxa); `NA` cells
#'       where required inputs are missing.}
#'     \item{`TaxaAccRate`}{Accumulation rate matrix (samples x taxa); `NA`
#'       cells where required inputs are missing.}
#'     \item{`groups_used`}{Group codes used as the percentage denominator.}
#'   }
#' @seealso [read_site()], [set_metadata()], [write_tlx()]
#' @export
site_matrix <- function(site,
                        groups      = NULL,
                        taxon_label = c("name", "alias", "code"),
                        min_present = 0L) {

  stopifnot(inherits(site, "pollen_site"))
  taxon_label <- match.arg(taxon_label)

  if (is.null(site$samples) || !length(site$samples))
    stop("`site` has no samples loaded. Run read_site() first.")

  groups <- .resolve_groups(groups, site)
  dic    <- site$dictionary

  # Samples with a depth ---------------------------------------------------
  has_depth <- .has_depth_top(site$samples)
  if (any(!has_depth))
    message("Excluding ", sum(!has_depth),
            " sample(s) with no depth_top: ",
            paste(names(site$samples)[!has_depth], collapse = ", "))

  depth_samples <- site$samples[has_depth]
  if (!length(depth_samples))
    stop("No samples with a depth_top value. Use set_metadata() to assign depths.")

  # Per-sample scalar fields -----------------------------------------------
  DepTop     <- .meta_numeric(depth_samples, "depth_top")
  DepBot     <- .meta_numeric(depth_samples, "depth_bottom")
  AgeTop     <- .meta_numeric(depth_samples, "age_top")
  AgeBot     <- .meta_numeric(depth_samples, "age_bottom")
  SampleSize <- .meta_numeric(depth_samples, "sample_quantity")
  SpikeCount <- .sample_numeric(depth_samples, "spike_n")
  SpikeAdded <- .meta_numeric(depth_samples, "spike_tablets")
  SpikeConc  <- .meta_numeric(depth_samples, "spike_density")

  all_codes <- .site_codes(depth_samples, dic)
  if (!length(all_codes))
    stop("No non-special taxon codes found in the loaded samples.")

  # Build count and percentage matrices ------------------------------------
  count_mat <- .build_count_matrix(depth_samples, all_codes)
  pct_mat   <- .build_pct_matrix(depth_samples, all_codes, groups, dic)

  # min_present filter (same columns for both matrices) --------------------
  if (min_present > 0L) {
    present <- colSums(pct_mat > 0, na.rm = TRUE)
    keep    <- present >= min_present
    if (!any(keep))
      stop("No taxa remain after applying min_present = ", min_present, ".")
    count_mat <- count_mat[, keep, drop = FALSE]
    pct_mat   <- pct_mat[,   keep, drop = FALSE]
  }

  # Concentration matrix ---------------------------------------------------
  # Per-sample concentration factor respects conc_method stored in each sample.
  #   spike:      cf = (SpikeAdded * SpikeConc) / (SpikeCount * SampleSize)
  #   volumetric: cf = 1 / SampleSize
  #   none:       cf = NA
  conc_method_vec <- vapply(depth_samples,
                            function(s) s$meta$conc_method %||% "spike", "")
  cf_spike <- (SpikeAdded * SpikeConc) / (SpikeCount * SampleSize)
  cf_vol   <- 1 / SampleSize
  cf <- ifelse(conc_method_vec == "volumetric", cf_vol,
        ifelse(conc_method_vec == "none",        NA_real_,
               cf_spike))
  cf[!is.finite(cf) | cf <= 0] <- NA_real_
  conc_mat <- sweep(count_mat, 1, cf, "*")

  # Accumulation rate matrix -----------------------------------------------
  # dep_time[i] = (AgeBot[i] - AgeTop[i]) / (DepBot[i] - DepTop[i])
  dep_time <- (AgeBot - AgeTop) / (DepBot - DepTop)
  dep_time[!is.finite(dep_time) | dep_time <= 0] <- NA_real_
  accrate_mat <- sweep(conc_mat, 1, dep_time, "/")

  # Apply taxon labels to all matrices -------------------------------------
  col_labels <- .taxon_labels(colnames(count_mat), dic, taxon_label)
  colnames(count_mat)   <- col_labels
  colnames(pct_mat)     <- col_labels
  colnames(conc_mat)    <- col_labels
  colnames(accrate_mat) <- col_labels

  list(DepTop      = DepTop,
       DepBot      = DepBot,
       AgeTop      = AgeTop,
       AgeBot      = AgeBot,
       SampleSize  = SampleSize,
       SpikeCount  = SpikeCount,
       SpikeAdded  = SpikeAdded,
       SpikeConc   = SpikeConc,
       TaxaCount   = count_mat,
       TaxaPerc    = pct_mat,
       TaxaConc    = conc_mat,
       TaxaAccRate = accrate_mat,
       groups_used = groups)
}


# === shared internal helpers ================================================

.resolve_groups <- function(groups, site) {
  if (!is.null(groups)) return(groups)
  g <- site$pollen_sum
  if (!length(g)) stop("`groups` is empty. Supply group codes for the denominator.")
  g
}

.has_depth_top <- function(samples) {
  vapply(samples, function(s) {
    v <- s$meta$depth_top
    !is.null(v) && length(v) == 1L && !is.na(v)
  }, FALSE)
}

# Extract a named numeric vector of one $meta field across all samples.
.meta_numeric <- function(samples, field) {
  vapply(samples, function(s) {
    v <- s$meta[[field]]
    if (is.null(v) || length(v) != 1L) NA_real_ else as.numeric(v)
  }, NA_real_)
}

# Extract a named numeric vector of one top-level field across all samples.
.sample_numeric <- function(samples, field) {
  vapply(samples, function(s) {
    v <- s[[field]]
    if (is.null(v) || length(v) != 1L) NA_real_ else as.numeric(v)
  }, NA_real_)
}

# Sorted non-special codes present in a list of depth-bearing samples.
.site_codes <- function(depth_samples, dic) {
  dic_nonspc <- dic[!dic$is_special, , drop = FALSE]
  codes <- unique(unlist(lapply(depth_samples, function(s) {
    s$grains$code[!grepl("^[#.]", s$grains$code)]
  })))
  sort(intersect(codes, dic_nonspc$code))
}

# Compute one raw-count row for a grains data frame.
# Returns a named numeric vector over `all_codes`.
.count_row <- function(grains, all_codes) {
  row   <- setNames(rep(0, length(all_codes)), all_codes)
  g_sub <- grains[grains$code %in% all_codes, , drop = FALSE]
  if (nrow(g_sub) == 0L) return(row)
  tx   <- tapply(g_sub$weight, g_sub$code, sum)
  hits <- intersect(names(tx), all_codes)
  row[hits] <- as.numeric(tx[hits])
  row
}

# Compute one percentage row for a grains data frame.
# Returns a named numeric vector over `all_codes`.
.pct_row <- function(grains, all_codes, groups, dic, label = "") {
  grp   <- dic$group[match(grains$code, dic$code)]
  denom <- sum(grains$weight[!is.na(grp) & grp %in% groups], na.rm = TRUE)

  if (is.na(denom) || denom == 0) {
    lbl <- if (nzchar(label)) paste0(label, ": ") else ""
    warning(lbl, "denominator is zero for groups ",
            paste(groups, collapse = "+"), "; row set to NA.", call. = FALSE)
    return(setNames(rep(NA_real_, length(all_codes)), all_codes))
  }

  row <- setNames(rep(0, length(all_codes)), all_codes)
  tx  <- tapply(grains$weight[grains$code %in% all_codes],
                grains$code[grains$code %in% all_codes], sum)
  hits      <- intersect(names(tx), all_codes)
  row[hits] <- as.numeric(tx[hits]) / denom * 100
  row
}

# Build the full raw-count matrix for a list of samples over `all_codes`.
.build_count_matrix <- function(depth_samples, all_codes) {
  mat <- matrix(0, nrow = length(depth_samples), ncol = length(all_codes),
                dimnames = list(names(depth_samples), all_codes))
  for (i in seq_along(depth_samples))
    mat[i, ] <- .count_row(depth_samples[[i]]$grains, all_codes)
  mat
}

# Build the full percentage matrix for a list of samples over `all_codes`.
.build_pct_matrix <- function(depth_samples, all_codes, groups, dic) {
  mat <- matrix(0, nrow = length(depth_samples), ncol = length(all_codes),
                dimnames = list(names(depth_samples), all_codes))
  for (i in seq_along(depth_samples))
    mat[i, ] <- .pct_row(depth_samples[[i]]$grains, all_codes, groups, dic,
                         label = names(depth_samples)[i])
  mat
}

# Return labels for a vector of codes from the dictionary.
.taxon_labels <- function(codes, dic, field) {
  if (field == "code") return(codes)
  idx <- match(codes, dic$code)
  raw <- dic[[field]][idx]
  if (field == "alias") {
    empty    <- is.na(raw) | !nzchar(trimws(raw))
    raw[empty] <- codes[empty]
  }
  raw
}
