#' Load an entire site folder of count files
#'
#' Discovers every `.CNT` and `.yaml`/`.yml` file in `folder`, loads them as
#' `pollen_count` objects, optionally attaches depth and age from a metadata
#' sheet, and returns a `pollen_site` with all samples ordered by `depth_top`
#' (samples lacking a depth are appended at the end, unordered).
#'
#' Depth and age are *never required* to load a site. Samples without depths
#' load and compute concentrations exactly as normal; they simply cannot be
#' ordered or plotted by depth until one is supplied.
#'
#' @section Depth and age sources (all optional):
#' \enumerate{
#'   \item Embedded in native `.yaml` files -- the primary route going forward.
#'   \item An optional CSV metadata sheet (`metadata` + `col_map`).
#'   \item Direct assignment with [set_depth()].
#' }
#' When a `.yaml` file already carries a depth value *and* the sheet also
#' provides one for the same sample, the two values must agree. A discrepancy
#' is an error unless `ignore_depth_conflicts = TRUE` (which downgrades it to a
#' warning and keeps the YAML value).
#'
#' @section Metadata sheet:
#' A CSV with one row per sample. Rows are matched to files case-insensitively
#' and without regard to extension (`LMSH001` matches `LMSH001.CNT`,
#' `lmsh001.yaml`, etc.). Columns for sample quantity, units, and spike are
#' ignored -- those are always read from the count file itself.
#'
#' Supply your own column names via `col_map` (see below). When the sheet is
#' provided, folder files with no matching row and sheet rows with no matching
#' file both produce warnings, not errors.
#'
#' Depth intervals must satisfy `depth_top < depth_bottom` (depth increases
#' downcore). Rows where `depth_top >= depth_bottom` are flagged as likely
#' transcription swaps.
#'
#' @param folder Path to a folder containing count files (and optionally a
#'   `.DIC` dictionary).
#' @param dic Path to a `.DIC` file, or a pre-loaded `pollen_dictionary`.
#'   Auto-detected when exactly one `.DIC` exists in `folder`; an error is
#'   raised if zero or more than one are found.
#' @param name Site name. Defaults to the folder's basename.
#' @param metadata Optional path to a CSV metadata sheet.
#' @param col_map Named character vector mapping standard field names to your
#'   sheet's actual column names. Standard names: `file`, `depth_top`,
#'   `depth_bottom`, `age_top`, `age_bottom`. Example:
#'   `col_map = c(file = "Sample_ID", depth_top = "Top_cm",
#'   depth_bottom = "Bot_cm")`. Column matching is case-insensitive.
#' @param ignore_depth_conflicts If `TRUE`, warn instead of error when a
#'   YAML-embedded depth disagrees with the sheet; the YAML value is kept.
#' @param quiet If `TRUE`, suppress per-file anomaly warnings.
#' @return A `pollen_site` with a `samples` list ordered by depth.
#' @export
read_site <- function(folder,
                      dic = NULL,
                      name = basename(folder),
                      metadata = NULL,
                      col_map = NULL,
                      ignore_depth_conflicts = FALSE,
                      quiet = FALSE) {

  # 1. Resolve dictionary -------------------------------------------------
  dic <- .resolve_dic(folder, dic)
  base_site <- pollen_site(name, dic)

  # 2. Parse metadata sheet if provided -----------------------------------
  sheet <- if (!is.null(metadata)) .read_metadata_sheet(metadata, col_map) else NULL

  # 3. Discover count files -----------------------------------------------
  cnt_files  <- list.files(folder, pattern = "\\.CNT$",
                           full.names = TRUE, ignore.case = TRUE)
  yaml_files <- list.files(folder, pattern = "\\.(yaml|yml)$",
                           full.names = TRUE, ignore.case = TRUE)
  all_files  <- c(cnt_files, yaml_files)

  if (!length(all_files)) {
    warning("No .CNT or .yaml/.yml files found in: ", folder, call. = FALSE)
    return(base_site)
  }

  # 4. Cross-match files against sheet ------------------------------------
  if (!is.null(sheet)) .check_sheet_coverage(all_files, sheet)

  # 5. Load each file -----------------------------------------------------
  samples <- vector("list", length(all_files))
  keys    <- character(length(all_files))

  for (i in seq_along(all_files)) {
    f   <- all_files[i]
    ext <- tolower(tools::file_ext(f))
    key <- tools::file_path_sans_ext(basename(f))
    keys[i] <- key

    if (ext == "cnt") {
      cnt <- read_cnt(f, site = base_site, quiet = quiet)
      cnt <- .attach_sheet_depth(cnt, key, sheet)
    } else {
      cnt <- read_pollen_count(f, site = base_site)
      cnt <- .reconcile_yaml_sheet_depth(cnt, key, sheet,
                                         ignore_depth_conflicts)
    }

    samples[[i]] <- cnt
  }

  names(samples) <- keys

  # 6. Order by depth_top; NA-depth samples appended at end ---------------
  samples <- .order_samples(samples)

  # 7. Return pollen_site with samples ------------------------------------
  pollen_site(name, dic,
              pollen_sum   = base_site$pollen_sum,
              preservation = base_site$preservation,
              precedence   = base_site$precedence,
              samples      = samples)
}


#' Set or update metadata for a sample in a loaded site
#'
#' Updates any combination of depth, age, sample identity, sample quantity, and
#' spike fields for a single sample, then re-sorts the site by `depth_top`
#' ascending (NA-depth samples remain at the end). Only arguments that are
#' explicitly supplied overwrite the existing value; omitted arguments leave the
#' current value unchanged.
#'
#' For sites with many samples, fill in the package metadata template and loop
#' over rows (see the template for a ready-to-paste code snippet):
#'
#' ```r
#' file.show(system.file("templates/metadata_template.csv", package = "pcountr"))
#' ```
#'
#' @param site A `pollen_site` with a `samples` list.
#' @param sample The sample to update: a character key (name in
#'   `site$samples`) or an integer index.
#' @param depth_top,depth_bottom Sample interval in cm. When both are supplied,
#'   `depth_top` must be less than `depth_bottom`.
#' @param age_top,age_bottom Ages in calibrated years BP (present = 1950 CE).
#' @param sample_name Analyst-assigned label (e.g. `"KF24sh#001"`).
#' @param sample_quantity Amount of sediment processed (numeric).
#' @param sample_units Units of `sample_quantity`: `"ml"` or `"g"`.
#' @param spike_tablets Quantity of spike added — number of tablets, ml, or g
#'   (interpretation depends on `spike_units`).
#' @param spike_density Microspheres per unit of spike (per tablet, per ml,
#'   or per g).
#' @param spike_units Units of the spike: `"tablets"`, `"ml"`, or `"g"`.
#' @return The updated `pollen_site` (invisibly).
#' @seealso [read_site()] for bulk depth/age assignment via a metadata sheet.
#' @export
set_metadata <- function(site, sample,
                         depth_top       = NULL,
                         depth_bottom    = NULL,
                         age_top         = NULL,
                         age_bottom      = NULL,
                         sample_name     = NULL,
                         sample_quantity = NULL,
                         sample_units    = NULL,
                         spike_tablets   = NULL,
                         spike_density   = NULL,
                         spike_units     = NULL) {
  stopifnot(inherits(site, "pollen_site"))
  if (is.null(site$samples) || !length(site$samples))
    stop("`site` has no samples loaded. Run read_site() first.")

  if (is.character(sample)) {
    if (!sample %in% names(site$samples))
      stop("Sample '", sample, "' not found in site$samples.\n",
           "Available keys: ", paste(names(site$samples), collapse = ", "))
    idx <- which(names(site$samples) == sample)[1L]
  } else {
    idx <- as.integer(sample)
    if (idx < 1L || idx > length(site$samples))
      stop("Sample index ", idx, " out of range (1-",
           length(site$samples), ").")
  }

  # Validate depth interval using final (new-or-existing) values
  final_dt <- depth_top    %||% site$samples[[idx]]$meta$depth_top
  final_db <- depth_bottom %||% site$samples[[idx]]$meta$depth_bottom
  if (!is.null(final_dt) && !is.null(final_db) &&
      !is.na(final_dt)   && !is.na(final_db)   &&
      final_dt >= final_db)
    stop("depth_top (", final_dt, ") must be less than depth_bottom (",
         final_db, ").")

  m <- site$samples[[idx]]$meta
  if (!is.null(depth_top))       m$depth_top       <- depth_top
  if (!is.null(depth_bottom))    m$depth_bottom     <- depth_bottom
  if (!is.null(age_top))         m$age_top          <- age_top
  if (!is.null(age_bottom))      m$age_bottom       <- age_bottom
  if (!is.null(sample_name))     m$sample_name      <- sample_name
  if (!is.null(sample_quantity)) m$sample_quantity  <- sample_quantity
  if (!is.null(sample_units))    m$units            <- sample_units
  if (!is.null(spike_tablets))   m$spike_tablets    <- spike_tablets
  if (!is.null(spike_density))   m$spike_density    <- spike_density
  if (!is.null(spike_units))     m$spike_units      <- spike_units
  site$samples[[idx]]$meta <- m

  site$samples <- .order_samples(site$samples)
  invisible(site)
}

#' @rdname set_metadata
#' @export
set_depth_age <- function(site, sample, depth_top, depth_bottom,
                          age_top = NA_real_, age_bottom = NA_real_) {
  .Deprecated("set_metadata")
  set_metadata(site, sample,
               depth_top = depth_top, depth_bottom = depth_bottom,
               age_top   = age_top,   age_bottom   = age_bottom)
}

#' @rdname set_metadata
#' @export
set_depth <- function(site, sample, depth_top, depth_bottom,
                      age_top = NA_real_, age_bottom = NA_real_) {
  .Deprecated("set_metadata")
  set_metadata(site, sample,
               depth_top = depth_top, depth_bottom = depth_bottom,
               age_top   = age_top,   age_bottom   = age_bottom)
}


# --- internal helpers -------------------------------------------------------

# Resolve the dictionary: auto-detect a single .DIC, or use the supplied value.
.resolve_dic <- function(folder, dic) {
  if (!is.null(dic)) {
    if (is.character(dic) && length(dic) == 1L) return(read_dic(dic))
    if (inherits(dic, "pollen_dictionary"))       return(dic)
    stop("`dic` must be a path to a .DIC file or a pollen_dictionary object.")
  }
  dics <- list.files(folder, pattern = "\\.DIC$",
                     full.names = TRUE, ignore.case = TRUE)
  if (length(dics) == 0L)
    stop("No .DIC file found in: ", folder,
         "\nPass `dic =` to specify one explicitly.")
  if (length(dics) > 1L)
    stop("Multiple .DIC files found in: ", folder, "\n",
         paste(" ", basename(dics), collapse = "\n"),
         "\nPass `dic =` to choose one.")
  read_dic(dics[1L])
}

# Read and normalise a CSV metadata sheet.
.read_metadata_sheet <- function(path, col_map) {
  df <- tryCatch(
    if (tolower(tools::file_ext(path)) == "csv") {
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
      read.table(path, header = TRUE, sep = "\t",
                 stringsAsFactors = FALSE, check.names = FALSE,
                 quote = "", fill = TRUE)
    },
    error = function(e) stop("Could not read metadata sheet '", path, "': ", e$message)
  )

  # Build standard-name -> user-column-name map
  std <- c(file = "file", depth_top = "depth_top",
           depth_bottom = "depth_bottom",
           age_top = "age_top", age_bottom = "age_bottom")
  if (!is.null(col_map)) {
    bad <- setdiff(names(col_map), names(std))
    if (length(bad))
      warning("col_map names not recognised (ignored): ",
              paste(bad, collapse = ", "), call. = FALSE)
    std[intersect(names(col_map), names(std))] <-
      col_map[intersect(names(col_map), names(std))]
  }

  # Match column names case-insensitively
  df_lower <- tolower(names(df))
  resolved <- vapply(std, function(want) {
    hit <- which(df_lower == tolower(want))
    if (length(hit)) names(df)[hit[1L]] else NA_character_
  }, "")

  if (is.na(resolved["file"]))
    stop("Metadata sheet has no column matching '", std["file"],
         "'. Use `col_map = c(file = ...)` to specify it.")

  # Copy to standard names for internal use
  for (std_nm in names(resolved)) {
    col_nm <- resolved[[std_nm]]
    if (!is.na(col_nm) && col_nm != std_nm)
      df[[std_nm]] <- df[[col_nm]]
  }

  # Validate depth intervals (after renaming so df$depth_top is available)
  if (!is.na(resolved["depth_top"]) && !is.na(resolved["depth_bottom"])) {
    dt <- suppressWarnings(as.numeric(df$depth_top))
    db <- suppressWarnings(as.numeric(df$depth_bottom))
    bad <- which(!is.na(dt) & !is.na(db) & dt >= db)
    if (length(bad))
      warning(sprintf(
        "Metadata sheet: depth_top >= depth_bottom (likely swap) in row(s) %s: %s",
        paste(bad, collapse = ", "),
        paste(sprintf("'%s' (%g >= %g)",
                      df[[resolved["file"]]][bad], dt[bad], db[bad]),
              collapse = "; ")
      ), call. = FALSE)
  }

  # Normalise the file-matching key: lowercase, no extension
  df$.key <- tolower(tools::file_path_sans_ext(as.character(df[[resolved["file"]]])))
  df
}

# Warn about files missing from sheet and sheet rows missing files.
.check_sheet_coverage <- function(files, sheet) {
  file_keys  <- tolower(tools::file_path_sans_ext(basename(files)))
  sheet_keys <- unique(sheet$.key)

  no_sheet <- setdiff(file_keys, sheet_keys)
  no_file  <- setdiff(sheet_keys, file_keys)

  if (length(no_sheet))
    warning("Folder file(s) with no metadata sheet row: ",
            paste(no_sheet, collapse = ", "), call. = FALSE)
  if (length(no_file))
    warning("Metadata sheet row(s) with no matching file: ",
            paste(no_file, collapse = ", "), call. = FALSE)
}

# Look up a sheet row by normalised file key.
.sheet_row <- function(key, sheet) {
  if (is.null(sheet)) return(NULL)
  hit <- which(sheet$.key == tolower(key))
  if (!length(hit)) return(NULL)
  sheet[hit[1L], , drop = FALSE]
}

# Attach depth/age from a sheet row to a CNT-derived pollen_count.
.attach_sheet_depth <- function(cnt, key, sheet) {
  row <- .sheet_row(key, sheet)
  if (is.null(row)) return(cnt)
  if ("depth_top"    %in% names(row)) cnt$meta$depth_top    <- .as_num(row$depth_top)
  if ("depth_bottom" %in% names(row)) cnt$meta$depth_bottom <- .as_num(row$depth_bottom)
  if ("age_top"      %in% names(row)) cnt$meta$age_top      <- .as_num(row$age_top)
  if ("age_bottom"   %in% names(row)) cnt$meta$age_bottom   <- .as_num(row$age_bottom)
  cnt
}

# For YAML files: check sheet values against embedded values; apply sheet
# values only when the YAML slot is NA.
.reconcile_yaml_sheet_depth <- function(cnt, key, sheet, ignore_conflicts) {
  row <- .sheet_row(key, sheet)
  if (is.null(row)) return(cnt)

  fields <- c("depth_top", "depth_bottom", "age_top", "age_bottom")
  for (fld in fields) {
    yaml_val  <- cnt$meta[[fld]]
    sheet_val <- if (fld %in% names(row)) .as_num(row[[fld]]) else NA_real_
    if (is.null(yaml_val)) yaml_val <- NA_real_

    if (!is.na(yaml_val) && !is.na(sheet_val)) {
      if (!isTRUE(all.equal(as.numeric(yaml_val), as.numeric(sheet_val),
                            tolerance = 1e-9))) {
        msg <- sprintf(
          "%s: %s conflict -- YAML has %g, sheet has %g.",
          key, fld, as.numeric(yaml_val), as.numeric(sheet_val)
        )
        if (ignore_conflicts) warning(msg, call. = FALSE) else stop(msg)
      }
    } else if (is.na(yaml_val) && !is.na(sheet_val)) {
      cnt$meta[[fld]] <- sheet_val
    }
  }
  cnt
}

# Order a named list of pollen_counts by depth_top ascending; NA at end.
.order_samples <- function(samples) {
  tops <- vapply(samples, function(s) {
    v <- s$meta$depth_top
    if (is.null(v) || length(v) == 0L || (length(v) == 1L && is.na(v)))
      NA_real_ else as.numeric(v)
  }, NA_real_)

  has_depth <- !is.na(tops)
  depth_order <- order(tops[has_depth])
  depth_names <- names(samples)[has_depth][depth_order]
  nodep_names <- names(samples)[!has_depth]

  samples[c(depth_names, nodep_names)]
}

.as_num <- function(x) suppressWarnings(as.numeric(x))
