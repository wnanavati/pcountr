# Deprecated — functionality moved to R/site_matrix.R (v0.5.0).
# as_rioja() is kept as a thin wrapper so existing scripts continue to work.

#' @rdname site_matrix
#' @export
as_rioja <- function(site, groups = NULL,
                     taxon_label = c("name", "alias", "code"),
                     min_present = 0L) {
  .Deprecated("site_matrix",
              msg = paste0("`as_rioja()` was renamed to `site_matrix()` in ",
                           "pcountr v0.5.0. Please update your code."))
  site_matrix(site, groups = groups,
              taxon_label = match.arg(taxon_label),
              min_present = min_present)
}
