# pcountr — interactive pollen counting application
# Launch with: pcountr::count_app()

library(shiny)
library(DT)
library(shinyFiles)
library(pcountr)

# ── Helpers ------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

wrap_tokens <- function(tokens, width = 68) {
  if (!length(tokens)) return(character(0))
  lines <- character(0); cur <- ""
  for (tok in tokens) {
    candidate <- paste0(cur, tok)
    if (nchar(candidate) > width && nzchar(cur)) {
      lines <- c(lines, cur); cur <- tok
    } else cur <- candidate
  }
  if (nzchar(cur)) lines <- c(lines, cur)
  lines
}

render_stream <- function(events, dic_name, sample_qty, spike_qty,
                          spike_density, sample_units, pollen_sum,
                          title, created, use_pres = TRUE) {
  units_code <- switch(sample_units, ml = "1", g = "2", "2")
  header <- c(
    paste("File created", format(created, "%d %b %Y  %H:%M")),
    sprintf("%s.DIC, %s, %s, %s, 0, %s;",
            dic_name, sample_qty, spike_qty, spike_density, units_code),
    paste("POLLEN SUM =", paste(pollen_sum, collapse = "")),
    title
  )
  tokens <- vapply(events, function(e) {
    switch(e$type,
      slide_desc = sprintf("{%s}", e$text),
      traverse   = sprintf("/%s/", e$label),
      remark     = sprintf("[%s]", e$text),
      spike      = ".",
      grain      = {
        if (isTRUE(use_pres)) {
          mods <- ""
          if (isTRUE(e$hidden))        mods <- paste0(mods, "9")
          if (isTRUE(e$weight == 0.5)) mods <- paste0(mods, "0")
          paste0(e$code, e$base %||% "", mods)
        } else {
          paste0(e$code, "_")
        }
      }, "")
  }, "")
  paste(c(header, wrap_tokens(tokens, 68)), collapse = "\n")
}

# Suggest a next save path by incrementing a trailing number in the filename.
next_save_path <- function(path) {
  if (!nzchar(path %||% "")) return("")
  base <- tools::file_path_sans_ext(basename(path))
  ext  <- tools::file_ext(path)
  dir  <- dirname(path)
  m    <- regmatches(base, regexec("^(.*?)([0-9]+)$", base))[[1]]
  if (length(m) == 3L) {
    n       <- as.integer(m[3])
    new_num <- formatC(n + 1L, width = nchar(m[3]), flag = "0")
    new_base <- paste0(m[2], new_num)
  } else {
    new_base <- paste0(base, "_2")
  }
  file.path(dir, paste0(new_base, ".", ext))
}

# Reconstruct an ordered event list from a loaded pollen_count.
rebuild_events_from_count <- function(cnt) {
  g <- cnt$grains
  r <- cnt$remarks %||% list()
  t <- cnt$traverses %||% character(0)

  all_events <- list()

  title_str <- cnt$meta$title %||% ""
  if (nzchar(title_str))
    all_events <- c(all_events,
                    list(list(type="slide_desc", text=title_str, position=-1L)))

  if (!is.null(g) && nrow(g) > 0) {
    grain_evs <- lapply(seq_len(nrow(g)), function(i) {
      list(type     = "grain",
           code     = g$code[i],
           base     = g$base[i],
           pres     = g$pres[i],
           weight   = as.numeric(g$weight[i]),
           hidden   = isTRUE(g$hidden[i]),
           traverse = if (is.na(g$traverse[i])) NA_character_ else g$traverse[i],
           position = as.numeric(g$position[i]),
           anomaly  = FALSE)
    })
    all_events <- c(all_events, grain_evs)
  }

  if (length(t) > 0 && !is.null(g) && nrow(g) > 0) {
    for (label in t) {
      grain_pos <- g$position[!is.na(g$traverse) & g$traverse == label]
      trav_pos  <- if (length(grain_pos) > 0) min(grain_pos) - 0.5 else Inf
      all_events <- c(all_events,
                      list(list(type="traverse", label=label, position=trav_pos)))
    }
  } else if (length(t) > 0) {
    for (i in seq_along(t))
      all_events <- c(all_events,
                      list(list(type="traverse", label=t[i], position=i - 0.5)))
  }

  if (length(r) > 0) {
    remark_evs <- lapply(r, function(rem) {
      list(type     = "remark",
           text     = rem$text,
           position = as.numeric(rem$position %||% Inf),
           traverse = rem$traverse %||% NA_character_)
    })
    all_events <- c(all_events, remark_evs)
  }

  if (length(all_events) > 0) {
    positions  <- vapply(all_events,
                         function(e) as.numeric(e$position %||% Inf), NA_real_)
    all_events <- all_events[order(positions)]
  }

  for (i in seq_along(all_events)) all_events[[i]]$position <- i

  list(events       = all_events,
       base_spike_n = as.integer(cnt$spike_n %||% 0L))
}

# ── Colour palette (WCAG 2.1 AA compliant) ----------------------------------
# bg0 #1e1e1e  bg1 #252526  bg2 #2d2d30  bg3 #3e3e42
# fg0 #d4d4d4 (11.2:1)  fg1 #a0a0a0 (5.0:1)
# acc #4ec9b0 (7.0:1)   blu #9cdcfe (9.3:1)
# wrn #e5c07b (6.4:1)   err #f44747 (4.6:1)  grn #4caf50 (4.5:1)

APP_CSS <- "
/* ── Base ── */
body {
  background: #1e1e1e;
  color: #d4d4d4;
  font-family: 'Courier New', monospace;
}
a, a:visited { color: #9cdcfe; }

/* ── Setup card ── */
.setup-wrap {
  max-width: 580px;
  margin: 40px auto;
  background: #252526;
  padding: 28px 32px;
  border-radius: 8px;
  border: 1px solid #3e3e42;
}
h3.app-title { color: #4ec9b0; margin-top: 0; }
.control-label { color: #d4d4d4 !important; }
.radio label, .checkbox label { color: #d4d4d4 !important; }
input[type='text'], input[type='number'], select, textarea {
  background: #2d2d30 !important;
  color: #d4d4d4 !important;
  border: 1px solid #3e3e42 !important;
}
input[type='text']:focus, input[type='number']:focus {
  border-color: #4ec9b0 !important;
  outline: 2px solid #4ec9b0 !important;
  outline-offset: 1px;
}
.form-control { background: #2d2d30 !important; color: #d4d4d4 !important; }

/* ── Stream box ── */
#stream_box {
  height: 360px; overflow-y: auto;
  background: #0d0d0d; color: #d4d4d4;
  font-size: 13px; padding: 8px 10px;
  white-space: pre-wrap; word-break: break-all;
  border: 1px solid #3e3e42; border-radius: 4px;
}

/* ── Stats panel ── */
.stats-box {
  background: #252526;
  padding: 14px; border-radius: 8px;
  border: 1px solid #3e3e42;
  font-size: 14px; min-height: 360px;
}
.big-num {
  font-size: 22px; font-weight: bold;
  color: #4ec9b0; display: inline-block; min-width: 65px;
}
.stat-label { color: #a0a0a0; font-size: 12px; }
.mid-num {
  font-size: 16px; font-weight: bold;
  color: #4ec9b0; display: inline-block;
}
.cur-trav   { color: #9cdcfe; font-size: 12px; margin-top: 4px; }

/* ── Buttons ── */
.btn-full { width: 100%; margin: 3px 0; }
.btn-primary   { background: #0e639c !important; color: #fff !important;
                 border-color: #0e639c !important; }
.btn-primary:hover { background: #1177bb !important; }
.btn-success   { background: #2d7d27 !important; color: #fff !important;
                 border-color: #2d7d27 !important; }
.btn-success:hover { background: #388a34 !important; }
.btn-warning   { background: #7c5c00 !important; color: #fff !important;
                 border-color: #7c5c00 !important; }
.btn-warning:hover { background: #9a7500 !important; }
.btn-info      { background: #00695c !important; color: #fff !important;
                 border-color: #00695c !important; }
.btn-info:hover { background: #00796b !important; }
.btn-danger    { background: #a31515 !important; color: #fff !important;
                 border-color: #a31515 !important; }
.btn-danger:hover { background: #c01818 !important; }
.btn-newsmpl   { background: #3e3e42 !important; color: #d4d4d4 !important;
                 border: 1px solid #6b6b6b !important; width: 100%; margin: 3px 0; }
.btn-newsmpl:hover { background: #5a5a5f !important; }

/* ── Grain input ── */
#grain_input {
  background: #2d2d30 !important; color: #d4d4d4 !important;
  border: 1px solid #3e3e42 !important;
  font-family: 'Courier New', monospace; font-size: 16px;
}

/* ── Taxon bar ── */
.taxon-strip {
  background: #252526; padding: 8px 12px;
  border-radius: 8px; margin-top: 8px;
  border: 1px solid #3e3e42;
  display: flex; align-items: center; flex-wrap: wrap; gap: 6px;
}
.taxon-cell {
  background: #1e3a5f; border-radius: 5px;
  padding: 4px 10px; text-align: center; min-width: 68px;
  border: 1px solid #2d5a8e;
}
.t-code { font-size: 12px; color: #9cdcfe; font-weight: bold; }
.t-val  { font-size: 16px; color: #d4d4d4; }

/* ── Tabs ── */
.nav-tabs { border-bottom-color: #3e3e42 !important; }
.nav-tabs > li > a { color: #a0a0a0 !important; background: #1e1e1e !important;
                     border-color: #3e3e42 !important; }
.nav-tabs > li.active > a,
.nav-tabs > li.active > a:focus,
.nav-tabs > li.active > a:hover {
  color: #d4d4d4 !important; background: #252526 !important;
  border-color: #3e3e42 #3e3e42 #252526 !important; }
.tab-content { background: #252526; border: 1px solid #3e3e42;
               border-top: none; padding: 0 8px; border-radius: 0 0 6px 6px; }

/* ── DataTables dark mode ── */
.dataTables_wrapper { color: #d4d4d4 !important; }
.dataTables_wrapper .dataTables_length label,
.dataTables_wrapper .dataTables_filter label,
.dataTables_wrapper .dataTables_info { color: #d4d4d4 !important; }
.dataTables_wrapper .dataTables_length select,
.dataTables_wrapper .dataTables_filter input {
  background: #2d2d30 !important; color: #d4d4d4 !important;
  border: 1px solid #3e3e42 !important; }
.dataTables_wrapper .dataTables_paginate .paginate_button {
  color: #d4d4d4 !important; background: #2d2d30 !important;
  border: 1px solid #3e3e42 !important; }
.dataTables_wrapper .dataTables_paginate .paginate_button:hover {
  background: #3e3e42 !important; color: #fff !important; border-color: #6b6b6b !important; }
.dataTables_wrapper .dataTables_paginate .paginate_button.current,
.dataTables_wrapper .dataTables_paginate .paginate_button.current:hover {
  background: #0e639c !important; color: #fff !important; border-color: #0e639c !important; }
table.dataTable { border-collapse: collapse !important; width: 100% !important; }
table.dataTable thead th,
table.dataTable thead td {
  background: #2d2d30 !important; color: #9cdcfe !important;
  border-bottom: 2px solid #3e3e42 !important; }
table.dataTable.display tbody tr.odd  { background: #1e1e1e !important; }
table.dataTable.display tbody tr.even { background: #252526 !important; }
table.dataTable tbody tr:hover        { background: #2d2d30 !important; }
table.dataTable tbody td {
  color: #d4d4d4 !important; border-top: 1px solid #3e3e42 !important; }
table.dataTable tbody td.sorting_1 { background: transparent !important; }

/* ── Modals ── */
.modal-content {
  background: #252526 !important; color: #d4d4d4 !important;
  border: 1px solid #3e3e42 !important; }
.modal-header { border-bottom-color: #3e3e42 !important; }
.modal-title  { color: #4ec9b0 !important; }
.modal-footer { border-top-color: #3e3e42 !important; }
.modal-backdrop { opacity: 0.7 !important; }
.close { color: #d4d4d4 !important; opacity: 0.8 !important; }

/* Unknown-code modal — extra prominence */
.unknown-banner {
  background: #3d1010;
  border: 2px solid #f44747;
  border-radius: 6px;
  padding: 14px 16px;
  margin-bottom: 16px;
}
.unknown-banner .unk-code {
  font-size: 2em; font-weight: bold;
  color: #f44747; font-family: 'Courier New', monospace;
  display: block; margin-bottom: 4px;
}
.unknown-banner .unk-msg {
  color: #d4d4d4; font-size: 1em;
}

/* ── Notifications ── */
.shiny-notification {
  background: #252526 !important; color: #d4d4d4 !important;
  border: 1px solid #3e3e42 !important; }

/* ── Misc ── */
hr { border-color: #3e3e42 !important; }
.carried-dic { color: #4ec9b0; font-size: 13px; margin-bottom: 8px; }
.meta-section { background: #1e1e1e; border-radius: 6px;
                padding: 12px 14px; margin-bottom: 8px;
                border: 1px solid #3e3e42; }
.meta-section-title { color: #9cdcfe; font-size: 12px;
                      text-transform: uppercase; letter-spacing: 0.05em;
                      margin-bottom: 8px; }
"

# ── JavaScript ---------------------------------------------------------------

APP_JS <- "
function scrollStream() {
  var el = document.getElementById('stream_box');
  if (el) el.scrollTop = el.scrollHeight;
}
function focusGrainInput() {
  setTimeout(function() {
    var el = document.getElementById('grain_input');
    if (el) el.focus();
  }, 60);
}
// Capture DOM value synchronously at Enter time — bypasses Shiny's 250ms
// textInput debounce so rapid repeated entries are never dropped.
// Optional `forced` value skips DOM read (used for single-key spike shortcut).
function submitEntry(forced) {
  var el  = document.getElementById('grain_input');
  var val = (forced !== undefined) ? forced : (el ? el.value : '');
  Shiny.setInputValue('entry_submit',
                      { value: val, t: Date.now() },
                      { priority: 'event' });
  if (el) el.value = '';
}
// Audible alert for unrecognised codes (Web Audio API).
function playBeep() {
  try {
    var ctx  = new (window.AudioContext || window.webkitAudioContext)();
    var osc  = ctx.createOscillator();
    var gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.type = 'square';
    osc.frequency.value = 880;
    gain.gain.setValueAtTime(0.35, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.35);
  } catch(e) {}
}
"

# ── Modal builders -----------------------------------------------------------

# Single alert modal for both unknown codes and malformed input.
# Analyst can dismiss to re-enter, or jump to the Dictionary tab.
code_alert_modal <- function(submission, message_text) {
  modalDialog(
    size  = "l",
    title = tags$span(style = "font-size:1.3em; color:#f44747;",
                      "⚠️  Entry not recognised"),
    div(class = "unknown-banner",
        tags$span(class = "unk-code", sprintf("\"%s\"", submission)),
        tags$span(class = "unk-msg",  message_text)
    ),
    footer = tagList(
      actionButton("alert_reenter_btn", "Re-enter",
                   style = "background:#3e3e42;color:#d4d4d4;border-color:#6b6b6b;"),
      actionButton("alert_edit_dic_btn", "Edit Dictionary", class = "btn-info")
    ),
    easyClose = FALSE
  )
}

traverse_modal <- function() {
  modalDialog(
    title = "New Traverse",
    textInput("trav_label", "Traverse label:",
              placeholder = "e.g. 42N, 18.5S, left-edge"),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_trav_btn", "Add Traverse", class = "btn-info")
    )
  )
}

remark_modal <- function() {
  modalDialog(
    title = "Insert Remark",
    textInput("remark_text", "Remark:",
              placeholder = "e.g. slide edge, focus change"),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_remark_btn", "Insert Remark", class = "btn-info")
    )
  )
}

# ── UI panels ----------------------------------------------------------------

# is_resume: TRUE when a YAML has been loaded and we are showing pre-filled form
# meta:      named list of loaded metadata values (or NULL for a fresh count)
setup_panel <- function(is_resume = FALSE, meta = NULL) {
  m <- meta %||% list()

  title_text <- if (is_resume) "Resume Count" else "New Count"
  btn_text   <- if (is_resume) "▶  Resume Count" else "▶  Start Counting"

  def_qty        <- m$sample_qty    %||% 1
  def_units      <- m$sample_units  %||% "ml"
  def_spike      <- m$spike_qty     %||% 2
  def_sdens      <- m$spike_density %||% 9666
  def_sunits     <- m$spike_units   %||% "tablets"
  def_sname      <- m$sample_name   %||% ""
  def_conc_meth  <- m$conc_method   %||% "spike"
  def_use_pres   <- if (isFALSE(m$use_pres)) "no" else "yes"
  def_dtop   <- m$depth_top     # may be NA
  def_dbot   <- m$depth_bottom
  def_atop   <- m$age_top
  def_abot   <- m$age_bottom
  def_title  <- m$title         %||% ""
  def_path   <- m$save_path     %||% ""

  div(class = "setup-wrap",
    h3(title_text, class = "app-title"),

    # ── Open existing count (top — dictionary auto-loads from YAML) ──
    shinyFilesButton("open_yaml_btn", "Open Existing Count (.yaml)",
                     title    = "Open a past count",
                     multiple = FALSE,
                     style    = "width:100%;background:#3e3e42;color:#d4d4d4;
                                 border:1px solid #6b6b6b;margin-bottom:4px;"),
    p("Dictionary is loaded automatically from the saved count.",
      style = "color:#a0a0a0;font-size:11px;margin:2px 0 0 0;"),
    hr(),

    # ── Dictionary (for new counts, or manual override on resume) ──
    uiOutput("dic_ui"),

    # ── ΣP groups ──
    uiOutput("group_ui"),
    hr(),

    # ── Concentration method ──
    radioButtons("conc_method", "Calculate concentration?",
                 choices  = c("Yes, using spikes."    = "spike",
                              "Yes, volumetrically."  = "volumetric",
                              "No."                   = "none"),
                 selected = def_conc_meth),
    # ── Sample quantity ──
    fluidRow(
      column(6, numericInput("sample_qty", "Sample quantity",
                             value = def_qty, min = 0.001, step = 0.1)),
      column(6, radioButtons("sample_units", "Sample units",
                             choices  = c("ml", "g"),
                             selected = def_units, inline = TRUE))
    ),
    # ── Spike fields — visible only when spike method is selected ──
    conditionalPanel(
      condition = "input.conc_method == 'spike'",
      fluidRow(
        column(6, numericInput("spike_qty", "Spike quantity",
                               value = def_spike, min = 1, step = 1)),
        column(6, numericInput("spike_density", "Spike density",
                               value = def_sdens, min = 1))
      ),
      radioButtons("spike_units", "Spike units",
                   choices  = c("ml", "g", "tablets"),
                   selected = def_sunits, inline = TRUE)
    ),
    # ── Preservation codes ──
    radioButtons("use_pres", "Use preservation codes?",
                 choices  = c("Yes" = "yes", "No" = "no"),
                 selected = def_use_pres, inline = TRUE),
    hr(),

    # ── Sample location & age ──
    p("Sample location & age — optional",
      style = "color:#a0a0a0;font-size:12px;margin-bottom:6px;"),
    textInput("sample_name", "Sample name",
              placeholder = "e.g. KF24sh#001", value = def_sname),
    fluidRow(
      column(6, numericInput("depth_top",    "Depth top (cm)",    value = def_dtop,
                             min = 0, step = 0.25)),
      column(6, numericInput("depth_bottom", "Depth bottom (cm)", value = def_dbot,
                             min = 0, step = 0.25))
    ),
    fluidRow(
      column(6, numericInput("age_top",    "Age top (years BP)",    value = def_atop,
                             min = 0, step = 1)),
      column(6, numericInput("age_bottom", "Age bottom (years BP)", value = def_abot,
                             min = 0, step = 1))
    ),
    p("Ages in years before present (BP); present = 1950 CE.",
      style = "color:#a0a0a0;font-size:11px;margin-top:-6px;"),
    hr(),

    # ── Title / slide / save (only for fresh counts; on resume these come from YAML) ──
    if (!is_resume) textInput("first_slide", "First slide ID",
                               placeholder = "e.g. LM23sh#001-1"),
    textInput("title_line", "Sample title",
              placeholder = "e.g. Little Mosquito Lake  LM23sh#001  13MAY24",
              value = def_title),
    tags$label("Save YAML to"),
    fluidRow(
      column(9, textInput("save_path", NULL,
                          placeholder = "Type path or use Browse",
                          value = def_path)),
      column(3, shinySaveButton("save_browse", "Browse",
                                title    = "Save count as YAML",
                                filetype = list(yaml = c("yaml","yml")),
                                style    = "width:100%;margin-top:0;"))
    ),
    br(),
    actionButton("start_btn", btn_text,
                 class = "btn-primary btn-full",
                 style = "font-size:15px;")
  )
}

counting_panel <- function() {
  tagList(
    tags$script(HTML("
      Shiny.addCustomMessageHandler('scroll',      function(m){ scrollStream(); });
      Shiny.addCustomMessageHandler('focus_input', function(m){ focusGrainInput(); });
      Shiny.addCustomMessageHandler('beep',        function(m){ playBeep(); });
      $(document).on('keydown', '#grain_input', function(e) {
        if (e.key === 'Enter') { e.preventDefault(); submitEntry(); }
        // Single-key spike shortcut: '.' on an empty field submits immediately.
        if (e.key === '.' && this.value === '') { e.preventDefault(); submitEntry('.'); }
      });
    ")),
    fluidRow(
      # ── Left: stream + tabbed input area ──
      column(8,
        div(id = "stream_box", textOutput("stream_out", inline = FALSE)),
        br(),
        tabsetPanel(id = "input_tabs",

          # ── Count tab ──
          tabPanel("Count",
            br(),
            fluidRow(
              column(9,
                textInput("grain_input", NULL,
                          placeholder = "code+digit  /traverse/  [remark]  .")
              ),
              column(3,
                tags$button("Enter", onclick = "submitEntry()",
                            class = "btn btn-primary",
                            style = "width:100%;margin-top:0;")
              )
            )
          ),

          # ── Grain History tab ──
          tabPanel("Grain History",
            br(),
            p("Double-click Code, Preservation, or Weight to edit. Preservation uses PCount notation: base digit (1–8) + optional modifiers (0 = half-grain, 9 = hidden).",
              style = "color:#a0a0a0;font-size:12px;"),
            DTOutput("grain_tbl")
          ),

          # ── Sample Info tab ──
          tabPanel("Sample Info",
            br(),
            p("All fields are live — changes take effect immediately and autosave.",
              style = "color:#a0a0a0;font-size:12px;margin-bottom:10px;"),
            div(class = "meta-section",
              div(class = "meta-section-title", "Identity"),
              textInput("meta_title",
                        "Sample title", value = ""),
              textInput("meta_sample_name",
                        "Sample name", value = "")
            ),
            div(class = "meta-section",
              div(class = "meta-section-title", "Depth & Age"),
              fluidRow(
                column(6, numericInput("meta_depth_top",    "Depth top (cm)",
                                       value = NA, min = 0, step = 0.25)),
                column(6, numericInput("meta_depth_bottom", "Depth bottom (cm)",
                                       value = NA, min = 0, step = 0.25))
              ),
              fluidRow(
                column(6, numericInput("meta_age_top",    "Age top (yr BP)",
                                       value = NA, min = 0, step = 1)),
                column(6, numericInput("meta_age_bottom", "Age bottom (yr BP)",
                                       value = NA, min = 0, step = 1))
              ),
              p("BP = years before present; present = 1950 CE.",
                style = "color:#a0a0a0;font-size:11px;margin-top:-4px;")
            ),
            div(class = "meta-section",
              div(class = "meta-section-title", "Sample & Spike"),
              fluidRow(
                column(6, numericInput("meta_sample_qty", "Sample quantity",
                                       value = 1, min = 0.001, step = 0.1)),
                column(6, radioButtons("meta_sample_units", "Units",
                                        choices  = c("ml","g"),
                                        selected = "ml", inline = TRUE))
              ),
              conditionalPanel(
                condition = "input.meta_conc_method == 'spike'",
                fluidRow(
                  column(6, numericInput("meta_spike_qty", "Spike quantity",
                                         value = 2, min = 1, step = 1)),
                  column(6, numericInput("meta_spike_density", "Spike density",
                                         value = 9666, min = 1))
                ),
                radioButtons("meta_spike_units", "Spike units",
                             choices  = c("ml","g","tablets"),
                             selected = "tablets", inline = TRUE)
              )
            ),
            div(class = "meta-section",
              div(class = "meta-section-title", "Counting Options"),
              radioButtons("meta_conc_method", "Calculate concentration?",
                           choices  = c("Yes, using spikes."   = "spike",
                                        "Yes, volumetrically." = "volumetric",
                                        "No."                  = "none"),
                           selected = "spike"),
              radioButtons("meta_use_pres", "Preservation codes?",
                           choices  = c("Yes" = "yes", "No" = "no"),
                           selected = "yes", inline = TRUE)
            ),
            div(class = "meta-section",
              div(class = "meta-section-title", "ΣP — Analyst defined pollen sum"),
              uiOutput("meta_group_ui")
            ),
            p("Save path is fixed for the current count.",
              style = "color:#a0a0a0;font-size:11px;margin-top:6px;")
          ),

          # ── Dictionary tab ──
          tabPanel("Dictionary",
            br(),
            p("Double-click any cell to edit. Add rows with the button below. Save writes back to the dictionary file.",
              style = "color:#a0a0a0;font-size:12px;"),
            DTOutput("dic_tbl"),
            br(),
            fluidRow(
              column(4, actionButton("dic_add_row_btn", "+  Add Row",
                                     class = "btn-info btn-full")),
              column(4, actionButton("dic_save_btn",    "✔  Save Dictionary",
                                     class = "btn-success btn-full")),
              column(4, uiOutput("dic_save_status"))
            ),
            br()
          )
        )
      ),

      # ── Right: stats + controls ──
      column(4,
        div(class = "stats-box",
          fluidRow(
            column(6,
              div(class = "stat-label", "Σ (total)"),
              div(class = "big-num", textOutput("stat_total", inline = TRUE))
            ),
            column(6,
              div(class = "stat-label", "ΣP (analyst defined)"),
              div(class = "big-num", textOutput("stat_basic", inline = TRUE))
            )
          ),
          fluidRow(
            column(6,
              div(class = "stat-label", textOutput("stat_conc_label", inline = TRUE)),
              div(class = "mid-num", textOutput("stat_conc", inline = TRUE))
            ),
            column(6,
              div(class = "stat-label", "PAR (grains/cm²/yr)"),
              div(class = "mid-num", textOutput("stat_par",  inline = TRUE))
            )
          ),
          hr(),
          fluidRow(
            column(4,
              div(class = "stat-label", "Slide"),
              div(class = "big-num", textOutput("stat_slide", inline = TRUE))
            ),
            column(4,
              div(class = "stat-label", "Travs"),
              div(class = "big-num", textOutput("stat_trav",  inline = TRUE))
            ),
            column(4,
              div(class = "stat-label", "Spike"),
              div(class = "big-num", textOutput("stat_spike", inline = TRUE))
            )
          ),
          div(class = "cur-trav", textOutput("stat_cur_trav", inline = FALSE)),
          hr(),
          fluidRow(
            column(6,
              actionButton("new_trav_btn", "Traverse",
                           class = "btn-info btn-full",
                           style = "font-size:12px;")
            ),
            column(6,
              actionButton("new_remark_btn", "Remark",
                           class = "btn-info btn-full",
                           style = "font-size:12px;")
            )
          ),
          actionButton("new_slide_btn", "New Slide",
                       class = "btn-info btn-full"),
          actionButton("undo_btn", "⟵  Undo",
                       class = "btn-warning btn-full"),
          hr(),
          div(class = "stat-label", textOutput("save_msg", inline = FALSE)),
          br(),
          actionButton("done_btn",   "✓  Done / Save",
                       class = "btn-success btn-full"),
          tags$button("⊕  New Sample",
                      id    = "new_sample_btn",
                      class = "btn btn-newsmpl",
                      onclick = "Shiny.setInputValue('new_sample_click',
                                 Date.now(), {priority:'event'});")
        )
      )
    ),
    uiOutput("taxon_bar")
  )
}

# ── Server -------------------------------------------------------------------

server <- function(input, output, session) {

  rv <- reactiveValues(
    # Setup
    setup_done    = FALSE,
    is_resume     = FALSE,   # TRUE after a YAML is loaded, before Resume is clicked
    loaded_cnt    = NULL,    # pollen_count from YAML, held until Resume
    loaded_meta   = NULL,    # named list of metadata from YAML
    dic           = NULL,
    dic_name      = "",
    dic_path      = "",
    dic_is_csv    = FALSE,
    pollen_sum    = c("A", "B", "F"),
    sample_qty    = 1,
    sample_units  = "ml",
    spike_qty     = 2,
    spike_density = 9666,
    spike_units   = "tablets",
    conc_method   = "spike",
    use_pres      = TRUE,
    title         = "",
    sample_name   = "",
    depth_top     = NA_real_,
    depth_bottom  = NA_real_,
    age_top       = NA_real_,
    age_bottom    = NA_real_,
    save_path     = "",
    created       = NULL,
    # Counting
    events        = list(),
    slide_n       = 0L,
    cur_traverse  = NA_character_,
    show_pct      = TRUE,
    # New-sample carry-over
    prev_setup    = NULL,
    prefill       = FALSE,
    # Spikes loaded from a past YAML (individual positions are not stored)
    base_spike_n  = 0L
  )

  # ── Debounced grain autosave (300 ms idle after last grain entry) ----------
  grain_save_pending   <- reactiveVal(0L)
  grain_save_debounced <- debounce(grain_save_pending, 300)
  observe({
    val <- grain_save_debounced()
    req(val > 0L)
    isolate(do_autosave())
  })

  # ── shinyFiles (static roots computed once) --------------------------------
  file_roots <- local({
    r <- c(Home = normalizePath("~", winslash = "/", mustWork = FALSE))
    if (.Platform$OS.type == "windows")
      for (d in LETTERS) { p <- paste0(d, ":/"); if (dir.exists(p)) r[d] <- p }
    r
  })
  shinyFileSave(input,   "save_browse",      roots = file_roots, session = session)
  shinyFileSave(input,   "dic_save_browse",  roots = file_roots, session = session)
  shinyFileChoose(input, "open_yaml_btn",    roots = file_roots,
                  filetypes = c("yaml", "yml"), session = session)
  shinyFileChoose(input, "dic_browse_btn",   roots = file_roots,
                  filetypes = c("DIC", "dic", "csv"), session = session)

  observeEvent(input$save_browse, {
    fp <- parseSavePath(file_roots, input$save_browse)
    if (!is.null(fp) && nrow(fp) > 0) {
      path <- fp$datapath[1]
      if (!grepl("\\.(yaml|yml)$", path, ignore.case = TRUE))
        path <- paste0(path, ".yaml")
      updateTextInput(session, "save_path", value = path)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$dic_save_browse, {
    fp <- parseSavePath(file_roots, input$dic_save_browse)
    if (!is.null(fp) && nrow(fp) > 0) {
      path <- fp$datapath[1]
      if (!grepl("\\.csv$", path, ignore.case = TRUE))
        path <- paste0(path, ".csv")
      updateTextInput(session, "dic_csv_path", value = path)
    }
  }, ignoreInit = TRUE)

  # ── Open existing YAML — auto-load dictionary, pre-fill form ---------------
  observeEvent(input$open_yaml_btn, {
    fp <- parseFilePaths(file_roots, input$open_yaml_btn)
    if (is.null(fp) || nrow(fp) == 0) return()
    path <- fp$datapath[1]

    cnt <- tryCatch(
      read_pollen_count(path),
      error = function(e) {
        showNotification(paste("Could not read YAML:", e$message),
                         type = "error"); NULL
      }
    )
    if (is.null(cnt)) return()

    m <- cnt$meta

    # ── Auto-load dictionary from saved dic_path ──
    dp <- m$dic_path %||% NA_character_
    if (!is.na(dp) && nzchar(dp)) {
      if (file.exists(dp)) {
        dic <- tryCatch(
          read_dic(dp),
          error = function(e) {
            showNotification(paste("Could not load dictionary:", e$message),
                             type = "warning"); NULL
          }
        )
        if (!is.null(dic)) {
          rv$dic        <- dic
          rv$dic_name   <- tools::file_path_sans_ext(basename(dp))
          rv$dic_path   <- dp
          rv$dic_is_csv <- tolower(tools::file_ext(dp)) == "csv"
          rv$pollen_sum <- intersect(
            unlist(m$pollen_sum_groups) %||% c("A","B","F"),
            unique(dic$group[!dic$is_special])
          )
        }
      } else {
        showNotification(
          sprintf("Dictionary '%s' not found at its saved path. Please load manually.",
                  basename(dp)),
          type = "warning", duration = 8)
      }
    }
    # If no dic_path in YAML and no dic loaded yet, pollen_sum still pre-fills
    if (is.null(rv$dic))
      rv$pollen_sum <- unlist(m$pollen_sum_groups) %||% c("A","B","F")

    # Update dic_name from source_file if still blank
    sf <- m$source_file %||% ""
    if (!nzchar(rv$dic_name) && nzchar(sf))
      rv$dic_name <- tools::file_path_sans_ext(sf)

    # Store loaded data and metadata for Resume
    rv$loaded_cnt <- cnt
    rv$loaded_meta <- list(
      sample_qty    = as.numeric(m$sample_quantity %||% 1),
      sample_units  = m$units %||% "g",
      spike_qty     = as.numeric(m$spike_tablets   %||% 2),
      spike_density = as.numeric(m$spike_density   %||% 9666),
      spike_units   = "tablets",
      conc_method   = m$conc_method    %||% "spike",
      use_pres      = if (isFALSE(m$use_pres)) FALSE else TRUE,
      title         = m$title          %||% "",
      sample_name   = m$sample_name    %||% "",
      depth_top     = suppressWarnings(as.numeric(m$depth_top    %||% NA)),
      depth_bottom  = suppressWarnings(as.numeric(m$depth_bottom %||% NA)),
      age_top       = suppressWarnings(as.numeric(m$age_top      %||% NA)),
      age_bottom    = suppressWarnings(as.numeric(m$age_bottom   %||% NA)),
      save_path     = path
    )

    rv$is_resume <- TRUE

    n_grains <- if (!is.null(cnt$grains)) nrow(cnt$grains) else 0L
    dic_msg  <- if (!is.null(rv$dic))
      sprintf(", dictionary: %s", rv$dic_name) else " — load dictionary manually"
    showNotification(
      sprintf("Loaded: %s (%d grains%s). Review and click Resume.",
              basename(path), n_grains, dic_msg),
      type = "message", duration = 8)
  }, ignoreInit = TRUE)

  # ── Dictionary UI (supports carry-over after New Sample) ------------------
  output$dic_ui <- renderUI({
    if (!is.null(rv$dic) && nzchar(rv$dic_name)) {
      fmt <- if (rv$dic_is_csv) "CSV" else "DIC"
      tagList(
        div(class = "carried-dic", "Dictionary carried from previous sample."),
        actionLink("change_dic_btn", "Change dictionary")
      )
    } else {
      tagList(
        tags$label("Dictionary file (.DIC or .csv)"),
        br(),
        shinyFilesButton("dic_browse_btn", "Browse for dictionary",
                         title    = "Select dictionary (.DIC or .csv)",
                         multiple = FALSE,
                         style    = "width:100%;background:#2d2d30;color:#d4d4d4;
                                     border:1px solid #3e3e42;margin-bottom:4px;"),
        uiOutput("dic_loaded_msg")
      )
    }
  })

  observeEvent(input$change_dic_btn, {
    rv$dic <- NULL; rv$dic_name <- ""; rv$dic_path <- ""; rv$dic_is_csv <- FALSE
  })

  output$dic_loaded_msg <- renderUI({
    if (!is.null(rv$dic) && nzchar(rv$dic_name))
      div(class = "carried-dic",
          sprintf("Loaded: %s (%d taxa)", rv$dic_name, nrow(rv$dic)))
    else NULL
  })

  observeEvent(input$dic_browse_btn, {
    fp <- parseFilePaths(file_roots, input$dic_browse_btn)
    if (is.null(fp) || nrow(fp) == 0) return()
    path <- fp$datapath[1]
    dic  <- tryCatch(
      read_dic(path),
      error = function(e) {
        showNotification(paste("Cannot read dictionary:", e$message), type = "error")
        NULL
      }
    )
    if (is.null(dic)) return()
    rv$dic        <- dic
    rv$dic_name   <- tools::file_path_sans_ext(basename(path))
    rv$dic_path   <- path
    rv$dic_is_csv <- tolower(tools::file_ext(path)) == "csv"
    rv$pollen_sum <- intersect(c("A","B","F"), unique(dic$group[!dic$is_special]))
  }, ignoreInit = TRUE)

  # ── Group checkboxes (setup page) -----------------------------------------
  output$group_ui <- renderUI({
    dic <- rv$dic
    if (is.null(dic)) return(
      p("Load a dictionary above to set ΣP groups.",
        style = "color:#a0a0a0;font-size:12px;")
    )
    grps <- sort(unique(dic$group[!dic$is_special & nzchar(dic$group)]))
    sel  <- intersect(rv$pollen_sum %||% c("A","B","F"), grps)
    checkboxGroupInput("pollen_sum_groups",
                       "ΣP — analyst defined pollen sum groups:",
                       choices = grps, selected = sel, inline = TRUE)
  })

  # ── Group checkboxes (Sample Info tab — counting page) --------------------
  output$meta_group_ui <- renderUI({
    req(rv$setup_done)
    dic <- rv$dic
    if (is.null(dic)) return(NULL)
    grps <- sort(unique(dic$group[!dic$is_special & nzchar(dic$group)]))
    checkboxGroupInput("meta_pollen_sum", NULL,
                       choices  = grps,
                       selected = isolate(rv$pollen_sum),
                       inline   = TRUE)
  })

  # ── Pre-fill setup fields after New Sample --------------------------------
  observe({
    req(rv$prefill, !rv$setup_done)
    ps <- rv$prev_setup
    if (is.null(ps)) { rv$prefill <- FALSE; return() }
    updateNumericInput(session,  "sample_qty",    value    = ps$sample_qty)
    updateRadioButtons(session,  "sample_units",  selected = ps$sample_units)
    updateNumericInput(session,  "spike_qty",     value    = ps$spike_qty)
    updateNumericInput(session,  "spike_density", value    = ps$spike_density)
    updateRadioButtons(session,  "spike_units",   selected = ps$spike_units)
    updateRadioButtons(session,  "conc_method",   selected = ps$conc_method %||% "spike")
    updateRadioButtons(session,  "use_pres",
                       selected = if (isFALSE(ps$use_pres)) "no" else "yes")
    updateTextInput(session,     "save_path",     value    = ps$next_path)
    rv$prefill <- FALSE
  })

  # ── Start / Resume counting -----------------------------------------------
  observeEvent(input$start_btn, {
    if (is.null(rv$dic)) {
      showNotification("Load a dictionary first.", type = "error"); return()
    }
    sp <- trimws(input$save_path %||% "")
    if (!nzchar(sp)) {
      showNotification("Please enter a save path.", type = "warning"); return()
    }

    # Read all metadata from the (possibly edited) form
    rv$pollen_sum    <- input$pollen_sum_groups %||% c("A","B","F")
    rv$sample_qty    <- as.numeric(input$sample_qty)
    rv$sample_units  <- input$sample_units
    rv$spike_qty     <- as.numeric(input$spike_qty)
    rv$spike_density <- as.numeric(input$spike_density)
    rv$spike_units   <- input$spike_units
    rv$conc_method   <- input$conc_method   %||% "spike"
    rv$use_pres      <- !identical(input$use_pres, "no")
    rv$title         <- trimws(input$title_line  %||% "")
    rv$sample_name <- trimws(input$sample_name %||% "")
    rv$depth_top     <- suppressWarnings(as.numeric(input$depth_top))
    rv$depth_bottom  <- suppressWarnings(as.numeric(input$depth_bottom))
    rv$age_top       <- suppressWarnings(as.numeric(input$age_top))
    rv$age_bottom    <- suppressWarnings(as.numeric(input$age_bottom))
    rv$save_path     <- sp
    rv$created       <- Sys.time()

    if (isTRUE(rv$is_resume) && !is.null(rv$loaded_cnt)) {
      if (length(rv$loaded_cnt$events) > 0) {
        # Lossless resume: full event stream read from YAML (format_version >= 2).
        # Spikes are already in the event stream; base_spike_n stays 0.
        rv$events       <- rv$loaded_cnt$events
        rv$base_spike_n <- 0L
      } else {
        # Legacy resume: reconstruct from grains/traverses/remarks.
        # Spike positions are lost but totals are correct.
        rebuilt         <- rebuild_events_from_count(rv$loaded_cnt)
        rv$events       <- rebuilt$events
        rv$base_spike_n <- rebuilt$base_spike_n
      }
      rv$slide_n      <- max(1L, sum(vapply(rv$events,
                                            function(e) e$type == "slide_desc", FALSE)))
      travs           <- Filter(function(e) e$type == "traverse", rv$events)
      rv$cur_traverse <- if (length(travs))
        travs[[length(travs)]]$label else NA_character_
      rv$loaded_cnt   <- NULL
      rv$loaded_meta  <- NULL
      rv$is_resume    <- FALSE
    } else {
      # Fresh count
      slide_id        <- trimws(input$first_slide %||% "")
      if (!nzchar(slide_id)) slide_id <- "slide-1"
      rv$events       <- list(list(type = "slide_desc", text = slide_id, position = 1L))
      rv$slide_n      <- 1L
      rv$cur_traverse <- NA_character_
      rv$base_spike_n <- 0L
    }

    rv$setup_done <- TRUE
    session$sendCustomMessage("focus_input", list())
  })

  # ── Sample Info tab — live metadata observers ----------------------------
  # These fire when the user edits fields while counting; each autosaves.

  observeEvent(input$meta_title, {
    rv$title <- input$meta_title; do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_sample_name, {
    rv$sample_name <- input$meta_sample_name; do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_depth_top, {
    rv$depth_top <- suppressWarnings(as.numeric(input$meta_depth_top)); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_depth_bottom, {
    rv$depth_bottom <- suppressWarnings(as.numeric(input$meta_depth_bottom)); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_age_top, {
    rv$age_top <- suppressWarnings(as.numeric(input$meta_age_top)); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_age_bottom, {
    rv$age_bottom <- suppressWarnings(as.numeric(input$meta_age_bottom)); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_sample_qty, {
    rv$sample_qty <- as.numeric(input$meta_sample_qty); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_sample_units, {
    rv$sample_units <- input$meta_sample_units; do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_spike_qty, {
    rv$spike_qty <- as.numeric(input$meta_spike_qty); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_spike_density, {
    rv$spike_density <- as.numeric(input$meta_spike_density); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_spike_units, {
    rv$spike_units <- input$meta_spike_units; do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_pollen_sum, {
    rv$pollen_sum <- input$meta_pollen_sum %||% character(0); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_conc_method, {
    rv$conc_method <- input$meta_conc_method %||% "spike"; do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$meta_use_pres, {
    rv$use_pres <- !identical(input$meta_use_pres, "no"); do_autosave()
  }, ignoreInit = TRUE, ignoreNULL = FALSE)

  # Sync meta fields when counting_panel first renders (setup → counting)
  observe({
    req(rv$setup_done)
    updateTextInput(session,    "meta_title",         value    = isolate(rv$title))
    updateTextInput(session,    "meta_sample_name", value    = isolate(rv$sample_name))
    updateNumericInput(session, "meta_depth_top",     value    = isolate(rv$depth_top))
    updateNumericInput(session, "meta_depth_bottom",  value    = isolate(rv$depth_bottom))
    updateNumericInput(session, "meta_age_top",       value    = isolate(rv$age_top))
    updateNumericInput(session, "meta_age_bottom",    value    = isolate(rv$age_bottom))
    updateNumericInput(session, "meta_sample_qty",    value    = isolate(rv$sample_qty))
    updateRadioButtons(session, "meta_sample_units",  selected = isolate(rv$sample_units))
    updateNumericInput(session, "meta_spike_qty",     value    = isolate(rv$spike_qty))
    updateNumericInput(session, "meta_spike_density", value    = isolate(rv$spike_density))
    updateRadioButtons(session, "meta_spike_units",   selected = isolate(rv$spike_units))
    updateRadioButtons(session, "meta_conc_method",   selected = isolate(rv$conc_method))
    updateRadioButtons(session, "meta_use_pres",
                       selected = if (isolate(rv$use_pres)) "yes" else "no")
  })

  # ── Entry logic -----------------------------------------------------------
  do_entry <- function(s) {
    s <- trimws(s %||% ""); if (!nzchar(s)) return(TRUE)
    pos <- length(rv$events) + 1L

    # Traverse: /label/ or /label (trailing slash optional)
    if (startsWith(s, "/") && nchar(s) > 1L) {
      label <- sub("^/", "", s)
      label <- sub("/$", "", label)
      if (nzchar(label)) {
        rv$cur_traverse <- label
        rv$events <- c(rv$events, list(list(type="traverse", label=label, position=pos)))
        return(TRUE)
      }
    }
    # Remark: [text] or [text (trailing bracket optional)
    if (startsWith(s, "[")) {
      txt <- sub("^\\[", "", s)
      txt <- sub("\\]$", "", txt)
      rv$events <- c(rv$events, list(list(type="remark", text=txt, position=pos,
                                          traverse=rv$cur_traverse)))
      return(TRUE)
    }
    if (s == ".") {
      rv$events <- c(rv$events, list(list(type="spike", position=pos,
                                          traverse=rv$cur_traverse)))
      return(TRUE)
    }
    if (rv$use_pres) {
      # Standard mode: code + preservation digit (e.g. I8, B1, A80)
      m <- regmatches(s, regexec("^([#$]?[A-Za-z]{1,2})([1-8])([09]*)$", s))[[1]]
      if (length(m) == 4L) {
        code   <- m[2]; base <- m[3]
        mods   <- strsplit(m[4], "")[[1]]
        half   <- "0" %in% mods; hidden <- "9" %in% mods
        pres   <- paste(unique(c(base, mods[mods != "0"])), collapse = ";")
        wt     <- if (half) 0.5 else 1.0
        idx    <- match(code, rv$dic$code)
        if (is.na(idx)) idx <- match(toupper(code), toupper(rv$dic$code))
        if (is.na(idx)) {
          session$sendCustomMessage("beep", list())
          showModal(code_alert_modal(code,
            "This code is not in the dictionary. Re-enter a known code, or open the Dictionary tab to add it."))
          return(FALSE)
        }
        rv$events <- c(rv$events, list(list(type="grain", code=rv$dic$code[idx],
                                            base=base, pres=pres, weight=wt,
                                            hidden=hidden, traverse=rv$cur_traverse,
                                            position=pos, anomaly=FALSE)))
        return(TRUE)
      }
      session$sendCustomMessage("beep", list())
      showModal(code_alert_modal(s,
        "This does not match any recognised token. Valid entries: code+digit (e.g. I8), /traverse/, [remark], or . (spike)."))
      return(FALSE)
    } else {
      # No-preservation mode: code only (e.g. I, B, A)
      m <- regmatches(s, regexec("^([#$]?[A-Za-z]{1,2})$", s))[[1]]
      if (length(m) == 2L) {
        code <- m[2]
        idx  <- match(code, rv$dic$code)
        if (is.na(idx)) idx <- match(toupper(code), toupper(rv$dic$code))
        if (is.na(idx)) {
          session$sendCustomMessage("beep", list())
          showModal(code_alert_modal(code,
            "This code is not in the dictionary. Re-enter a known code, or open the Dictionary tab to add it."))
          return(FALSE)
        }
        rv$events <- c(rv$events, list(list(type="grain", code=rv$dic$code[idx],
                                            base=NA_character_, pres=NA_character_,
                                            weight=1.0, hidden=FALSE,
                                            traverse=rv$cur_traverse,
                                            position=pos, anomaly=FALSE)))
        return(TRUE)
      }
      session$sendCustomMessage("beep", list())
      showModal(code_alert_modal(s,
        "This does not match any recognised token. Valid entries: taxon code only (e.g. I), /traverse/, [remark], or . (spike)."))
      return(FALSE)
    }
  }

  observeEvent(input$entry_submit, {
    val      <- input$entry_submit$value %||% ""
    consumed <- do_entry(val)
    session$sendCustomMessage("scroll", list())
    if (consumed) { session$sendCustomMessage("focus_input", list()); grain_save_pending(grain_save_pending() + 1L) }
  }, ignoreInit = TRUE)

  # ── Entry alert modal (unknown code / malformed input) -------------------
  observeEvent(input$alert_reenter_btn, {
    removeModal()
    session$sendCustomMessage("focus_input", list())
  })
  observeEvent(input$alert_edit_dic_btn, {
    removeModal()
    updateTabsetPanel(session, "input_tabs", selected = "Dictionary")
    session$sendCustomMessage("focus_input", list())
  })

  # ── Traverse button -------------------------------------------------------
  observeEvent(input$new_trav_btn,    { showModal(traverse_modal()) })
  observeEvent(input$confirm_trav_btn, {
    label <- trimws(input$trav_label %||% "")
    if (!nzchar(label)) { showNotification("Label required.", type="warning"); return() }
    pos <- length(rv$events) + 1L
    rv$cur_traverse <- label
    rv$events <- c(rv$events, list(list(type="traverse", label=label, position=pos)))
    removeModal()
    session$sendCustomMessage("scroll", list())
    session$sendCustomMessage("focus_input", list())
    do_autosave()
  })

  # ── Remark button ---------------------------------------------------------
  observeEvent(input$new_remark_btn,     { showModal(remark_modal()) })
  observeEvent(input$confirm_remark_btn, {
    txt <- trimws(input$remark_text %||% "")
    if (!nzchar(txt)) { showNotification("Remark text required.", type="warning"); return() }
    pos <- length(rv$events) + 1L
    rv$events <- c(rv$events, list(list(type="remark", text=txt, position=pos,
                                        traverse=rv$cur_traverse)))
    removeModal()
    session$sendCustomMessage("scroll", list())
    session$sendCustomMessage("focus_input", list())
    do_autosave()
  })

  # ── Undo -----------------------------------------------------------------
  observeEvent(input$undo_btn, {
    evs <- rv$events; if (length(evs) <= 1L) return()
    rv$events <- evs[-length(evs)]
    travs <- Filter(function(e) e$type=="traverse", rv$events)
    rv$cur_traverse <- if (length(travs)) travs[[length(travs)]]$label else NA_character_
    rv$slide_n <- max(1L, sum(vapply(rv$events, function(e) e$type=="slide_desc", FALSE)))
    do_autosave()
    session$sendCustomMessage("focus_input", list())
  })

  # ── New Slide modal -------------------------------------------------------
  observeEvent(input$new_slide_btn, {
    showModal(modalDialog(
      title = "New Slide",
      textInput("new_slide_id", "Slide ID",
                placeholder = sprintf("%s-%d", rv$title, rv$slide_n + 1L)),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_slide_btn", "Start Slide", class="btn-info")
      )
    ))
  })
  observeEvent(input$confirm_slide_btn, {
    sid <- trimws(input$new_slide_id %||% "")
    if (!nzchar(sid)) sid <- sprintf("slide-%d", rv$slide_n + 1L)
    pos <- length(rv$events) + 1L
    rv$events  <- c(rv$events, list(list(type="slide_desc", text=sid, position=pos)))
    rv$slide_n <- rv$slide_n + 1L
    rv$cur_traverse <- NA_character_
    removeModal(); do_autosave()
    session$sendCustomMessage("focus_input", list())
  })

  # ── Done / Save -----------------------------------------------------------
  observeEvent(input$done_btn, {
    do_autosave()
    showNotification(paste("Saved to:", rv$save_path), type="message", duration=8)
  })

  # ── New Sample ------------------------------------------------------------
  observeEvent(input$new_sample_click, {
    do_autosave()
    rv$prev_setup <- list(
      sample_qty    = rv$sample_qty,
      sample_units  = rv$sample_units,
      spike_qty     = rv$spike_qty,
      spike_density = rv$spike_density,
      spike_units   = rv$spike_units,
      conc_method   = rv$conc_method,
      use_pres      = rv$use_pres,
      pollen_sum    = rv$pollen_sum,
      next_path     = next_save_path(rv$save_path)
    )
    rv$events        <- list()
    rv$slide_n       <- 0L
    rv$cur_traverse  <- NA_character_
    rv$base_spike_n  <- 0L
    rv$sample_name <- ""
    rv$depth_top     <- NA_real_
    rv$depth_bottom  <- NA_real_
    rv$age_top       <- NA_real_
    rv$age_bottom    <- NA_real_
    rv$is_resume     <- FALSE
    rv$loaded_cnt    <- NULL
    rv$loaded_meta   <- NULL
    rv$setup_done    <- FALSE
    rv$prefill       <- TRUE
  })

  # ── Derived state --------------------------------------------------------
  grains_rv <- reactive({
    glist <- Filter(function(e) e$type=="grain", rv$events)
    if (!length(glist)) return(data.frame(code=character(0), base=character(0),
                                          pres=character(0), weight=numeric(0),
                                          hidden=logical(0), traverse=character(0),
                                          position=integer(0), stringsAsFactors=FALSE))
    data.frame(
      code     = vapply(glist, `[[`, "",    "code"),
      base     = vapply(glist, `[[`, "",    "base"),
      pres     = vapply(glist, `[[`, "",    "pres"),
      weight   = vapply(glist, `[[`, 0.0,   "weight"),
      hidden   = vapply(glist, `[[`, FALSE, "hidden"),
      traverse = vapply(glist, function(e) e$traverse %||% NA_character_, ""),
      position = vapply(glist, `[[`, 0L,    "position"),
      stringsAsFactors = FALSE)
  })

  tallies_rv <- reactive({
    g <- grains_rv(); dic <- rv$dic
    if (is.null(dic) || !nrow(g)) return(list(total=0, basic=0))
    is_spc <- grepl("^[#.]", g$code)
    grp    <- dic$group[match(g$code, dic$code)]
    total  <- sum(g$weight[!is_spc], na.rm=TRUE)
    basic  <- sum(g$weight[!is_spc & !is.na(grp) & grp %in% rv$pollen_sum], na.rm=TRUE)
    list(total=total, basic=basic)
  })

  top_taxa_rv <- reactive({
    g <- grains_rv(); dic <- rv$dic
    if (is.null(dic) || !nrow(g)) return(NULL)
    basic <- tallies_rv()$basic; if (basic == 0) return(NULL)
    is_spc <- grepl("^[#.]", g$code)
    tx <- sort(tapply(g$weight[!is_spc], g$code[!is_spc], sum), decreasing=TRUE)
    tx <- head(tx, 10)
    data.frame(code=names(tx), count=as.numeric(tx),
               pct=round(as.numeric(tx)/basic*100), stringsAsFactors=FALSE)
  })

  # ── Running concentration and PAR ----------------------------------------
  conc_par_rv <- reactive({
    basic   <- tallies_rv()$basic
    spike_n <- rv$base_spike_n +
               sum(vapply(rv$events, function(e) e$type == "spike", FALSE))

    # Concentration: method-dependent
    conc <- NA_real_
    if (rv$conc_method == "spike") {
      if (basic > 0 && spike_n > 0 &&
          !is.na(rv$spike_qty)     && rv$spike_qty     > 0 &&
          !is.na(rv$spike_density) && rv$spike_density > 0 &&
          !is.na(rv$sample_qty)    && rv$sample_qty    > 0) {
        conc <- (basic / spike_n) * (rv$spike_qty * rv$spike_density) / rv$sample_qty
      }
    } else if (rv$conc_method == "volumetric") {
      if (basic > 0 && !is.na(rv$sample_qty) && rv$sample_qty > 0) {
        conc <- basic / rv$sample_qty
      }
    }
    # "none": conc stays NA

    # PAR: concentration / deposition_time  [grains/cm²/yr]
    # deposition_time = (age_bottom - age_top) / (depth_bottom - depth_top)  [yr/cm]
    par <- NA_real_
    if (!is.na(conc) &&
        !is.na(rv$depth_top)    && !is.na(rv$depth_bottom)  &&
        !is.na(rv$age_top)      && !is.na(rv$age_bottom)    &&
        rv$depth_bottom > rv$depth_top &&
        rv$age_bottom   > rv$age_top) {
      dt  <- (rv$age_bottom - rv$age_top) / (rv$depth_bottom - rv$depth_top)
      if (dt > 0) par <- conc / dt
    }

    list(conc  = conc,
         par   = par,
         units = if (identical(rv$sample_units, "ml")) "grains/cm³" else "grains/g")
  })

  output$stat_conc_label <- renderText({
    paste0("Conc (", conc_par_rv()$units, ")")
  })
  output$stat_conc <- renderText({
    v <- conc_par_rv()$conc
    if (is.na(v)) "NA" else formatC(round(v), format = "d", big.mark = ",")
  })
  output$stat_par <- renderText({
    v <- conc_par_rv()$par
    if (is.na(v)) "NA" else formatC(round(v), format = "d", big.mark = ",")
  })

  # ── Autosave -------------------------------------------------------------
  do_autosave <- function() {
    if (!rv$setup_done || !nzchar(rv$save_path)) return()
    g     <- grains_rv()
    travs <- vapply(Filter(function(e) e$type=="traverse", rv$events),
                    function(e) e$label, "")
    rems  <- lapply(Filter(function(e) e$type=="remark", rv$events),
                    function(e) list(text=e$text, position=e$position,
                                     traverse=e$traverse %||% NA_character_))
    tryCatch({
      cnt <- pollen_count(
        grains=g,
        spike_n=rv$base_spike_n +
                sum(vapply(rv$events, function(e) e$type=="spike", FALSE)),
        traverses=travs, remarks=rems, events=rv$events,
        sample_quantity=rv$sample_qty, units=rv$sample_units,
        spike_tablets=rv$spike_qty, spike_density=rv$spike_density,
        pollen_sum_groups=rv$pollen_sum, title=rv$title,
        sample_name=rv$sample_name,
        dic_path=rv$dic_path,
        depth_top=rv$depth_top,   depth_bottom=rv$depth_bottom,
        age_top=rv$age_top,       age_bottom=rv$age_bottom,
        source_file=basename(rv$save_path),
        conc_method=rv$conc_method,
        use_pres=rv$use_pres)
      write_pollen_count(cnt, rv$save_path)
    }, error=function(e) invisible(NULL))
  }

  # ── Grain table editing --------------------------------------------------
  observeEvent(input$grain_tbl_cell_edit, {
    info <- input$grain_tbl_cell_edit
    col  <- info$col
    val  <- as.character(info$value)

    find_and_update <- function(update_fn) {
      grain_n <- 0L
      for (i in seq_along(rv$events)) {
        if (rv$events[[i]]$type == "grain") {
          grain_n <- grain_n + 1L
          if (grain_n == info$row) { update_fn(i); break }
        }
      }
    }

    if (col == 0L) {
      idx <- match(val, rv$dic$code)
      if (is.na(idx)) idx <- match(toupper(val), toupper(rv$dic$code))
      if (is.na(idx)) {
        showNotification(sprintf("'%s' not in dictionary — edit not applied.", val),
                         type = "warning")
        return()
      }
      canon <- rv$dic$code[idx]
      find_and_update(function(i) rv$events[[i]]$code <- canon)

    } else if (col == 1L) {
      if (!rv$use_pres) {
        showNotification("Preservation codes are disabled for this count.",
                         type = "warning")
        return()
      }
      m <- regmatches(val, regexec("^([1-8])([09]*)$", val))[[1]]
      if (length(m) < 3) {
        showNotification(
          "Invalid preservation code. Use base digit (1–8) + optional modifiers (0=half, 9=hidden).",
          type = "warning")
        return()
      }
      base   <- m[2]
      mods   <- strsplit(m[3], "")[[1]]
      half   <- "0" %in% mods
      hidden <- "9" %in% mods
      pres   <- paste(unique(c(base, mods[mods != "0"])), collapse = ";")
      wt     <- if (half) 0.5 else 1.0
      find_and_update(function(i) {
        rv$events[[i]]$base   <- base
        rv$events[[i]]$pres   <- pres
        rv$events[[i]]$weight <- wt
        rv$events[[i]]$hidden <- hidden
      })

    } else if (col == 2L) {
      wt <- suppressWarnings(as.numeric(val))
      if (is.na(wt) || !wt %in% c(0.5, 1.0)) {
        showNotification("Weight must be 0.5 (half-grain) or 1.0 (full grain).",
                         type = "warning")
        return()
      }
      find_and_update(function(i) rv$events[[i]]$weight <- wt)
    }
    do_autosave()
  })

  # ── Dictionary tab — table -----------------------------------------------
  output$dic_tbl <- DT::renderDT({
    dic <- rv$dic
    if (is.null(dic)) return(NULL)
    DT::datatable(
      dic[, c("code","alias","group","name","is_special"), drop = FALSE],
      editable = list(target = "cell"),
      options  = list(pageLength = 30, dom = "ftp", scrollX = TRUE),
      rownames = FALSE, selection = "none"
    )
  }, server = TRUE)

  # Dictionary cell edit
  observeEvent(input$dic_tbl_cell_edit, {
    info     <- input$dic_tbl_cell_edit
    col_names <- c("code","alias","group","name","is_special")
    col_name  <- col_names[info$col + 1L]
    val       <- as.character(info$value)
    if (col_name == "is_special") {
      rv$dic[[col_name]][info$row] <- isTRUE(as.logical(val))
    } else {
      rv$dic[[col_name]][info$row] <- val
    }
    class(rv$dic) <- c("pollen_dictionary", "data.frame")
  }, ignoreInit = TRUE)

  # Dictionary — Add Row modal
  observeEvent(input$dic_add_row_btn, {
    grps <- if (!is.null(rv$dic))
      sort(unique(rv$dic$group[!rv$dic$is_special & nzchar(rv$dic$group)]))
    else character(0)
    showModal(modalDialog(
      title = "Add Dictionary Row",
      fluidRow(
        column(4, textInput("new_dic_code",  "Code:",
                            placeholder = "e.g. Q")),
        column(4, textInput("new_dic_group", "Group:",
                            placeholder = "e.g. A")),
        column(4, textInput("new_dic_alias", "Alias (optional):", value = ""))
      ),
      textInput("new_dic_name", "Full name:", placeholder = "e.g. Quercus"),
      checkboxInput("new_dic_special",
                    "Special marker (non-pollen, e.g. #NPP code)?",
                    value = FALSE),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_add_dic_row_btn", "Add", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$confirm_add_dic_row_btn, {
    code <- trimws(input$new_dic_code %||% "")
    name <- trimws(input$new_dic_name %||% "")
    if (!nzchar(code) || !nzchar(name)) {
      showNotification("Code and Name are required.", type = "warning"); return()
    }
    new_row <- data.frame(
      code       = code,
      alias      = trimws(input$new_dic_alias  %||% ""),
      group      = trimws(input$new_dic_group  %||% ""),
      name       = name,
      is_special = isTRUE(input$new_dic_special),
      stringsAsFactors = FALSE
    )
    rv$dic <- rbind(rv$dic, new_row)
    class(rv$dic) <- c("pollen_dictionary","data.frame")
    removeModal()
    showNotification(sprintf("'%s' added. Click Save Dictionary to write to disk.",
                             code), type = "message", duration = 5)
  })

  # Dictionary — Save Dictionary button
  observeEvent(input$dic_save_btn, {
    if (is.null(rv$dic)) {
      showNotification("No dictionary loaded.", type = "warning"); return()
    }
    if (rv$dic_is_csv && nzchar(rv$dic_path)) {
      tryCatch({
        write_dic_csv(rv$dic, rv$dic_path)
        showNotification(paste("Dictionary saved:", basename(rv$dic_path)),
                         type = "message", duration = 5)
      }, error = function(e)
        showNotification(paste("Save failed:", e$message), type = "error"))
    } else {
      # .DIC or no path — prompt for CSV path
      showModal(modalDialog(
        title = "Save Dictionary as CSV",
        p("The current dictionary is in .DIC format (read-only for write-back). Choose a CSV path to save an editable copy. The app will use this CSV from now on."),
        tags$label("Save as:"),
        fluidRow(
          column(8, textInput("dic_csv_path", NULL,
                              placeholder = "Type a .csv path or Browse")),
          column(4, shinySaveButton("dic_save_browse", "Browse",
                                    title    = "Save dictionary as CSV",
                                    filetype = list(csv = c("csv")),
                                    style    = "width:100%;margin-top:0;"))
        ),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_dic_csv_save_btn", "Save", class = "btn-primary")
        )
      ))
    }
  })

  observeEvent(input$confirm_dic_csv_save_btn, {
    path <- trimws(input$dic_csv_path %||% "")
    if (!nzchar(path)) {
      showNotification("Enter or browse to a save path.", type = "warning"); return()
    }
    if (!grepl("\\.csv$", path, ignore.case = TRUE)) path <- paste0(path, ".csv")
    tryCatch({
      write_dic_csv(rv$dic, path)
      rv$dic_path   <- path
      rv$dic_is_csv <- TRUE
      rv$dic_name   <- tools::file_path_sans_ext(basename(path))
      removeModal()
      showNotification(paste("Dictionary saved as CSV:", basename(path)),
                       type = "message", duration = 5)
    }, error = function(e)
      showNotification(paste("Save failed:", e$message), type = "error"))
  })

  output$dic_save_status <- renderUI({
    if (!is.null(rv$dic) && rv$dic_is_csv && nzchar(rv$dic_path))
      div(style = "color:#4ec9b0;font-size:11px;padding-top:8px;",
          basename(rv$dic_path))
    else if (!is.null(rv$dic) && !rv$dic_is_csv)
      div(style = "color:#e5c07b;font-size:11px;padding-top:8px;",
          ".DIC — click Save to convert")
    else NULL
  })

  # ── Outputs --------------------------------------------------------------
  output$main_ui <- renderUI({
    if (!rv$setup_done)
      setup_panel(rv$is_resume, rv$loaded_meta)
    else
      counting_panel()
  })

  output$stream_out <- renderText({
    req(rv$setup_done)
    render_stream(rv$events, rv$dic_name, rv$sample_qty, rv$spike_qty,
                  rv$spike_density, rv$sample_units, rv$pollen_sum,
                  rv$title, rv$created, rv$use_pres)
  })
  output$stat_total    <- renderText(sprintf("%.1f", tallies_rv()$total))
  output$stat_basic    <- renderText(sprintf("%.1f", tallies_rv()$basic))
  output$stat_slide    <- renderText(as.character(rv$slide_n))
  output$stat_trav     <- renderText(as.character(
    sum(vapply(rv$events, function(e) e$type=="traverse", FALSE))))
  output$stat_spike    <- renderText(as.character(
    rv$base_spike_n +
    sum(vapply(rv$events, function(e) e$type=="spike", FALSE))))
  output$stat_cur_trav <- renderText({
    trav <- rv$cur_traverse
    if (is.null(trav)||(length(trav)==1L&&is.na(trav))) "current traverse: —"
    else paste0("current traverse: /", trav, "/")
  })
  output$save_msg <- renderText({
    sp <- rv$save_path %||% ""
    if (nzchar(sp)) paste0("autosaving → ", basename(sp)) else ""
  })
  output$taxon_bar <- renderUI({
    tx   <- top_taxa_rv(); show <- rv$show_pct
    tog  <- actionButton("toggle_btn", if(show) "Show #" else "Show %",
                         style = "background:#3e3e42;color:#d4d4d4;
                                  font-size:11px;padding:4px 8px;border:1px solid #6b6b6b;")
    if (is.null(tx)||!nrow(tx))
      return(div(class="taxon-strip", tog,
                 span("No grains counted yet.", style="color:#a0a0a0")))
    cells <- lapply(seq_len(nrow(tx)), function(i) {
      val <- if(show) paste0(tx$pct[i],"%") else as.character(tx$count[i])
      div(class="taxon-cell",
          div(class="t-code", tx$code[i]),
          div(class="t-val",  val))
    })
    div(class="taxon-strip", tog, do.call(tagList, cells))
  })
  observeEvent(input$toggle_btn, { rv$show_pct <- !rv$show_pct })

  output$grain_tbl <- DT::renderDT({
    req(input$input_tabs == "Grain History")
    g <- grains_rv()
    empty <- DT::datatable(
      data.frame(Code=character(0), Preservation=character(0),
                 Weight=numeric(0), Traverse=character(0)),
      options = list(dom="t"), rownames = FALSE)
    if (!nrow(g)) return(empty)

    notation <- vapply(seq_len(nrow(g)), function(i) {
      b <- g$base[i]
      if (is.na(b) || !nzchar(b)) return("—")  # em-dash for no-pres mode
      parts  <- strsplit(g$pres[i], ";")[[1]]
      base   <- parts[1]
      extras <- parts[-1]
      mods   <- paste0(c(extras, if (g$weight[i] == 0.5) "0" else character(0)),
                       collapse = "")
      paste0(base, mods)
    }, "")

    DT::datatable(
      data.frame(Code         = g$code,
                 Preservation = notation,
                 Weight       = g$weight,
                 Traverse     = g$traverse,
                 stringsAsFactors = FALSE),
      editable  = list(target  = "cell",
                       disable = list(columns = c(3L))),
      options   = list(pageLength=25, dom="tip", scrollX=TRUE),
      rownames  = FALSE, selection = "none")
  }, server = TRUE)
}

# ── Launch -------------------------------------------------------------------

ui <- fluidPage(
  tags$head(tags$style(APP_CSS), tags$script(APP_JS)),
  uiOutput("main_ui")
)

shinyApp(ui, server)
