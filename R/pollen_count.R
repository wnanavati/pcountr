#' Construct a pollen_count object
#'
#' The core per-sample object. Stores grains in counting order (a data frame),
#' the tracer-spike total, traverse labels, remarks, the full ordered event
#' list, and sample-level metadata including depth and (optional) age.
#'
#' Depth and age are *not* present in legacy `.CNT` files and must be supplied
#' by the analyst (here, or later via direct assignment). Age is only needed for
#' accumulation-rate arithmetic and may be left `NA`.
#'
#' @param grains Data frame of per-grain records (see [read_cnt()]).
#' @param spike_n Number of tracer microspheres counted.
#' @param traverses Character vector of traverse labels, in order.
#' @param remarks List of inline remarks.
#' @param events Ordered list of all count events.
#' @param sample_quantity Quantity of sediment processed.
#' @param units Unit of `sample_quantity` (`"ml"` or `"g"`).
#' @param spike_tablets,spike_density Quantity of spike added and microspheres
#'   per unit (per tablet, per ml, or per g depending on `spike_units`).
#' @param spike_units Units of the spike added: `"tablets"`, `"ml"`, or `"g"`.
#' @param pollen_sum_groups Group codes forming the basic pollen sum.
#' @param depth_top,depth_bottom Sample depths (analyst-supplied).
#' @param age_top,age_bottom Sample ages in years BP (optional, analyst-supplied;
#'   present = 1950 CE).
#' @param sample_name Analyst-assigned sample label (e.g. `"KF24sh#001"`).
#' @param dic_path Full path to the dictionary file used for this count
#'   (stored so the counting app can auto-reload it on resume).
#' @param slide,title,source_file Provenance metadata.
#' @param site Optional [pollen_site()].
#' @export
pollen_count <- function(grains,
                         spike_n,
                         traverses = character(0),
                         remarks = list(),
                         events = list(),
                         sample_quantity = NA_real_,
                         units = NA_character_,
                         spike_tablets = NA_real_,
                         spike_density = NA_real_,
                         spike_units = NA_character_,
                         pollen_sum_groups = c("A", "B", "F"),
                         depth_top = NA_real_,
                         depth_bottom = NA_real_,
                         age_top = NA_real_,
                         age_bottom = NA_real_,
                         sample_name = NA_character_,
                         dic_path = NA_character_,
                         slide = NA_character_,
                         title = NA_character_,
                         source_file = NA_character_,
                         site = NULL) {
  structure(
    list(
      grains = grains,
      spike_n = spike_n,
      traverses = traverses,
      remarks = remarks,
      events = events,
      meta = list(
        sample_quantity = sample_quantity,
        units = units,
        spike_tablets = spike_tablets,
        spike_density = spike_density,
        spike_units   = spike_units,
        pollen_sum_groups = pollen_sum_groups,
        depth_top = depth_top,
        depth_bottom = depth_bottom,
        age_top = age_top,
        age_bottom = age_bottom,
        sample_name = sample_name,
        dic_path = dic_path,
        slide = slide,
        title = title,
        source_file = source_file
      ),
      site = site
    ),
    class = "pollen_count"
  )
}

#' @export
print.pollen_count <- function(x, ...) {
  cat("<pollen_count>", x$meta$title %||% x$meta$source_file %||% "(untitled)", "\n")
  cat("  grains:", nrow(x$grains), " spike:", x$spike_n,
      " traverses:", length(x$traverses), "\n")
  cat("  sample:", x$meta$sample_quantity, x$meta$units,
      "| spike:", x$meta$spike_tablets, "tablets x",
      x$meta$spike_density, "\n")
  d <- x$meta
  if (!is.na(d$depth_top) || !is.na(d$depth_bottom))
    cat("  depth:", d$depth_top, "-", d$depth_bottom, "\n")
  an <- attr(x, "anomalies")
  if (!is.null(an) && nrow(an)) cat("  anomalies:", nrow(an), "\n")
  invisible(x)
}

#' @export
summary.pollen_count <- function(object, ...) {
  count_metrics(object)
}

