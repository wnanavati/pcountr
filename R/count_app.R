#' Launch the interactive pollen counting application
#'
#' Opens the pcountr Shiny counting app in your default browser. The app
#' provides a keystroke-driven counting interface that mirrors the PCount DOS
#' workflow while saving to the native YAML format.
#'
#' @section Input syntax:
#' Type any of the following in the input field and press Enter:
#' \describe{
#'   \item{`B1`, `I80`, `A1`}{**With preservation codes (default):** taxon code +
#'     base preservation digit (1–8) + optional modifiers (`0` = half-grain,
#'     `9` = hidden).}
#'   \item{`B`, `I`, `A`}{**Without preservation codes:** taxon code only (when
#'     "Use preservation codes?" is set to No on setup). The stream displays grains
#'     separated by `_`. Preservation columns are suppressed.}
#'   \item{`.`}{One tracer microsphere (spike). Only relevant when concentration
#'     method is "spike". Pressing `.` on an empty input field submits
#'     immediately — no Enter required.}
#'   \item{`/label/`}{A traverse marker — stored verbatim.}
#'   \item{`[text]`}{An inline remark — stored verbatim.}
#' }
#' Use the **New Slide** button to record a slide transition; you will be
#' prompted for the slide ID.
#'
#' @param ... Arguments passed to [shiny::runApp()], e.g. `port = 3838`.
#' @return Called for its side effect (launches the app). Does not return
#'   until the app is stopped.
#' @export
count_app <- function(...) {
  if (!requireNamespace("shiny", quietly = TRUE))
    stop("The 'shiny' package is required. ",
         "Install it with: install.packages('shiny')")
  if (!requireNamespace("DT", quietly = TRUE))
    stop("The 'DT' package is required. ",
         "Install it with: install.packages('DT')")
  if (!requireNamespace("shinyFiles", quietly = TRUE))
    stop("The 'shinyFiles' package is required. ",
         "Install it with: install.packages('shinyFiles')")
  app_dir <- system.file("shiny", "pcount_app", package = "pcountr")
  if (!nzchar(app_dir))
    stop("Shiny app directory not found. Try re-installing pcountr.")
  shiny::runApp(app_dir, ...)
}
