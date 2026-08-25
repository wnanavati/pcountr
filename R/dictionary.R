#' Default preservation-code scheme
#'
#' The preservation codes used by PCount, following the scheme of Cushing
#' (1967, *Review of Palaeobotany and Palynology*). Code `0` is special: it is
#' a *weight modifier* meaning the grain is a fragment (counts as 0.5 toward
#' the pollen sum) rather than a preservation state in its own right. Codes
#' `5` and `7` are undefined in the source scheme and are retained as
#' placeholders that may be relabelled per project.
#'
#' @format A named character vector mapping single-digit codes to labels.
#' @references Cushing, E.J. (1967). Evidence for differential pollen
#'   preservation in late Quaternary sediments in Minnesota.
#'   *Review of Palaeobotany and Palynology*, 4(1-4), 87-101.
#' @export
default_preservation <- c(
  "1" = "well-preserved",
  "2" = "corroded",
  "3" = "degraded",
  "4" = "crumpled, exine thinned",
  "5" = "undefined",
  "6" = "crumpled, exine normal",
  "7" = "undefined",
  "8" = "broken",
  "9" = "hidden",
  "0" = "half-grain"
)

#' Default precedence for attributing multi-code grains in summaries
#'
#' When a single grain carries more than one preservation state (e.g. crumpled
#' and broken), a summary table that allows only one class per grain must pick
#' one. This vector defines the precedence, highest first. It is only used for
#' presentation; the raw per-grain preservation set is always retained.
#'
#' This is a **default, not a rule**. Pass `precedence` to [pollen_site()] to use
#' a different order; collapsing is a presentation choice that discards nothing,
#' since the raw per-grain `pres` string is always kept. Codes follow the
#' Cushing (1967) scheme defined in [default_preservation], which is likewise
#' overridable via `pollen_site(preservation = )`.
#'
#' @format A character vector of single-digit codes, highest precedence first.
#' @export
default_precedence <- c("8", "6", "2", "9", "1")

#' Read a PCount dictionary file (.DIC or .csv)
#'
#' Reads a pollen dictionary into a `pollen_dictionary` data frame. The format
#' is detected automatically from the file extension:
#'
#' * **`.DIC`** — the legacy PCount fixed-column format (original behaviour).
#' * **`.csv`** — the modern pcountr CSV format; see [read_dic_csv()] for column
#'   requirements and [write_dic_csv()] to create one from an existing `.DIC`.
#'
#' @param path Path to a `.DIC` or `.csv` dictionary file.
#' @return A data frame of class `pollen_dictionary` with columns `code`,
#'   `alias`, `group`, `name`, `is_special`, `value`.
#' @references Grimm, E. C. (1994). *PCount* (Version 2.0) \[MS-DOS software\].
#'   Illinois State Museum, Research and Collections Center, Springfield, IL.
#' @seealso [read_dic_csv()], [write_dic_csv()]
#' @export
read_dic <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") return(read_dic_csv(path))
  .read_dic_fixed(path)
}

# Legacy fixed-column parser (original implementation).
.read_dic_fixed <- function(path) {
  raw <- readLines(path, warn = FALSE, encoding = "latin1")
  if (length(raw) < 1) stop("Dictionary file is empty: ", path)
  body <- raw[-1]
  body <- body[nzchar(trimws(body))]

  pad <- function(s, n) formatC(s, width = n, flag = "-")
  get <- function(s, a, b) { s <- pad(s, b); trimws(substr(s, a, b)) }

  code  <- vapply(body, get, "", a = 8,  b = 9,  USE.NAMES = FALSE)
  alias <- vapply(body, get, "", a = 11, b = 18, USE.NAMES = FALSE)
  group <- vapply(body, get, "", a = 20, b = 20, USE.NAMES = FALSE)
  name  <- vapply(body, function(s) trimws(substring(pad(s, 22), 22)),
                  "", USE.NAMES = FALSE)

  keep <- nzchar(code) & nzchar(name)
  df <- data.frame(
    code       = code[keep],
    alias      = alias[keep],
    group      = group[keep],
    name       = name[keep],
    is_special = !nzchar(group[keep]) | grepl("^[#.]", code[keep]),
    value      = 1.0,
    stringsAsFactors = FALSE
  )
  class(df) <- c("pollen_dictionary", "data.frame")
  df
}

#' Read a pcountr CSV dictionary file
#'
#' Reads a CSV dictionary with the following columns:
#'
#' | Column | Required | Description |
#' |--------|----------|-------------|
#' | `code` | yes | Taxon code (1–2 characters; `#`-prefixed for non-pollen markers; `.` for tracer spike) |
#' | `name` | yes | Full taxon name |
#' | `group` | yes | Single-letter group code (e.g. `A`, `B`, `F`, `Q`); leave blank for special markers |
#' | `alias` | no | Short alternative name or abbreviation |
#' | `is_special` | no | `TRUE`/`FALSE`; inferred from `code` prefix when absent |
#' | `value` | no | Grain weight (default `1`). Set to `0.5` for half-grain codes when counting without preservation codes — e.g. a code `HI` for "half *Picea*" with `value = 0.5`. Ignored when preservation codes are in use (weight is then determined by the `0` modifier in the token). |
#'
#' Column names are matched case-insensitively. Rows with blank `code` or
#' `name` are silently dropped.
#'
#' A template with documentation is available at
#' `system.file("extdata", "dictionary_template.csv", package = "pcountr")`.
#'
#' @param path Path to a `.csv` dictionary file.
#' @return A data frame of class `pollen_dictionary`.
#' @seealso [read_dic()], [write_dic_csv()]
#' @export
read_dic_csv <- function(path) {
  # encoding = "UTF-8" marks the strings rather than converting them, so taxon
  # names carrying diacritics (Neotoma spells one of them "Isoëtes") survive
  # on machines whose native encoding is not UTF-8. Harmless for ASCII files.
  df <- tryCatch(
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
             encoding = "UTF-8"),
    error = function(e) stop("Could not read dictionary CSV '", path,
                             "': ", e$message)
  )

  # Case-insensitive column matching
  nm_lower <- tolower(names(df))
  resolve  <- function(want) {
    hit <- which(nm_lower == tolower(want))
    if (length(hit)) names(df)[hit[1L]] else NA_character_
  }
  req_cols <- c("code", "name", "group")
  missing  <- req_cols[is.na(vapply(req_cols, resolve, ""))]
  if (length(missing))
    stop("Dictionary CSV '", basename(path), "' is missing required column(s): ",
         paste(missing, collapse = ", "),
         ".\nRequired: code, name, group.  Optional: alias, is_special, value.")

  # Rename to standard names
  for (std in c("code", "name", "group", "alias", "is_special", "value")) {
    real <- resolve(std)
    if (!is.na(real) && real != std) df[[std]] <- df[[real]]
  }

  # Add optional columns if absent
  if (!"alias"      %in% names(df)) df$alias      <- NA_character_
  if (!"is_special" %in% names(df)) df$is_special  <- NA
  if (!"value"      %in% names(df)) df$value       <- NA_real_

  df$code       <- trimws(as.character(df$code  %||% ""))
  df$name       <- trimws(as.character(df$name  %||% ""))
  df$group      <- trimws(as.character(df$group %||% ""))
  df$alias      <- trimws(as.character(df$alias %||% ""))
  df$alias[is.na(df$alias)] <- ""

  # is_special: honour explicit TRUE/FALSE, else infer from code prefix / blank group
  explicit <- suppressWarnings(as.logical(df$is_special))
  inferred <- !nzchar(df$group) | grepl("^[#.]", df$code)
  df$is_special <- ifelse(is.na(explicit), inferred, explicit | inferred)

  # value: grain weight; default 1 when absent or NA
  df$value <- suppressWarnings(as.numeric(df$value))
  df$value[is.na(df$value)] <- 1.0

  # Drop blank / NA rows; select canonical column order
  keep <- !is.na(df$code) & nzchar(df$code) &
          !is.na(df$name) & nzchar(df$name)
  df   <- df[keep, c("code", "alias", "group", "name", "is_special", "value"),
             drop = FALSE]
  rownames(df) <- NULL
  class(df)    <- c("pollen_dictionary", "data.frame")
  df
}

#' Write a pollen_dictionary to a CSV file
#'
#' Serialises a `pollen_dictionary` to the pcountr CSV format.  The resulting
#' file can be edited in any spreadsheet application and read back with
#' [read_dic()] or [read_dic_csv()].
#'
#' To migrate a legacy `.DIC` file to CSV:
#' ```r
#' write_dic_csv(read_dic("ECG.DIC"), "ECG.csv")
#' ```
#'
#' @param dic A `pollen_dictionary` object.
#' @param path Output `.csv` path.
#' @return `path`, invisibly.
#' @seealso [read_dic_csv()], [read_dic()]
#' @export
write_dic_csv <- function(dic, path) {
  stopifnot(inherits(dic, "pollen_dictionary"))
  # fileEncoding is explicit for the same reason read_dic_csv() reads with
  # encoding = "UTF-8": taxon names can carry diacritics (Neotoma spells one
  # of them "Iso\u00ebtes"), and the round trip must not depend on the
  # machine's native encoding.
  write.csv(dic[, c("code", "alias", "group", "name", "is_special", "value"),
               drop = FALSE],
            file = path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

#' Construct a pollen_site object
#'
#' A *site* bundles the configuration shared by all samples counted there: the
#' dictionary, the preservation-code scheme, the precedence used for summarising
#' multi-state grains, and the pollen-sum group definition.
#'
#' @param name Site name.
#' @param dictionary A `pollen_dictionary` (from [read_dic()]) or path to a
#'   `.DIC` file.
#' @param pollen_sum Character vector of group codes forming the *basic* pollen
#'   sum (default `c("A","B","F")`, i.e. the PCount "ABF" sum).
#' @param preservation Named character vector mapping codes to labels.
#' @param precedence Character vector of codes, highest precedence first, for
#'   attributing multi-state grains in single-class summaries.
#' @param samples Named list of `pollen_count` objects pre-loaded into the
#'   site (rarely used directly; [read_site()] populates this).
#' @return An object of class `pollen_site`.
#' @export
pollen_site <- function(name,
                        dictionary,
                        pollen_sum = c("A", "B", "F"),
                        preservation = default_preservation,
                        precedence = default_precedence,
                        samples = NULL) {
  if (is.character(dictionary) && length(dictionary) == 1L) {
    dictionary <- read_dic(dictionary)
  }
  if (!inherits(dictionary, "pollen_dictionary")) {
    stop("`dictionary` must be a pollen_dictionary or a path to a .DIC file.")
  }
  structure(
    list(
      name = name,
      dictionary = dictionary,
      pollen_sum = pollen_sum,
      preservation = preservation,
      precedence = precedence,
      samples = samples
    ),
    class = "pollen_site"
  )
}

#' @export
print.pollen_site <- function(x, ...) {
  cat("<pollen_site>", x$name, "\n")
  cat("  dictionary:", nrow(x$dictionary), "taxa",
      sprintf("(%s)", paste(names(table(x$dictionary$group)),
                            table(x$dictionary$group), sep = "=",
                            collapse = ", ")), "\n")
  cat("  pollen sum (basic):", paste(x$pollen_sum, collapse = "+"), "\n")
  if (!is.null(x$samples) && length(x$samples) > 0L) {
    tops <- vapply(x$samples, function(s) {
      v <- s$meta$depth_top
      if (is.null(v) || (length(v) == 1L && is.na(v))) NA_real_ else as.numeric(v)
    }, NA_real_)
    n_with    <- sum(!is.na(tops))
    n_without <- sum(is.na(tops))
    depth_str <- if (n_with > 0L)
      sprintf("depth %.1f-%.1f cm", min(tops, na.rm = TRUE),
              max(tops, na.rm = TRUE))
    else
      "no depths assigned"
    cat(sprintf("  samples: %d (%s; %d without depth)\n",
                length(x$samples), depth_str, n_without))
  }
  cat("  preservation codes:",
      paste(names(x$preservation), x$preservation, sep = "=",
            collapse = ", "), "\n")
  invisible(x)
}
