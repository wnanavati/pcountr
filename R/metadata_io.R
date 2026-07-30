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


#' Apply an edited metadata CSV back to a loaded site
#'
#' Reads the CSV produced by [extract_metadata()], matches each row to a
#' sample in the site, applies every non-NA column via [set_metadata()], and
#' optionally writes the updated samples back to their source YAML files.
#' This makes `extract_metadata()` + edit + `apply_metadata()` a complete
#' round-trip edit workflow for any metadata field.
#'
#' @section Row matching:
#' Rows are matched to samples first by `source_file` (exact path stored in
#' `meta$source_file`), then by `sample_name` for rows where `source_file` is
#' absent or does not match any sample. Rows that cannot be matched by either
#' key produce a warning and are skipped.
#'
#' @section Columns applied:
#' All editable columns present in the CSV are applied when non-NA:
#' `depth_top`, `depth_bottom`, `age_top`, `age_bottom`, `sample_name`,
#' `sample_quantity`, `units`, `spike_tablets`, `spike_density`,
#' `spike_units`, `conc_method`, `title`. The `source_file` column is used
#' for matching only and is never written back.
#'
#' @param site A `pollen_site` with samples loaded.
#' @param csv Path to a CSV file (as produced by [extract_metadata()]), or a
#'   data frame with the same column structure.
#' @param write If `TRUE` (default), write each modified sample back to its
#'   source YAML file. Samples without a resolvable YAML path are updated in
#'   memory only (a message is emitted).
#' @return The updated `pollen_site` (invisibly).
#' @seealso [extract_metadata()], [set_metadata()]
#' @export
apply_metadata <- function(site, csv, write = TRUE) {
  stopifnot(inherits(site, "pollen_site"))

  csv_dir <- NULL   # used to resolve bare source_file names
  df <- if (is.character(csv)) {
    if (length(csv) != 1L || !file.exists(csv))
      stop("File not found: ", csv)
    csv_dir <- dirname(normalizePath(csv, winslash = "/", mustWork = FALSE))
    read.csv(csv, stringsAsFactors = FALSE, check.names = FALSE)
  } else if (is.data.frame(csv)) {
    csv
  } else {
    stop("`csv` must be a file path or a data frame.")
  }

  # Build lookup tables: source_file -> key, sample_name -> key
  src_map  <- character(0)
  name_map <- character(0)
  for (k in names(site$samples)) {
    sf <- site$samples[[k]]$meta$source_file
    sn <- site$samples[[k]]$meta$sample_name
    if (!is.null(sf) && length(sf) == 1L && !is.na(sf) && nzchar(sf))
      src_map[[sf]] <- k
    if (!is.null(sn) && length(sn) == 1L && !is.na(sn) && nzchar(sn))
      name_map[[sn]] <- k
  }

  modified <- character(0)

  for (i in seq_len(nrow(df))) {
    row <- df[i, , drop = FALSE]

    # --- match row to sample key -------------------------------------------
    key      <- NA_character_
    sf_row   <- .ameta_chr(row, "source_file")
    if (!is.na(sf_row) && sf_row %in% names(src_map))
      key <- src_map[[sf_row]]
    if (is.na(key)) {
      sn_row <- .ameta_chr(row, "sample_name")
      if (!is.na(sn_row) && sn_row %in% names(name_map))
        key <- name_map[[sn_row]]
    }
    if (is.na(key)) {
      warning("Row ", i, " could not be matched to any sample ",
              "(no source_file or sample_name match). Skipped.",
              call. = FALSE)
      next
    }

    # --- build set_metadata() argument list --------------------------------
    args <- list(site = site, sample = key)

    .add_num <- function(col, arg = col) {
      v <- .ameta_num(row, col)
      if (!is.na(v)) args[[arg]] <<- v
    }
    .add_chr <- function(col, arg = col) {
      v <- .ameta_chr(row, col)
      if (!is.na(v)) args[[arg]] <<- v
    }

    .add_num("depth_top")
    .add_num("depth_bottom")
    .add_num("age_top")
    .add_num("age_bottom")
    .add_chr("sample_name")
    .add_num("sample_quantity")
    .add_chr("units",        "sample_units")
    .add_num("spike_tablets")
    .add_num("spike_density")
    .add_chr("spike_units")
    .add_chr("conc_method")
    .add_chr("title")

    site     <- do.call(set_metadata, args)
    modified <- c(modified, key)
  }

  # --- write modified samples back to YAML ----------------------------------
  if (write && length(modified)) {
    for (k in unique(modified)) {
      src <- site$samples[[k]]$meta$source_file
      if (is.null(src) || is.na(src) || !nzchar(src)) {
        message("'", k, "': no source_file — updated in memory only.")
        next
      }
      if (!grepl("\\.(yaml|yml)$", src, ignore.case = TRUE)) {
        message("'", k, "': source_file is not a YAML — updated in memory only.")
        next
      }
      # Resolve a bare filename against the CSV's directory as a fallback.
      if (!file.exists(src) && !is.null(csv_dir)) {
        candidate <- file.path(csv_dir, basename(src))
        if (file.exists(candidate)) src <- candidate
      }
      write_pollen_count(site$samples[[k]], src)
      message("Saved: ", src)
    }
  }

  invisible(site)
}


# --- internal helpers for apply_metadata() ----------------------------------

.ameta_num <- function(row, col) {
  if (!col %in% names(row)) return(NA_real_)
  v <- suppressWarnings(as.numeric(row[[col]][[1L]]))
  if (is.null(v) || length(v) == 0L || is.na(v)) NA_real_ else v
}

.ameta_chr <- function(row, col) {
  if (!col %in% names(row)) return(NA_character_)
  v <- row[[col]][[1L]]
  if (is.null(v) || length(v) == 0L) return(NA_character_)
  v <- trimws(as.character(v))
  if (is.na(v) || !nzchar(v)) NA_character_ else v
}
