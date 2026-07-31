# pcountr — Roadmap

## Done — v0.1.0 (the verified spine)

- `read_dic()` — fixed-column dictionary parser (232 taxa, groups A/B/F/Q/X + specials)
- `read_cnt()` — legacy count parser: per-grain, ordered, traverses + spike + remarks,
  permissive anomaly reporting
- `pollen_site` / `pollen_count` S3 objects + print/summary methods
- `count_metrics()` — reproduces PCount report numbers to the digit
- `preservation_table()` — taxon × class tabulation with configurable precedence
- `write_pollen_count()` / `read_pollen_count()` — native YAML format
- Golden + site testthat suites (87 assertions passing)

## Done — v0.2.0

- **Traverse parsing** loosened to accept any free-text label (DESIGN.md §5)
- **`yaml` in `Imports:`** — real package always required; YAML round-trip golden test added
- **`testthat` via `devtools::test()`** — replaces the shim used in v0.1.0
- **`read_site()`** — site-folder loader: `.CNT` and/or `.yaml` files, optional depth/age
  metadata sheet (CSV/TSV, user-mappable column names), YAML/sheet conflict detection,
  depth-ordered sample list, NA-depth samples load fine
- **`set_metadata()`** — update depth, age, sample identity, quantity, and spike on a sample; re-sorts site automatically (`set_depth_age()` / `set_depth()` are deprecated wrappers)
- **`as_rioja()`** — wide species × depth percentage matrix; configurable denominator,
  taxon label, and min-presence filter; depth-less samples excluded with a message
  *(renamed to `site_matrix()` in v0.5.0; deprecated wrapper retained)*
- **`accum_rate()`** — total + per-taxon PAR; full input validation with a combined error
- **CSV dictionary** — `read_dic_csv()`, `write_dic_csv()`, auto-detect in `read_dic()`;
  one-line DIC migration; `dictionary_template.csv` + README for GitHub
- **`count_app()`** — Shiny counting app (see NEWS.md for full feature list)
- **`sample_number`** field on `pollen_count` and in YAML
- **`LM_depths.txt`** — real depth sheet for the Little Mosquito Lake extdata site
- 279 test assertions passing

## Done — v0.3.0

- **Setup flow**: "Open Existing Count" moved to top of setup page; loading a YAML
  pre-fills the metadata form so the analyst can review/edit before clicking "Resume Count".
- **Dictionary auto-load on resume**: `dic_path` added to `pollen_count()` and the YAML
  format; the app auto-loads the dictionary when a past count is opened. Falls back to
  manual browse if the file has moved or the count is from a different machine.
- **Sample Info tab**: all count metadata (title, depth, age, quantity, spike parameters,
  ΣP groups) editable mid-count with immediate autosave. Save path is intentionally locked.
- **Dictionary tab**: full inline editing of the loaded dictionary, add-row dialog, Save
  Dictionary button, and automatic `.DIC` → CSV conversion on first save.
- **Entry alerts overhauled**: unknown codes and malformed input (e.g. `I8A1`) now trigger
  a large prominent modal with an audio beep. Options are Re-enter (dismiss and retype) or
  Edit Dictionary (jump to Dictionary tab). Old three-way correct/add/delete dialog removed.
- **Live concentration and PAR** in the stats panel, below the ΣP sum. Update on every
  entry; show `NA` when required inputs (spike, sample quantity, depth, age) are absent.
- **`dic_path` data model field** — stored in `pollen_count$meta` and YAML; transparent to
  all analytical functions.

## Done — v0.4.0

- **Shiny app — lossless resume**: full event list (grains, spikes, traverses, remarks)
  serialised to YAML (`format_version: 2`). Spike positions are now preserved exactly
  on resume. Older YAMLs (`format_version: 1`) fall back automatically to the previous
  reconstruction path — backward compatible.
- **`as_rioja()` data model overhaul**: renamed fields (`TaxaPerc`, `DepTop/DepBot/
  AgeTop/AgeBot`) and new fields for every input and output of the Stockmarr equation:
  `SampleSize`, `SpikeCount`, `SpikeAdded`, `SpikeConc`, `TaxaCount`, `TaxaConc`,
  `TaxaAccRate`.
- **Taxa names as default column labels** in `as_rioja()` (`taxon_label = "name"`).
- **Attribution**: Eric Grimm (1951–2020) credited throughout `DESCRIPTION`, `README.md`,
  `DESIGN.md`, and roxygen `@references` for `read_cnt()` and `read_dic()`.
- 287 test assertions passing.

## Done — v0.5.0

- **`site_matrix()`** replaces `as_rioja()`. Identical behaviour; name change reflects
  that the output is general-purpose, not rioja-specific. `as_rioja()` is retained as a
  deprecated wrapper with a one-time warning.
- **`write_tlx()`** — exports a `pollen_site` to Tilia XML (`.tlx`) with four sheets:
  Data, Percents, Concentrations, Influx. CONC metadata block includes age, depth, spike,
  sample quantity (unit-aware), tablets, tablet concentration, and deposition time. Samples
  ordered by `depth_top` → `sample_number` → `age_top`; negative sample numbers supported.
  Site/CollectionUnit stubs left empty for completion in Tilia.
- 313 test assertions passing.

## Done — v0.5.2

- **Concentration method selector** — `count_app()` setup screen asks "Calculate
  concentration?" with three choices: spike (Stockmarr equation, default),
  volumetric (ΣP / sample_quantity), or none. Spike fields hidden when not needed.
  `conc_method` field added to `pollen_count()`, YAML format, `count_metrics()`,
  and `site_matrix()` (per-sample concentration factor). Carried forward on New
  Sample; restored on Resume.
- **Preservation codes optional** — setup screen asks "Use preservation codes?"
  (Yes/No). When No, grains are entered as code only; stream display uses `_`
  separator. `use_pres` field added to `pollen_count()` and YAML.
- **`extract_metadata()`** — new function that creates a metadata data frame from
  a `pollen_site` or folder path, suitable for editing and passing back to
  `read_site(metadata = ...)`. The reverse of `set_metadata()`. Optional
  `file =` argument writes CSV.
- **Fake Lake units corrected** — `metadata_FL.csv` changed from `g` to `ml`;
  concentration now reports as grains/cm³.

## Done — v0.5.3

- **Counting app input reliability fix** — removed R-side `updateTextInput`
  that was racing against the analyst's next keystrokes during autosave lag,
  causing rapid entries to be silently discarded.
- **Undo refocuses grain input** — pressing Undo no longer leaves focus on the
  button; the grain input box reactivates automatically, consistent with all
  other counting actions.
- **Grain autosave debounced** — grain entries write to disk within 300 ms of
  the last keystroke rather than after every individual grain. All other actions
  (traverses, remarks, undo, metadata changes, Done / Save) still save
  immediately.
- **Grain History table renders on demand** — table is built only when the
  Grain History tab is open, eliminating redundant rebuilds during counting.

## Done — v0.5.5

- **`write_site()`** — batch YAML export; converts every sample in a loaded
  `pollen_site` to a YAML file. Primary use: migrating a legacy `.CNT` folder
  to the modern YAML format so `apply_metadata()` can write metadata back to
  disk. Returns the updated site with `source_file` stamped to the new YAML
  paths, enabling immediate `extract_metadata()` / `apply_metadata()` calls
  without reloading. `overwrite = FALSE` by default.

## Done — v0.5.4

- **`apply_metadata()`** — new function completing the round-trip edit workflow:
  `extract_metadata()` → edit CSV → `apply_metadata()` applies all non-NA
  columns via `set_metadata()` and writes updated YAMLs back to disk. Rows are
  matched by `source_file` (preferred) or `sample_name` (fallback). Pass
  `write = FALSE` to apply edits in memory only.
- **`set_metadata()` gains `title` and `conc_method`** — both fields were already
  handled by `extract_metadata()` and the YAML format but were not settable via
  `set_metadata()`.
- **`spike_units` fix in counting app autosave** — `do_autosave()` now passes
  `spike_units` to `pollen_count()`. Previously the field was silently omitted, so
  all YAMLs saved before this fix have `spike_units: NA`. Use `apply_metadata()`
  to backfill existing files.
- **`read_site()` stamps full `source_file` path** — after loading each sample,
  `read_site()` overwrites `meta$source_file` with the full normalized path,
  making `apply_metadata()` reliable regardless of what was stored in the YAML.

## Planned (in priority order)

1. **More site validation data** — load the remaining LM `.CNT` files (LMSH159–LMSH302)
   once added to `inst/extdata/`; harden `read_cnt()` against any format variants they
   reveal.

2. ~~**Shiny app — keyboard shortcut for spike**~~ — **Done (v0.5.3).** Pressing `.` on an
   empty input field submits a spike immediately without Enter.

3. ~~**`site_matrix()` + `rioja::strat.plot()` integration**~~ — **Done (v0.5.3).**
   `tests/testthat/test-site-matrix-rioja.R` covers the full pipeline using
   Fake Lake; rioja tests are guarded with `skip_if_not_installed("rioja")`.

4. **Accumulation-rate end-to-end validation** — once a full site with analyst-supplied
   ages is available, run `accum_rate()` and compare with independently computed values.

5. ~~**Rarefaction analysis**~~ — **Done (v0.5.1).** `rarefaction()` implements
   the 100-permutation / 90%-asymptote method per sample, with optional depth
   and age range filters and a `pollen_rarefaction` S3 print method.

6. **`write_tlx()` validation** — round-trip test against a known-good TLX file once a
   complete site with ages is available; harden unit handling for g-unit sites.

## Optional future features

- **Volumetric concentration — extended form** — the current volumetric mode
  divides ΣP by sample quantity directly. A more precise version would use an
  aliquot volume drawn from a known total suspension volume:
  `concentration = (grains_counted / aliquot_volume) × total_volume / sample_quantity`.
  Would require new metadata fields (`aliquot_volume`, `total_volume`) for
  analysts who use this approach.

## Validation debts to clear when data allows

- A `.CNT`/`.RPT` pair with **combination preservation codes** (e.g. `680`) to verify
  multi-state attribution against the original PCount output.
- Documentation for preservation codes **3, 4, 5, 7**.
- More sites (different dictionaries, ml vs g units) to harden assumptions.
