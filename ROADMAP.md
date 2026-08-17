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
- **Depth sheet** for the local validation site (unpublished; not distributed)
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

## Done — v0.6.1

- **Bug fix: `pct_smax` contradicted the tier columns.** It was defined as
  observed richness over the modelled asymptote (`n_taxa / s_max`) while
  `n70`/`n80`/`n90` came from the fitted model, so a sample could report reaching
  90% of `Smax` on 347 grains while its own `n90` asked for 531. The
  least-squares fit sits slightly below observed richness at `n = N`, making the
  observed ratio systematically optimistic. `pct_smax` is now the fitted curve's
  share at the count made, `100 * N / (K + N)`, which is algebraically equivalent
  to the tiers. `s_max`, `k`, and all targets are unaffected. See DESIGN.md §12.

## Done — v0.6.0

- **`rarefaction()` rewritten — pollen count targets** (breaking). The previous
  "optimal pollen sum" was defined as a fraction of each sample's *own* observed
  richness, which a rarefaction curve reaches by construction. `meets_optimal`
  had no code path to `FALSE`, `pct_asymptote` was pinned at 100%, and the
  recommended count scaled with effort. The asymptote is now extrapolated with a
  Michaelis–Menten model after Lesven et al. (2026), so a count can genuinely
  fall short; targets for 70/80/90% of `Smax` follow in closed form from
  `n_p = K·p/(1−p)`, the relationship underlying their Table 3. No adequacy
  verdict is returned — the analytical objective is the analyst's to set. See
  DESIGN.md §12.
- **Deterministic targets** — the mean curve is computed analytically (Hurlbert,
  1971) rather than by simulation, so `Smax`, `K`, and all targets are
  reproducible without `set.seed()`. Permutations now serve only the confidence
  band on plotted curves.
- **Half-grains count as whole detections**; unusable fits return `NA` rather
  than a fabricated number; `stats` added to `Imports`.

## Done — v0.5.8

- **`extract_remarks()`** — remark lookup across a site. Returns
  `sample_name`, `slide`, `traverse`, `id`, `remark`, where `id` is the taxon
  code + preservation of the adjacent grain (`id = "before"` default, or
  `"after"`). Lets an analyst find their way back to a flagged spot on a slide.
- **Bug fix: preservation code `9` rejected on entry** — the entry regex
  required a base digit `1`–`8`, so a modifier-only token (`ts9`) could never
  match. Base digit is now optional in both the grain parser and the Grain
  History preservation editor.
- **Bug fix: multi-slide `.CNT` files lost slide boundaries** — mid-stream
  `{...}` tokens had no tokeniser branch and were discarded as anomalies. They
  now produce `slide_desc` events, and the leading descriptor is emitted as the
  opening event so CNT and app event streams match.
- **Bug fix: vignette documented a nonexistent `rioja::strat.plot()` argument**
  — `y2var` / `y2label` were never `strat.plot()` parameters, so the documented
  secondary age axis was silently never drawn (and emitted 128 warnings per
  diagram). Vignette now uses the single `yvar` axis; the test that asserted the
  opposite was corrected, and both `strat.plot()` smoke tests now use
  `expect_no_warning()`.
- **`pres` standardised to a concatenated digit string** (`"19"`, not `"1;9"`).
  Fixed `preservation_table(collapse_multistate = TRUE)`, which had silently
  stopped collapsing multi-state grains, and the app's Grain History
  preservation column. `read_pollen_count()` strips semicolons for backward
  compatibility.

## Done — v0.5.7

- **Bug fix: CNT → YAML round-trip for modifier grains** — `.tokenise_stream()`
  now builds grain events with `base`, `pres`, `hidden`, and `anomaly` fields
  (matching the app's event format) instead of the `pres_set` vector that
  `write_pollen_count()` did not read. Grains with modifier `9` (hidden) or `0`
  (half-grain) now survive the CNT → YAML → `read_pollen_count()` round-trip
  with all flags intact. New test file `test-modifier-roundtrip.R` (7 assertions)
  guards against regression.

## Done — v0.5.6

- **`pollen_dictionary` `value` column** — optional grain weight column in CSV
  dictionaries (default `1`). Allows analysts counting without preservation codes
  to define half-grain codes (e.g. `HI` for "half *Picea*" with `value = 0.5`)
  directly in the dictionary rather than using the `0` modifier. `.DIC` files
  always produce `value = 1`. `write_dic_csv()` and `dictionary_template.csv`
  updated. Counting app `use_pres = FALSE` path now looks up grain weight from
  `dic$value` instead of hardcoding `1.0`.

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

1. **More site validation data** — load the remaining `.CNT` files from the local
   validation corpus; harden `read_cnt()` against any format variants they reveal.

2. ~~**Shiny app — keyboard shortcut for spike**~~ — **Done (v0.5.3).** Pressing `.` on an
   empty input field submits a spike immediately without Enter.

3. ~~**`site_matrix()` + `rioja::strat.plot()` integration**~~ — **Done (v0.5.3).**
   `tests/testthat/test-site-matrix-rioja.R` covers the full pipeline using
   Fake Lake; rioja tests are guarded with `skip_if_not_installed("rioja")`.

4. ~~**Accumulation-rate end-to-end validation**~~ — **Resolved (v0.5.8).**
   `accum_rate()` verified against real sites with analyst-supplied ages.

5. ~~**Rarefaction analysis**~~ — **Done (v0.5.1); rewritten (v0.6.0).** The
   original 90%-of-observed-richness method was circular and always reported
   sufficiency; `rarefaction()` now extrapolates the asymptote with a
   Michaelis–Menten model and reports objective-specific count targets
   (DESIGN.md §12).

6. ~~**`write_tlx()` validation**~~ — **Resolved (v0.5.8).** Verified in use on
   real sites.

## Optional future features

- **Volumetric concentration — extended form** — the current volumetric mode
  divides ΣP by sample quantity directly. A more precise version would use an
  aliquot volume drawn from a known total suspension volume:
  `concentration = (grains_counted / aliquot_volume) × total_volume / sample_quantity`.
  Would require new metadata fields (`aliquot_volume`, `total_volume`) for
  analysts who use this approach.

## Validation debts to clear when data allows

- More sites (different dictionaries, ml vs g units) to harden assumptions.

### Closed as not-a-debt (v0.5.8)

The preservation scheme is **analyst-defined** — both the code→label mapping and
the multi-state precedence order are `pollen_site()` arguments (DESIGN.md §6).
Two long-standing entries were therefore retired rather than resolved:

- ~~Documentation for preservation codes 3, 4, 5, 7~~ — these carry no canonical
  meaning in `pcountr`; labels come from the analyst's `preservation` vector.
- ~~A `.CNT`/`.RPT` pair with combination codes to verify multi-state
  attribution~~ — attribution is governed by the analyst's `precedence` order, a
  configurable presentation choice, not a fact about PCount to be reproduced.
