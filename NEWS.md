# pcountr NEWS / changelog

## pcountr 0.5.6

### Counting app — spacebar submits grain entries

Pressing **Space** in the grain input field now submits the entry, identical to
pressing Enter. Space is ignored when the field is empty, and passes through
normally when typing a remark (`[text]`) or traverse label (`/label/`) so that
multi-word entries are unaffected.

### Dictionary — optional `value` column for half-grain codes

`pollen_dictionary` now supports an optional `value` column (grain weight;
default `1`). This is intended for analysts who count **without preservation
codes** (`use_pres = FALSE`) but still need to record half-grains. Instead of
the standard `0` preservation modifier, they can define a dedicated code in the
CSV dictionary — for example `HI` ("half *Picea*") with `value = 0.5`.

Behaviour:

- `.DIC` files: `value` is set to `1` for every row (the fixed-column format
  has no weight column).
- CSV files: column is optional and matched case-insensitively. Missing or
  blank values default to `1`; `NA` values default to `1`.
- `write_dic_csv()` always writes the `value` column so round-tripped files
  are self-documenting.
- `dictionary_template.csv` updated with `value` column (all `1`).
- **Counting app** (`use_pres = FALSE` path): grain weight is now looked up
  from `dic$value[idx]` instead of the previous hardcoded `1.0`. Falls back
  to `1.0` if the column is absent or the value is `NA`/non-finite.
- **`use_pres = TRUE` path**: `value` is ignored — weight is always determined
  by the `0` preservation modifier in the grain token, as before.

---

## pcountr 0.5.5

### `write_site()` — batch YAML export and CNT migration

New function `write_site()` converts every sample in a loaded `pollen_site` to
a native YAML file, completing the CNT → YAML migration path and enabling the
full round-trip metadata edit workflow for legacy data:

```r
# Load legacy CNT files (depths/ages from sheet if available)
site <- read_site(cnt_dir, dic = "ECG.csv", metadata = "depths.csv")

# Convert to YAML
site <- write_site(site, "yaml_output/")

# Edit metadata and write back
extract_metadata(site, file = "metadata.csv")
# … edit …
site <- apply_metadata(site, "metadata.csv")
```

After writing, each sample's `meta$source_file` is updated to the new YAML
path in the returned site, so `extract_metadata()` and `apply_metadata()` work
immediately without reloading from disk. Existing files are skipped with a
message by default; pass `overwrite = TRUE` to replace them.

---

## pcountr 0.5.4

### Metadata round-trip workflow — `apply_metadata()`

New function `apply_metadata()` completes the round-trip edit cycle for all
sample metadata fields:

```r
site <- read_site("path/to/yamls")
extract_metadata(site, file = "metadata.csv")  # export CSV
# … edit the CSV in any spreadsheet editor …
site <- apply_metadata(site, "metadata.csv")   # apply edits; writes YAMLs
```

`apply_metadata()` reads the CSV, matches each row to a sample by `source_file`
(exact path, preferred) or by `sample_name` (fallback), applies every non-NA
column via `set_metadata()`, and by default writes each modified sample back to
its source YAML file. All fields that `set_metadata()` accepts are editable this
way: `depth_top`, `depth_bottom`, `age_top`, `age_bottom`, `sample_name`,
`sample_quantity`, `units`, `spike_tablets`, `spike_density`, `spike_units`,
`conc_method`, and `title`. The `source_file` column is used for matching only
and is never overwritten. Pass `write = FALSE` to apply edits in memory only.

### `set_metadata()` — new `title` and `conc_method` parameters

Both fields were present in `extract_metadata()` output and the YAML format but
were not settable via `set_metadata()`. They are now full `NULL`-default
parameters.

### Bug fix — `spike_units` always NA in exported metadata

The counting app's autosave (`do_autosave()`) called `pollen_count()` with
`spike_tablets` and `spike_density` but omitted `spike_units`. All YAML files
saved by `count_app()` before this fix therefore lack the `spike_units` field.
The omission is now corrected. To backfill existing files, export metadata with
`extract_metadata()`, fill in the `spike_units` column, and run `apply_metadata()`
to write the updated YAMLs.

### Bug fix — `apply_metadata()` writes to the correct YAML directory

`read_site()` now stamps the full normalized path to `meta$source_file` for
every sample after loading, overwriting whatever bare filename may have been
stored in the YAML by the counting app. This ensures `apply_metadata()` always
resolves the write target to the correct folder rather than R's working directory.

---

## pcountr 0.5.3

### Counting app — performance and input reliability

- **Race condition fixed.** Rapidly typing the next grain token during the
  brief autosave lag could cause the entry to be silently discarded. Root
  cause: an R-side `updateTextInput` was clearing the grain input box after
  each entry, arriving back in the browser after the analyst had already
  started typing. The redundant clear has been removed; the JavaScript-side
  clear (synchronous, immediate) is sufficient.

- **Undo refocuses the grain input.** After clicking Undo the grain input box
  is now reactivated automatically, consistent with the behaviour after every
  other counting action. Previously the Undo button retained focus, so pressing
  Enter immediately after an undo would trigger another undo.

- **Grain autosave debounced (300 ms).** Grain entries now write to disk within
  300 ms of the last rapid keystroke rather than after each individual entry.
  All other actions — traverses, remarks, undo, new slide, Done / Save, New
  Sample, and all Sample Info tab changes — still save immediately. In practice
  this reduces file-write frequency during rapid counting without meaningfully
  affecting crash safety.

- **Grain History table renders on demand.** The grain table is now built only
  when the Grain History tab is open. Previously it was rebuilt on every grain
  entry even when invisible, adding unnecessary overhead especially late in
  large counts.

### Tests — `site_matrix()` + rioja integration smoke test

New test file `tests/testthat/test-site-matrix-rioja.R` exercises the full
`read_site() → site_matrix() → rioja::strat.plot()` pipeline using the
bundled Fake Lake data. Tests cover matrix shape, `DepTop` / `AgeTop`
parallelism, depth ordering, and full `TaxaConc` population (Fake Lake has
complete spike metadata for every sample). The `strat.plot()` calls are
guarded with `skip_if_not_installed("rioja")`.

### Counting app — spike single-key shortcut

Pressing `.` on an **empty** input field now submits a spike immediately —
no Enter required. Pressing `.` mid-token (field not empty) appends the
character as before. The `.` + Enter path continues to work unchanged.

---

## pcountr 0.5.2

### Counting app — concentration method selector

The setup screen now asks **"Calculate concentration?"** with three choices,
stored in the new `conc_method` field on `pollen_count` and YAML:

- **Yes, using spikes.** (default) — tracer-spike (Stockmarr) equation,
  unchanged from previous versions. Spike fields appear on setup and Sample
  Info tab.
- **Yes, volumetrically.** — concentration = ΣP / sample quantity. No spike
  required. Spike fields are hidden. Units follow the existing ml/g selector
  (grains/cm³ or grains/g).
- **No.** — no concentration computed; Conc and PAR display `NA`.

`count_metrics()` branches on `conc_method` per sample. `site_matrix()` computes
a per-sample concentration factor that respects each sample's method, so mixed
sites (some spike, some volumetric) produce correct results.

### Counting app — preservation codes optional

The setup screen now asks **"Use preservation codes?"** (Yes / No), stored in
the new `use_pres` field on `pollen_count` and YAML:

- **Yes** (default) — existing behaviour: each grain token requires a base
  preservation digit (e.g. `B1`, `I80`).
- **No** — grains are entered as code only (e.g. `B`, `I`). No digit expected
  or accepted. In the count stream display, grains are separated by `_`
  (e.g. `Betula_Picea_Alnus_`) rather than concatenated with preservation
  digits. The Grain History table shows `—` in the Preservation column.

Both settings are carried forward automatically when **New Sample** is used,
and are fully restored on **Resume Count** from a saved YAML.

### `extract_metadata()` — reverse of `set_metadata()`

New function that creates a metadata data frame from a loaded site, suitable
for editing and re-passing to `read_site(metadata = ...)`:

```r
site <- read_site("path/to/yamls")
df   <- extract_metadata(site)           # returns data frame
extract_metadata(site, file = "meta.csv")  # also writes CSV
```

Accepts either a `pollen_site` object or a folder path (calls `read_site()`
internally). Fields absent from a sample are `NA`. Columns: `sample_name`,
`depth_top`, `depth_bottom`, `age_top`, `age_bottom`, `sample_quantity`,
`units`, `spike_tablets`, `spike_density`, `spike_units`, `conc_method`,
`title`, `source_file`.

### Fake Lake example data — units corrected

`inst/extdata/fake_lake/metadata_FL.csv` now records `sample_units = ml`
(was `g`). Sediment processed by volume is more realistic for palynological
subsamples; concentration now reports as grains/cm³.

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
  just numeric + N/S. The corresponding test was renamed accordingly.

### Testing

- 279 test assertions passing (was 87 at v0.1.0).
- New test files: `test-dictionary-csv.R`, `test-site-loader.R`,
  `test-rioja.R`, `test-accum-rate.R`.
- YAML round-trip golden test verifies concentration reproduces to the digit
  through write → read.

---

## pcountr 0.1.0 (the verified spine)

First working version. Reads legacy PCount files, reproduces PCount report
calculations to the digit, and writes a modern native format.

### Features

- `read_dic()`: parse PCount `.DIC` dictionaries (fixed-column format).
- `read_cnt()`: parse legacy `.CNT` count files into per-grain `pollen_count`
  objects, preserving counting order, traverse labels, tracer-spike marks, and
  inline remarks. Anomalies (e.g. data-entry typos, unresolved codes) are
  imported permissively and reported via the `anomalies` attribute and a warning.
- `pollen_site()` / `pollen_count()`: the two core S3 objects, with configurable
  preservation scheme and multi-state precedence, and sample-level depth/age slots.
- `count_metrics()`: per-group pollen sums, basic/total sums, spike count,
  sum/spike ratio, grain concentration (per-sample ml→grains/cm³ or g→grains/g),
  traverse statistics.
- `preservation_table()`: taxon × preservation-class tabulation, with optional
  multi-state collapsing by precedence.
- `write_pollen_count()` / `read_pollen_count()`: native YAML format (with a
  built-in emitter fallback when the `yaml` package is absent).

### Verified

- Reproduces `LM23SH00.RPT` exactly (all sums, spike, ratio, concentration,
  traverse stats).
- Parses all 20 Little Mosquito Lake samples; surfaces exactly 7 known
  data-entry anomalies.
- 87 test assertions passing.
