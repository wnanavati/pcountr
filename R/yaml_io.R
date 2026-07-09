#' Write a pollen_count to the native YAML format
#'
#' Serialises a sample to a single self-contained YAML file: scalar metadata
#' (site, depths, ages, sample quantity and unit, spike) plus the full per-grain
#' sequence in counting order, with traverse labels and remarks interleaved by
#' position. This is the modern replacement for the legacy `.CNT` format.
#'
#' @param x A `pollen_count`.
#' @param path Output path (`.yaml`/`.yml`).
#' @return `path`, invisibly.
#' @export
write_pollen_count <- function(x, path) {
  stopifnot(inherits(x, "pollen_count"))
  g <- x$grains

  # Legacy fields kept for human readability and external tool compatibility.
  grain_list <- lapply(seq_len(nrow(g)), function(i) {
    list(
      order        = i,
      code         = g$code[i],
      preservation = g$pres[i],
      weight       = g$weight[i],
      traverse     = if (is.na(g$traverse[i])) NULL else g$traverse[i]
    )
  })
  remark_list <- lapply(x$remarks, function(r) {
    list(text     = r$text,
         position = r$position,
         traverse = if (is.null(r$traverse) || is.na(r$traverse)) NULL else r$traverse)
  })

  # Full event stream — enables lossless resume (spike positions preserved).
  .trav_or_null <- function(e)
    if (is.null(e$traverse) || is.na(e$traverse)) NULL else e$traverse

  event_list <- lapply(x$events, function(e) {
    base <- list(type = e$type, position = e$position)
    switch(e$type,
      grain      = c(base, list(code     = e$code,
                                base     = e$base,
                                pres     = e$pres,
                                weight   = e$weight,
                                hidden   = isTRUE(e$hidden),
                                traverse = .trav_or_null(e),
                                anomaly  = isTRUE(e$anomaly))),
      spike      = c(base, list(traverse = .trav_or_null(e))),
      traverse   = c(base, list(label    = e$label)),
      remark     = c(base, list(text     = e$text,
                                traverse = .trav_or_null(e))),
      slide_desc = c(base, list(text     = e$text)),
      base   # unknown type: position + type only
    )
  })

  doc <- list(
    format            = "pcountr/pollen_count",
    format_version    = 2L,
    site              = if (!is.null(x$site)) x$site$name else NULL,
    title             = .na_null(x$meta$title),
    source_file       = .na_null(x$meta$source_file),
    slide             = .na_null(x$meta$slide),
    sample_name       = .na_null(x$meta$sample_name),
    dic_path          = .na_null(x$meta$dic_path),
    depth_top         = .na_null(x$meta$depth_top),
    depth_bottom      = .na_null(x$meta$depth_bottom),
    age_top           = .na_null(x$meta$age_top),
    age_bottom        = .na_null(x$meta$age_bottom),
    sample_quantity   = .na_null(x$meta$sample_quantity),
    units             = .na_null(x$meta$units),
    spike_tablets     = .na_null(x$meta$spike_tablets),
    spike_density     = .na_null(x$meta$spike_density),
    spike_units       = .na_null(x$meta$spike_units),
    spike_counted     = x$spike_n,
    conc_method       = .na_null(x$meta$conc_method),
    use_pres          = if (isFALSE(x$meta$use_pres)) FALSE else NULL,
    pollen_sum_groups = x$meta$pollen_sum_groups,
    traverses         = x$traverses,
    grains            = grain_list,
    remarks           = remark_list,
    events            = if (length(event_list)) event_list else NULL
  )
  writeLines(.emit_yaml(doc), path)
  invisible(path)
}

# Prefer the real yaml package; fall back to a minimal emitter for our flat doc.
.emit_yaml <- function(doc) {
  if (requireNamespace("yaml", quietly = TRUE)) return(yaml::as.yaml(doc))
  .minimal_yaml(doc)
}

.minimal_yaml <- function(x, indent = 0) {
  pad <- strrep("  ", indent)
  scalar <- function(v) {
    if (is.null(v)) return("null")
    if (is.logical(v)) return(if (v) "true" else "false")
    if (is.character(v)) return(paste0('"', gsub('"', '\\\\"', v), '"'))
    format(v, trim = TRUE)
  }
  out <- character(0)
  for (nm in names(x)) {
    v <- x[[nm]]
    if (is.null(v) || (length(v) == 1 && is.atomic(v))) {
      out <- c(out, paste0(pad, nm, ": ", scalar(v)))
    } else if (is.atomic(v)) {
      out <- c(out, paste0(pad, nm, ":"))
      for (e in v) out <- c(out, paste0(pad, "  - ", scalar(e)))
    } else if (is.list(v)) {
      out <- c(out, paste0(pad, nm, ":"))
      for (item in v) {
        if (is.list(item)) {
          first <- TRUE
          for (k in names(item)) {
            prefix <- if (first) paste0(pad, "  - ") else paste0(pad, "    ")
            out <- c(out, paste0(prefix, k, ": ", scalar(item[[k]])))
            first <- FALSE
          }
        } else {
          out <- c(out, paste0(pad, "  - ", scalar(item)))
        }
      }
    }
  }
  paste(out, collapse = "\n")
}

#' Read a native pollen_count YAML file
#'
#' @param path Path to a `pcountr` YAML file.
#' @param site Optional [pollen_site()] to attach.
#' @return A `pollen_count`.
#' @export
read_pollen_count <- function(path, site = NULL) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Reading native YAML requires the 'yaml' package. ",
         "Install it with install.packages('yaml').")
  }
  doc <- yaml::read_yaml(path)

  if (length(doc$events)) {
    # ── Lossless path (format_version >= 2): derive everything from events ──
    evs <- lapply(doc$events, function(e) {
      base <- list(type = e$type, position = as.integer(e$position %||% 0L))
      switch(e$type,
        grain      = c(base, list(code     = e$code %||% "",
                                  base     = e$base %||% "",
                                  pres     = e$pres %||% e$base %||% "",
                                  weight   = as.numeric(e$weight %||% 1),
                                  hidden   = isTRUE(e$hidden),
                                  traverse = e$traverse %||% NA_character_,
                                  anomaly  = isTRUE(e$anomaly))),
        spike      = c(base, list(traverse = e$traverse %||% NA_character_)),
        traverse   = c(base, list(label    = e$label %||% "")),
        remark     = c(base, list(text     = e$text %||% "",
                                  traverse = e$traverse %||% NA_character_)),
        slide_desc = c(base, list(text     = e$text %||% "")),
        base
      )
    })

    grain_evs <- Filter(function(e) e$type == "grain", evs)
    grains <- if (length(grain_evs)) {
      data.frame(
        code     = vapply(grain_evs, function(e) e$code,     ""),
        base     = vapply(grain_evs, function(e) e$base,     ""),
        pres     = vapply(grain_evs, function(e) e$pres,     ""),
        weight   = vapply(grain_evs, function(e) e$weight,   0),
        hidden   = vapply(grain_evs, function(e) e$hidden,   FALSE),
        traverse = vapply(grain_evs, function(e) e$traverse %||% NA_character_, ""),
        position = vapply(grain_evs, function(e) e$position, 0L),
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(code=character(0), base=character(0), pres=character(0),
                 weight=numeric(0), hidden=logical(0), traverse=character(0),
                 position=integer(0), stringsAsFactors=FALSE)
    }

    spike_n   <- sum(vapply(evs, function(e) e$type == "spike", FALSE))
    trav_evs  <- Filter(function(e) e$type == "traverse", evs)
    traverses <- vapply(trav_evs, function(e) e$label %||% "", "")
    rem_evs   <- Filter(function(e) e$type == "remark", evs)
    remarks   <- lapply(rem_evs, function(e)
      list(text = e$text, position = e$position,
           traverse = e$traverse %||% NA_character_))

  } else {
    # ── Legacy path (format_version 1): reconstruct from grains/remarks ──
    evs <- list()
    gl <- doc$grains %||% list()
    grains <- data.frame(
      code     = vapply(gl, function(g) g$code, ""),
      base     = vapply(gl, function(g) sub(";.*$", "", g$preservation), ""),
      pres     = vapply(gl, function(g) g$preservation, ""),
      weight   = vapply(gl, function(g) as.numeric(g$weight), 0),
      hidden   = vapply(gl, function(g) grepl("9", g$preservation), FALSE),
      traverse = vapply(gl, function(g) g$traverse %||% NA_character_, ""),
      position = seq_along(gl),
      stringsAsFactors = FALSE
    )
    spike_n   <- doc$spike_counted %||% 0
    traverses <- unlist(doc$traverses) %||% character(0)
    remarks   <- lapply(doc$remarks %||% list(), function(r)
      list(text = r$text, position = r$position,
           traverse = r$traverse %||% NA_character_))
  }

  pollen_count(
    grains            = grains,
    spike_n           = spike_n,
    traverses         = traverses,
    remarks           = remarks,
    events            = evs,
    sample_quantity   = doc$sample_quantity   %||% NA_real_,
    units             = doc$units             %||% NA_character_,
    spike_tablets     = doc$spike_tablets     %||% NA_real_,
    spike_density     = doc$spike_density     %||% NA_real_,
    spike_units       = doc$spike_units       %||% NA_character_,
    pollen_sum_groups = unlist(doc$pollen_sum_groups) %||% c("A","B","F"),
    depth_top         = doc$depth_top         %||% NA_real_,
    depth_bottom      = doc$depth_bottom      %||% NA_real_,
    age_top           = doc$age_top           %||% NA_real_,
    age_bottom        = doc$age_bottom        %||% NA_real_,
    sample_name       = doc$sample_name %||% doc$sample_number %||% NA_character_,
    dic_path          = doc$dic_path          %||% NA_character_,
    slide             = doc$slide             %||% NA_character_,
    title             = doc$title             %||% NA_character_,
    source_file       = doc$source_file       %||% basename(path),
    conc_method       = doc$conc_method       %||% "spike",
    use_pres          = if (isFALSE(doc$use_pres)) FALSE else TRUE,
    site              = site
  )
}

.na_null <- function(v) if (length(v) == 0L || (length(v) == 1L && is.na(v))) NULL else v
