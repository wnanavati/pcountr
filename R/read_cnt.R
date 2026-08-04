#' Read a legacy PCount count file (.CNT)
#'
#' Parses the PCount `.CNT` format into a per-grain `pollen_count` object,
#' preserving the original counting order, traverse structure, tracer-spike
#' marks and inline remarks.
#'
#' The validated grammar (confirmed against a full 20-sample site) is:
#'
#' * **Header** -- 5 lines: program tag, timestamp, a config line
#'   (`dict, sample_qty, spike_tablets, spike_density, n0, units;`), the
#'   pollen-sum definition (e.g. `POLLEN SUM = ABF`) and a title line.
#' * **Slide description** -- text wrapped in `{ ... }`.
#' * **Grain** -- a taxon code (1-2 letters, optionally prefixed `#`/`$`)
#'   followed by one base preservation digit `1`-`8`, optionally followed by
#'   modifier digits drawn from `{0, 9}` (where `0` marks a half-grain fragment,
#'   weight 0.5, and `9` marks hidden).
#' * **Spike** -- a bare `.` (one tracer microsphere; no preservation digit).
#' * **Traverse marker** -- `/label/` where `label` is any free text the
#'   analyst chooses (stored verbatim; never validated).
#' * **Remark** -- free text in `[ ... ]`, kept verbatim at its position.
#'
#' Anything not matching these is recorded as an *anomaly* (e.g. stray digits
#' from data-entry typos). Valid grains are still imported; anomalies are
#' attached as the `anomalies` attribute and reported via a warning.
#'
#' @param path Path to a `.CNT` file.
#' @param site Optional [pollen_site()]. If supplied, taxon codes are resolved
#'   against its dictionary and unresolved codes are reported as anomalies.
#' @param quiet If `TRUE`, suppress the anomaly warning.
#' @return A `pollen_count` object.
#' @references Grimm, E. C. (1994). *PCount* (Version 2.0) \[MS-DOS software\].
#'   Illinois State Museum, Research and Collections Center, Springfield, IL.
#' @export
read_cnt <- function(path, site = NULL, quiet = FALSE) {
  raw <- readLines(path, warn = FALSE, encoding = "latin1")
  if (length(raw) < 6) stop("File too short to be a .CNT: ", path)

  header <- raw[1:5]
  cfg <- .parse_cfg_line(header[3])
  pollen_sum_groups <- .parse_pollen_sum(header[4])
  title <- trimws(header[5])

  # De-wrap the body: the count stream is wrapped at ~68 cols; rejoin.
  body_lines <- raw[6:length(raw)]
  body_lines <- body_lines[nzchar(trimws(body_lines))]
  body <- paste0(trimws(body_lines, which = "right"), collapse = "")

  # Pull off the slide description {...}
  slide <- NA_character_
  m <- regexec("^\\{([^}]*)\\}(.*)$", body)
  g <- regmatches(body, m)[[1]]
  if (length(g) == 3L) {
    slide <- g[2]
    stream <- g[3]
  } else {
    stream <- body
  }

  parsed <- .tokenise_stream(stream)

  count <- pollen_count(
    grains = parsed$grains,
    spike_n = parsed$spike_n,
    traverses = parsed$traverses,
    remarks = parsed$remarks,
    events = parsed$events,
    sample_quantity = cfg$sample_qty,
    units = cfg$units_label,
    spike_tablets = cfg$spike_tablets,
    spike_density = cfg$spike_density,
    pollen_sum_groups = pollen_sum_groups,
    slide = slide,
    title = title,
    source_file = basename(path),
    site = site
  )
  attr(count, "anomalies") <- parsed$anomalies

  # Resolve codes against the dictionary if a site is given.
  if (!is.null(site)) {
    known <- c(site$dictionary$code, ".")
    codes <- parsed$grains$code
    unknown <- setdiff(unique(codes[!is.na(codes)]), known)
    if (length(unknown)) {
      attr(count, "anomalies") <- rbind(
        attr(count, "anomalies"),
        data.frame(position = NA_integer_,
                   text = unknown,
                   reason = "code not in dictionary",
                   stringsAsFactors = FALSE)
      )
    }
  }

  an <- attr(count, "anomalies")
  if (!quiet && !is.null(an) && nrow(an) > 0) {
    warning(sprintf("%s: %d anomaly/anomalies recorded (see attr(x,'anomalies')).",
                    basename(path), nrow(an)), call. = FALSE)
  }
  count
}

# --- internal helpers --------------------------------------------------------

.parse_cfg_line <- function(line) {
  line <- sub(";\\s*$", "", trimws(line))
  parts <- trimws(strsplit(line, ",")[[1]])
  # parts: dict, sample_qty, spike_tablets, spike_density, n0, units
  units_code <- suppressWarnings(as.integer(parts[6]))
  units_label <- switch(as.character(units_code),
                        "1" = "ml",
                        "2" = "g",
                        NA_character_)
  list(
    dictionary = parts[1],
    sample_qty = suppressWarnings(as.numeric(parts[2])),
    spike_tablets = suppressWarnings(as.numeric(parts[3])),
    spike_density = suppressWarnings(as.numeric(parts[4])),
    units_code = units_code,
    units_label = units_label
  )
}

.parse_pollen_sum <- function(line) {
  # e.g. "POLLEN SUM = ABF"
  m <- regmatches(line, regexpr("=\\s*([A-Z]+)", line))
  if (!length(m)) return(c("A", "B", "F"))
  letters_str <- sub("=\\s*", "", m)
  strsplit(letters_str, "")[[1]]
}

# Tokeniser: walks the stream left to right, classifying each token and
# preserving order in `events`.
.tokenise_stream <- function(stream) {
  n <- nchar(stream)
  pos <- 1L
  events <- list()
  grains <- list()
  remarks <- list()
  traverses <- character(0)
  anomalies <- list()
  spike_n <- 0
  cur_traverse <- NA_character_
  ne <- 0L

  # Regexes anchored at a position
  re_spike    <- "^\\."
  re_traverse <- "^/([^/]+)/"
  re_remark   <- "^\\[([^]]*)\\]"
  re_grain    <- "^([#$]?[A-Za-z]{1,2})([1-8])([09]*)"

  sub_from <- function(p) substr(stream, p, n)

  while (pos <= n) {
    s <- sub_from(pos)

    if (substr(s, 1, 1) == "/") {
      mt <- regmatches(s, regexec(re_traverse, s, perl = TRUE))[[1]]
      if (length(mt) == 2L) {
        cur_traverse <- mt[2]
        traverses <- c(traverses, cur_traverse)
        ne <- ne + 1L
        events[[ne]] <- list(type = "traverse", label = cur_traverse,
                             position = pos)
        pos <- pos + nchar(mt[1])
        next
      }
    }

    if (substr(s, 1, 1) == "[") {
      mt <- regmatches(s, regexec(re_remark, s))[[1]]
      if (length(mt) == 2L) {
        ne <- ne + 1L
        events[[ne]] <- list(type = "remark", text = mt[2], position = pos,
                             traverse = cur_traverse)
        remarks[[length(remarks) + 1L]] <-
          list(text = mt[2], position = pos, traverse = cur_traverse)
        pos <- pos + nchar(mt[1])
        next
      }
    }

    if (substr(s, 1, 1) == ".") {
      spike_n <- spike_n + 1
      ne <- ne + 1L
      events[[ne]] <- list(type = "spike", position = pos,
                          traverse = cur_traverse)
      pos <- pos + 1L
      next
    }

    mt <- regmatches(s, regexec(re_grain, s))[[1]]
    if (length(mt) == 4L && nzchar(mt[1])) {
      code <- mt[2]
      base <- mt[3]
      mods <- strsplit(mt[4], "")[[1]]
      half <- "0" %in% mods
      hidden <- "9" %in% mods
      pres_set <- unique(c(base, mods[mods != "0"]))  # 0 is weight, not a state
      weight <- if (half) 0.5 else 1.0
      grains[[length(grains) + 1L]] <- list(
        code = code,
        base = base,
        pres_set = pres_set,
        weight = weight,
        hidden = hidden,
        traverse = cur_traverse,
        position = pos
      )
      ne <- ne + 1L
      events[[ne]] <- list(type     = "grain",
                           code     = code,
                           base     = base,
                           pres     = paste(pres_set, collapse = ";"),
                           weight   = weight,
                           hidden   = hidden,
                           position = pos,
                           traverse = cur_traverse,
                           anomaly  = FALSE)
      pos <- pos + nchar(mt[1])
      next
    }

    # Nothing matched: record one character as an anomaly and advance.
    anomalies[[length(anomalies) + 1L]] <-
      list(position = pos, text = substr(stream, pos, pos),
           reason = "unparseable token")
    pos <- pos + 1L
  }

  grains_df <- .grains_to_df(grains)
  anomalies_df <- .anoms_to_df(anomalies)

  list(
    grains = grains_df,
    spike_n = spike_n,
    traverses = traverses,
    remarks = remarks,
    events = events,
    anomalies = anomalies_df
  )
}

.grains_to_df <- function(grains) {
  if (!length(grains)) {
    return(data.frame(code = character(0), base = character(0),
                      pres = character(0), weight = numeric(0),
                      hidden = logical(0), traverse = character(0),
                      position = integer(0), stringsAsFactors = FALSE))
  }
  data.frame(
    code     = vapply(grains, `[[`, "", "code"),
    base     = vapply(grains, `[[`, "", "base"),
    pres     = vapply(grains, function(g) paste(g$pres_set, collapse = ";"), ""),
    weight   = vapply(grains, `[[`, 0, "weight"),
    hidden   = vapply(grains, `[[`, FALSE, "hidden"),
    traverse = vapply(grains, function(g) g$traverse %||% NA_character_, ""),
    position = vapply(grains, `[[`, 0L, "position"),
    stringsAsFactors = FALSE
  )
}

.anoms_to_df <- function(anoms) {
  if (!length(anoms)) {
    return(data.frame(position = integer(0), text = character(0),
                      reason = character(0), stringsAsFactors = FALSE))
  }
  data.frame(
    position = vapply(anoms, `[[`, 0L, "position"),
    text     = vapply(anoms, `[[`, "", "text"),
    reason   = vapply(anoms, `[[`, "", "reason"),
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
