# pcountr NEWS / changelog

## pcountr 0.5.0

Naming and export release. `as_rioja()` renamed to `site_matrix()`; new
`write_tlx()` exports a site to Tilia XML for Neotoma upload. 313 test
assertions pass.

### `as_rioja()` → `site_matrix()`

- **`site_matrix()`** replaces `as_rioja()`. The function is identical in
  behaviour; only the name has changed to reflect that the output matrix is
  not rioja-specific — it is used for plotting, export, and any downstream
  analysis.
- **`as_rioja()` was retained as a deprecated wrapper** in this release and
  removed in v0.5.1. Use `site_matrix()` directly.

### `write_tlx()` — Tilia XML export

Exports a loaded `pollen_site` to a `.tlx` file readable by Tilia and
suitable for Neotoma upload:

- **Four spreadsheet pages**: Data (weighted counts), Percents (analyst's
  configured ΣP groups), Concentrations (Stockmarr equation), and Influx
  (accumulation rates). CONISS is omitted — compute it in Tilia or `rioja`.
- **CONC metadata rows** per sample: age (`#Chron1`), depth (`#depth`),
  spike counted, sample quantity (unit-aware: `volume:ml` or `weight:g`),
  tablets added, tablet concentration, deposition time (yr/cm).
- **Stratigraphic ordering** uses the first available of `depth_top`,
  `sample_number` (supports negative values for field-extracted samples),
  then `age_top`. Errors if none is present.
- **Only observed taxa** (weighted count ≥ 1 in at least one sample) are
  written. All taxa including `#`-prefixed non-pollen palynomorphs appear in
  the regular taxon section.
- **Site and CollectionUnit stubs** are left empty for completion in Tilia.
- Output filename is user-specified.

---

## pcountr 0.5.1

### Documentation refocus

- **DESCRIPTION** retitled and rewritten to lead with `count_app()` as the
  primary interface. Broader proxy support (diatoms, charcoal morphotypes,
  phytoliths) noted explicitly.
- **README** restructured: `count_app()` is now the first function listed and
  the quick-start example leads with a counting session. A "Not just pollen"
  section added.
- **New vignette: `counting.Rmd`** — *Counting at the Microscope* — the primary
  workflow vignette. Covers the setup screen, input token syntax, live metrics,
  autosave/resume, and the full post-counting pipeline (load → plot → TLX).
  Includes a "Non-pollen applications" section.
- **`workflow.Rmd` renamed to `legacy.Rmd`** — retitled *Legacy Workflow: CNT
  Files to Tilia XML*. A callout at the top directs new users to `counting.Rmd`.
- Author ORCID (0000-0003-4853-5429) added to `DESCRIPTION` and `README`.

### Deprecated wrappers removed

- **`as_rioja()`** removed. Use `site_matrix()` directly.
- **`set_depth_age()`** and **`set_depth()`** removed. Use `set_metadata()` directly.

### `inst/extdata/fake_lake/ECG.csv` — modernized dictionary

A CSV-format version of the ECG dictionary with updated taxonomy is now bundled
with the Fake Lake example data. Key updates relative to the original `ECG.DIC`:
Lycopodium split (*Spinulum*, *Diphasiastrum*, *Lycopodiella*, *Huperzia*,
*Dendrolycopodium*); Petalostemum → *Dalea*; Dodecatheon → *Primula*;
Kochia → *Bassia*; Cornus stolonifera → *C. sericea*; Potamogeton subgen.
Coleogeton → *Stuckenia*; Chenopodiaceae → Amaranthaceae; Asteraceae subfamily
names updated to current usage. Both vignettes now pass this CSV as the
dictionary rather than auto-detecting `ECG.DIC`.

### `write_tlx()` — revised and expanded Tilia XML export

The Tilia XML exporter has been substantially revised to match Tilia's own
output format and to include all information needed for concentration and
accumulation-rate calculations:

- **Four spreadsheet pages**: Data (weighted counts), Percents, Concentrations
  (Stockmarr equation), and Accumulation (accumulation rates). Page names
  match Tilia's conventions.
- **Nine shared metadata header rows (rows 3–11)** appear on every page,
  identical to the structure Tilia produces: `#Chron1` (Age top, cal yr BP),
  `#Chron2` (Age bottom), `#Depth1` (Depth top, cm), `#Depth2` (Depth
  bottom), Lycopodium spike counted, sample quantity (unit-aware), tablets
  added, tablet concentration, and deposition time (yr/cm). Taxon rows begin
  at row 12.
- **Row 1** holds `depth_top` as the column display header; **row 2** holds
  the analyst's `sample_name` label (e.g. `"KF24sh#001"`).
- **CONC group** is assigned only to spike, sample-quantity, and tablet rows;
  depth and deposition-time rows intentionally have no group, matching Tilia's
  behaviour.
- **Stratigraphic ordering** uses `depth_top` first, then the trailing number
  in `sample_name`, then `age_top`.

### `sample_number` → `sample_name`

The per-sample identifier field has been renamed throughout the package to
better reflect its intended use across multi-drive cores where sample numbers
restart:

- **`pollen_count()`** parameter renamed from `sample_number` to `sample_name`.
  Accepts free-text labels such as `"KF24sh#001"` and `"KF24-1A#001"`.
- **YAML read path** is backward-compatible: files written with `sample_number`
  load correctly (`sample_number` is read as `sample_name`).
- **Counting app** setup page and Sample Info tab now show "Sample name" with
  placeholder `"e.g. KF24sh#001"`. The field accepts any text string.
- **`write_tlx()`** writes `sample_name` to row 2 of each sample column as
  plain text (no zero-padding).

### `set_depth_age()` → `set_metadata()`

`set_depth_age()` has been renamed to `set_metadata()` and expanded to cover
all per-sample metadata fields:

- **New fields**: `sample_name`, `sample_quantity`, `sample_units`,
  `spike_tablets`, `spike_density`, `spike_units` (`"tablets"`, `"ml"`, or
  `"g"`).
- **NULL-default semantics**: only arguments that are explicitly supplied
  overwrite the existing value — omitted fields are left unchanged.
- `set_depth_age()` and `set_depth()` have been removed; use `set_metadata()` directly.
- `spike_units` added to the `pollen_count` data model and YAML format
  (backward-compatible: existing files without the field load as `NA`).
- `inst/templates/metadata_template.csv` updated with all new columns and a
  ready-to-paste loop for calling `set_metadata()` across an entire site.

### `preview_sample()` removed

`preview_sample()` has been removed. The `site_matrix()` → `rioja::strat.plot()`
workflow is the preferred route for stratigraphic visualisation; inserting a
single in-progress sample into the diagram did not add enough value to justify
maintaining a separate function.

### `rarefaction()` — optimal pollen sum analysis

Determines the minimum pollen count needed for a statistically representative
sample, per-sample across a loaded site:

- **Method**: pollen grains in each sample are randomly rearranged `n_sim`
  times (default 100). Cumulative taxon richness is tracked across each
  permutation using an O(N) duplicated-position approach.
- **Optimal pollen sum**: the smallest count at which the mean rarefaction
  curve reaches `threshold` (default 90%) of the sample's observed richness —
  consistent with the criterion "the minimum pollen count that assures the
  presence of at least 90% of the terrestrial pollen types."
- **Output**: a `pollen_rarefaction` S3 object with a summary data frame
  (sample, depth, n\_grains, n\_taxa, threshold\_taxa, optimal\_sum,
  meets\_optimal, pct\_asymptote) and per-sample curve lists (mean ± 95% CI).
- **Half-grains** (preservation weight 0.5) are rounded up (ceiling) to the
  nearest integer before rarefaction.
- **Filters**: optional `depth_range` and `age_range` arguments restrict
  analysis to a stratigraphic window; defaults to the full record.
- **Groups**: uses the same analyst-defined ΣP denominator as `site_matrix()`.

---

## pcountr 0.4.0

Analysis and data-model release. Shiny app gains lossless resume; `as_rioja()`
is substantially expanded. 287 test assertions pass.

### Shiny app — lossless resume

- **Full event stream serialised to YAML** (format version 2). Every grain,
  spike, traverse, and remark is written to the YAML in counting order, so
  spike positions are preserved exactly on resume. The legacy `grains`,
  `traverses`, and `remarks` fields are still written alongside for human
  readability and external-tool compatibility.
- **`read_pollen_count()` takes a lossless path** when the `events` field is
  present in the YAML; falls back to the v1 reconstruction path for older files
  (backward compatible — all pre-v0.4.0 YAMLs still load correctly).
- **`count_app()` resume branch** uses the event list directly when available
  (lossless); falls back to `rebuild_events_from_count()` for v1 YAMLs.

### `as_rioja()` and `preview_sample()` — expanded return object

Both functions now return a richer list covering everything needed for
concentration and accumulation-rate calculations:

- **Renamed fields**: `TaxaPerc` (was `spec`), `DepTop` / `DepBot` / `AgeTop` /
  `AgeBot` (were `depth_top` etc.). "Taxa" is used in place of "Spec" throughout
  because species-level identification is generally not possible from pollen
  morphology.
- **New per-sample scalar vectors**: `SampleSize`, `SpikeCount`, `SpikeAdded`,
  `SpikeConc` — all required inputs for the concentration equation.
- **`TaxaCount`** — raw weighted grain counts per taxon per sample (half-grains
  count as 0.5), same dimensions as `TaxaPerc`.
- **`TaxaConc`** — per-taxon concentration (Stockmarr equation):
  `TaxaCount × (SpikeAdded × SpikeConc) / (SpikeCount × SampleSize)`.
  `NA` for any sample missing required inputs.
- **`TaxaAccRate`** — per-taxon accumulation rate: `TaxaConc / deposition_time`
  where `deposition_time = (AgeBot − AgeTop) / (DepBot − DepTop)`. `NA` for
  any sample missing depth or age intervals.

### Attribution

- Eric Grimm (1951–2020) credit added to `DESCRIPTION`, `README.md`,
  `DESIGN.md`, and roxygen `@references` tags on `read_cnt()` and `read_dic()`.

---

## pcountr 0.3.0

Counting-app polish release. All changes are in the Shiny app and the YAML
data model; the analytical R functions and test suite are unchanged (279
assertions still pass).

### Counting app — setup flow

- **"Open Existing Count" moved to the top** of the setup page, above the
  dictionary section.
- **Dictionary auto-loads on resume.** The YAML now stores the full path of
  the dictionary used for the count (`dic_path` field). When a past count is
  opened, the dictionary loads automatically. If the file has moved or the
  count was made on a different machine, a notification prompts for manual
  load.
- **Metadata review before resuming.** Loading a YAML no longer jumps directly
  into counting. All metadata fields are pre-filled in the setup form so the
  analyst can review and edit before clicking "Resume Count".

### Counting app — mid-count editing

- **Sample Info tab** (new): title, sample number, depth top/bottom, age
  top/bottom, sample quantity/units, spike quantity/density/units, and ΣP
  groups are all editable while counting. Changes take effect immediately and
  autosave.
- **Dictionary tab** (new): full dictionary view with inline cell editing,
  an Add Row dialog, and a Save Dictionary button. If the source dictionary is
  in `.DIC` format (read-only), Save prompts for a CSV path and converts
  automatically.

### Counting app — entry alerts

- **Unknown code** and **malformed input** (e.g. `I8A1` typed instead of `I8`
  then `A1` separately) now trigger the same large modal with an audio beep.
  The offending entry is displayed prominently. Two actions are offered:
  **Re-enter** (dismiss and retype) or **Edit Dictionary** (jump to the
  Dictionary tab). The previous radio-button correct/add/delete dialog is
  removed.

### Counting app — live metrics

- **Running concentration and PAR** are displayed in the stats panel below the
  ΣP sum. Concentration updates on every entry once spike parameters and
  sample quantity are set. PAR additionally requires depth and age top/bottom;
  both fields show `NA` until all required inputs are present.

### Data model

- `pollen_count()` gains a `dic_path` parameter: full path to the dictionary
  file, written to and read from YAML. Enables dictionary auto-load on resume;
  transparent to all other analytical functions.

---

## pcountr 0.2.0

Major feature release. Adds interactive counting, site-level analysis, and a
modern CSV dictionary format on top of the verified v0.1.0 spine.

### Counting app

- `count_app()`: launch a Shiny-based interactive pollen counting application.
  - Setup screen: dictionary (`.DIC` or `.csv`), sample quantity/units, spike
    quantity/density/units, analyst-defined ΣP groups, sample number, depth,
    age (years BP), first slide ID, sample title, YAML save path (with file
    browser).
  - Keystroke-driven counting: `B1` (grain), `.` (spike), `/label/` (traverse),
    `[text]` (remark) — all inline, Enter to confirm.
  - Traverse and Remark buttons for mouse-driven entry.
  - New Slide button with slide-ID prompt.
  - Live running totals: Σ (all taxa), ΣP (analyst defined), traverses, spike.
  - Taxon bar: top 10 taxa by ΣP%, with count/% toggle.
  - Unknown-code modal: correct, add to dictionary, or delete.
  - Grain History tab: full editable table (code, preservation notation
    including half-grain `0`, weight); mid-count ID corrections supported.
  - Undo (multi-level).
  - Autosave to YAML on every entry.
  - New Sample: closes current count, carries over instrument metadata,
    suggests an incremented save path.
  - Open Existing Count: resume a past YAML (grains, traverses, remarks, and
    spike total restored; individual spike positions are not stored in YAML).
  - WCAG 2.1 AA compliant dark colour scheme throughout.
  - Requires: `shiny`, `DT`, `shinyFiles`.

### Dictionary

- `read_dic()` now auto-detects format by extension: `.DIC` → legacy
  fixed-column parser (unchanged); `.csv` → new CSV reader.
- `read_dic_csv()`: reads the pcountr CSV dictionary format. Columns `code`,
  `name`, `group` are required; `alias` and `is_special` are optional and
  inferred when absent. Column names matched case-insensitively.
- `write_dic_csv()`: serialise any `pollen_dictionary` to CSV. One-line
  migration: `write_dic_csv(read_dic("ECG.DIC"), "ECG.csv")`.
- `inst/extdata/dictionary_template.csv`: copy-and-customise template for new
  sites, with a companion README explaining every column.
- When the Shiny app's source dictionary is a CSV, "Add to dictionary" writes
  the new taxon back to that file persistently.

### Site-level analysis

- `read_site()`: load a folder of `.CNT` and/or `.yaml` files as a
  `pollen_site` with all samples ordered by depth. Accepts an optional depth/age
  metadata sheet (CSV or TSV, column-name-mappable via `col_map`). Warns on
  mismatched rows; errors on YAML/sheet depth conflicts (overridable with
  `ignore_depth_conflicts`). Depth not required to load — only to order or plot.
- `set_depth()`: set or update depth and age for a single sample; re-sorts the
  site automatically.
- `pollen_site()` gains a `samples` slot; `print.pollen_site()` reports sample
  count and depth range.
- `inst/extdata/LM_depths.txt`: real depth sheet for the 20-sample Little
  Mosquito Lake extdata site.

### Stratigraphic output

- `as_rioja()`: produce a wide samples × taxa percentage matrix for
  `rioja::strplot()`. Configurable percentage denominator (`groups`), taxon
  labels (`taxon_label`), and minimum-presence filter (`min_present`). Excludes
  depth-less samples with a message.
- `preview_sample()`: insert a single in-progress `pollen_count` into an
  existing `as_rioja()` matrix at its correct depth, returning `preview_row`
  so callers can locate it. New taxa in the preview sample are added as columns
  with zeros for all site rows; `min_present` applies to site rows only.

### Accumulation rates

- `accum_rate()`: compute pollen accumulation rates (PAR / pollen influx) for
  all depth-bearing samples in a site. Returns a summary data frame (depth,
  age, deposition time, concentration, influx) plus per-taxon concentration and
  influx matrices. Validates all required inputs (depth interval, age interval,
  sample quantity, spike parameters) before computing; lists every deficiency in
  a single error so all problems can be fixed at once.

### Data model

- `pollen_count()` gains a `sample_number` field (written to and read from
  YAML).
- Ages are documented as years BP (before present; present = 1950 CE).
- `yaml` package moved from `Suggests:` to `Imports:` (always required).
- `%||%` scalar-guard bug fixed (was using `is.na()` on vectors).

### Parser fixes

- Traverse labels now accept any free text between slashes (`/label/`), not
  just numeric + N/S. The corresponding test was renamed accord