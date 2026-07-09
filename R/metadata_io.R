#' Extract sample metadata from a site or folder of YAML files
#'
#' Creates a data frame with one row per sample, containing all metadata
#' fields found in the loaded samples. The output matches the CSV format
#' accepted by the `metadata` argument of [read_site()], making this the
#' reverse of [set_metadata()]: use it to bootstrap a metadata file from
#' counts that were saved without one.
#'
#' Fields absent from a sample are left `NA`.
#'
#' @param x A `pollen_site` object, or a character path to a folder containing
#'   `.yaml`/`.yml`/`.cnt` count files. If a path is given, [read_site()] is
#'   called internally.
#' @param file Optional path to a `.csv` file to write. If `NULL` (default)
#'   the data frame is returned but not written.
#' @return A data frame with columns: `sample_name`, `depth_top`,
#'   `depth_bottom`, `age_top`, `age_bottom`, `sample_quantity`, `units`,
#'   `spike_tablets`, `spike_density`, `spike_units`, `conc_method`,
#'   `title`, `source_file`.
#' @seealso [set_metadata()], [read_site()]
#' @export
extract_metadata <- function(x, file = NULL) {
  if (is.character(x)) {
    if (length(x) != 1L || !dir.exists(x))
      stop("`x` must be a `pollen_site` object or a path to an existing folder.")
    x <- read_site(x)
  }
  if (!inherits(x, "pollen_site"))
    stop("`x` must be a `pollen_site` object or a folder path.")

  samples <- x$samples
  if (!length(samples)) {
    return(data.frame(
      sample_name     = character(0),
      depth_top       = numeric(0),
      depth_bottom    = numeric(0),
      age_top         = numeric(0),
      age_bottom      = numeric(0),
      sample_quantity = numeric(0),
      units           = character(0),
      spike_tablets   = numeric(0),
      spike_density   = numeric(0),
      spike_units     = character(0),
      conc_method     = character(0),
      title           = character(0),
      source_file     = character(0),
      stringsAsFactors = FALSE
    ))
  }

  .pull <- function(m, field, default = NA) {
    v <- m[[field]]
    if (is.null(v) || (length(v) == 1L && is.na(v))) default else v
  }

  rows <- lapply(samples, function(s) {
    m <- s$meta
    data.frame(
      sample_name     = .pull(m, "sample_name",     NA_character_),
      depth_top       = suppressWarnings(as.numeric(.pull(m, "depth_top",      NA_real_))),
      depth_bottom    = suppressWarnings(as.numeric(.pull(m, "depth_bottom",   NA_real_))),
      age_top         = suppressWarnings(as.numeric(.pull(m, "age_top",        NA_real_))),
      age_bottom      = suppressWarnings(as.numeric(.pull(m, "age_bottom",     NA_real_))),
      sample_quantity = suppressWarnings(as.numeric(.pull(m, "sample_quantity", NA_real_))),
      units           = .pull(m, "units",           NA_character_),
      spike_tablets   = suppressWarnings(as.numeric(.pull(m, "spike_tablets",  NA_real_))),
      spike_density   = suppressWarnings(as.numeric(.pull(m, "spike_density",  NA_real_))),
      spike_units     = .pull(m, "spike_units",     NA_character_),
      conc_method     = .pull(m, "conc_method",     NA_character_),
      title           = .pull(m, "title",           NA_character_),
      source_file     = .pull(m, "source_file",     NA_character_),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  if (!is.null(file)) {
    if (!grepl("\\.csv$", file, ignore.case = TRUE))
      file <- paste0(file, ".csv")
    write.csv(out, file, row.names = FALSE)
    message("Metadata written to: ", file)
  }

  out
}
