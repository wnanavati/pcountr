#' Construct a pollen_count object
#'
#' The core per-sample object. Stores count entries in counting order (the
#' `grains` data frame, which keeps its historical name), the tracer-spike
#' total, traverse labels, remarks, the full ordered event list, and
#' sample-level metadata including depth and (optional) age.
#'
#' Depth and age are *not* present in legacy `.CNT` files and must be supplied
#' by the analyst (here, or later via direct assignment). Age is only needed for
#' accumulation-rate arithmetic and may be left `NA`.
#'
#' @param grains Data frame of per-entry records (see [read_cnt()]).
#' @param spike_n Number of tracer microspheres counted.
#' @param traverses Character vector of traverse labels, in order.
#' @param remarks List of inline remarks.
#' @param events Ordered list of all count events.
#' @param sample_quantity Quantity of sediment processed.
#' @param units Unit of `sample_quantity` (`"ml"` or `"g"`).
#' @param spike_tablets,spike_density Quantity of spike added and microspheres
#'   per unit (per tablet, per ml, or per g depending on `spike_units`).
#' @param spike_units Units of the spike added: `"tablets"`, `"ml"`, or `"g"`.
#' @param pollen_sum_groups Group codes forming the basic count sum,
#'   \eqn{\Sigma P}{Sigma P}. Keeps its historical name for backward
#'   compatibility.
#' @param depth_top,depth_bottom Sample depths (analyst-supplied).
#' @param age_top,age_bottom Sample ages in years BP (optional, analyst-supplied;
#'   present = 1950 CE).
#' @param sample_name Analyst-assigned sample label (e.g. `"KF24sh#001"`).
#' @param dic_path Full path to the dictionary file used for this count
#'   (stored so the counting app can auto-reload it on resume).
#' @param slide,title,source_file Provenance metadata.
#' @param conc_method Concentration calculation method: `"spike"` (tracer
#'   equation, default), `"volumetric"` (counts divided by sample quantity),
#'   or `"none"` (no concentration computed).
#' @param latitude,longitude,elevation,collection_date,device,event_label
#'   Georeferencing and provenance for this sample (see [pollen_site()]).
#'   Recorded per sample rather than per site: a folder may hold one core at
#'   a single position, or surface samples collected across a region.
#'   [read_site()] summarizes them onto the site.
#' @param created ISO timestamp of when this count was first written. Left
#'   `NA` for a new count: [write_pollen_count()] stamps it on the first
#'   write and preserves it on every write after, so it records when the
#'   sample was started rather than when it was last saved.
#' @param use_pres Logical; `TRUE` (default) means entries carry preservation
#'   codes. `FALSE` means no preservation digit was recorded.
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
                         conc_method = "spike",
                         use_pres = TRUE,
                         latitude = NA_real_,
                         longitude = NA_real_,
                         elevation = NA_real_,
                         collection_date = NA_character_,
                         device = NA_character_,
                         event_label = NA_character_,
                         created = NA_character_,
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
        source_file = source_file,
        conc_method = conc_method,
        use_pres = use_pres,
        # Site-level provenance. Stored per sample because the YAML format is
        # one file per sample and has no site-level block; read_site()
        # summarizes it onto the site: the common value where samples agree,
        # NA plus a distinct count where they legitimately differ.
        latitude = latitude,
        longitude = longitude,
        elevation = elevation,
        collection_date = collection_date,
        device = device,
        event_label = event_label,
        # When this count was first written. Carried through reads and writes
        # unchanged, so it records when the sample was started rather than
        # when it was last touched; `last_modified` in the YAML covers that.
        created = created
      ),
      site = site
    ),
    class = "pollen_count"
  )
}

#' @export
print.pollen_count <- function(x, ...) {
  cat("<pollen_count>", x$meta$title %||% x$meta$source_file %||% "(untitled)", "\n")
  cat("  entries:", nrow(x$grains), " spike:", x$spike_n,
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

