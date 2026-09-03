# remarks.R — extract remark table from a pollen_site (any counted proxy)

#' Extract remarks from a site
#'
#' Returns a data frame of every inline remark recorded during counting across
#' all samples in a \code{pollen_site}, along with the taxon ID of the
#' immediately adjacent entry.
#'
#' @param site A \code{pollen_site} object.
#' @param id   \code{"before"} (default) returns the entry counted immediately
#'   \emph{before} the remark; \code{"after"} returns the entry counted
#'   immediately \emph{after} it.  The ID is the taxon code concatenated with
#'   the preservation string (e.g. \code{"I1"} for Picea, well-preserved), or
#'   just the code when preservation was not recorded (e.g. \code{"I"}).
#'   \code{NA} when no adjacent entry exists or when a sample lacks a full
#'   event stream (format version 1 YAML).
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{sample_name}{Sample identifier from count metadata.}
#'     \item{slide}{The slide that was active when the remark was written —
#'       the analyst's name for it, or its ordinal within the sample (1, 2, …)
#'       if it was never named. Every sample starts on slide 1; each
#'       \code{\{...\}} token in a CNT stream (or New Slide in the counting
#'       app) begins the next slide.}
#'     \item{traverse}{Traverse label active at the time the remark was made.}
#'     \item{id}{Taxon ID of the adjacent entry (see \code{id} argument).}
#'     \item{remark}{Remark text, verbatim.}
#'   }
#'   An empty data frame with the same columns is returned when no remarks
#'   exist in any sample.
#'
#' @examples
#' \dontrun{
#' site <- read_site("path/to/yamls", dic = "path/to/dict.csv")
#' extract_remarks(site)
#' extract_remarks(site, id = "after")
#' }
#'
#' @export
extract_remarks <- function(site, id = c("before", "after")) {
  id <- match.arg(id)
  if (!inherits(site, "pollen_site"))
    stop("`site` must be a pollen_site object.")

  empty <- data.frame(
    sample_name = character(0),
    slide       = character(0),
    traverse    = character(0),
    id          = character(0),
    remark      = character(0),
    stringsAsFactors = FALSE
  )

  rows <- lapply(site$samples, function(cnt) {
    sname <- cnt$meta$sample_name %||% NA_character_
    evs   <- cnt$events

    if (length(evs) > 0L) {
      # ---------- format_version 2: full event stream available ----------
      if (!any(vapply(evs, function(e) isTRUE(e$type == "remark"), logical(1))))
        return(NULL)

      # Grain lookup, for resolving the ID adjacent to each remark.
      grain_evs <- Filter(function(e) isTRUE(e$type == "grain"), evs)
      # numeric(), not integer(): YAML may return positions as doubles
      g_pos <- vapply(grain_evs, function(e) as.numeric(e$position %||% NA_real_),
                      numeric(1))
      g_id  <- vapply(grain_evs, function(e) {
        p <- e$pres %||% ""
        if (nzchar(p)) paste0(e$code, p) else e$code %||% NA_character_
      }, character(1))

      # Walk the stream in order so each remark is attributed to the slide
      # that was active when it was written. Every sample starts on slide 1;
      # each slide_desc event ({...} in a CNT, New Slide in the app) begins
      # the next slide.
      slide_n    <- 0L
      slide_name <- NA_character_
      out        <- list()

      for (e in evs) {
        if (isTRUE(e$type == "slide_desc")) {
          slide_n    <- slide_n + 1L
          txt        <- e$text %||% ""
          slide_name <- if (nzchar(txt)) txt else NA_character_
          next
        }

        if (!isTRUE(e$type == "remark")) next

        # Slide label: the analyst's name for it, else its ordinal.
        cur_n     <- max(1L, slide_n)
        slide_lbl <- if (!is.na(slide_name)) slide_name else as.character(cur_n)

        rpos <- as.numeric(e$position %||% NA_real_)
        adj  <- NA_character_
        if (!is.na(rpos) && length(g_pos) > 0L) {
          if (id == "before") {
            ok <- which(!is.na(g_pos) & g_pos < rpos)
            if (length(ok) > 0L) adj <- g_id[ok[which.max(g_pos[ok])]]
          } else {
            ok <- which(!is.na(g_pos) & g_pos > rpos)
            if (length(ok) > 0L) adj <- g_id[ok[which.min(g_pos[ok])]]
          }
        }

        out[[length(out) + 1L]] <- data.frame(
          sample_name = sname,
          slide       = slide_lbl,
          traverse    = e$traverse %||% NA_character_,
          id          = adj,
          remark      = e$text %||% "",
          stringsAsFactors = FALSE
        )
      }

      if (length(out) == 0L) return(NULL)
      do.call(rbind, out)

    } else {
      # ---------- format_version 1 fallback: remarks list only ----------
      # No event stream, so slide transitions cannot be recovered; the whole
      # sample is reported against its recorded slide name, else slide 1.
      rmks <- cnt$remarks
      if (length(rmks) == 0L) return(NULL)

      s_raw <- cnt$meta$slide %||% NA_character_
      slide_lbl <- if (!is.na(s_raw) && nzchar(s_raw)) s_raw else "1"

      data.frame(
        sample_name = sname,
        slide       = slide_lbl,
        traverse    = vapply(rmks, function(r) r$traverse %||% NA_character_, character(1)),
        id          = NA_character_,
        remark      = vapply(rmks, function(r) r$text %||% "",     character(1)),
        stringsAsFactors = FALSE
      )
    }
  })

  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) return(empty)
  do.call(rbind, rows)
}
