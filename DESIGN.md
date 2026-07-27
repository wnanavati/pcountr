# pcountr — Design & Decisions Log

This document is the single source of truth for *why* `pcountr` is built the way
it is. It exists so that any new working session (in Claude Cowork, Claude Code,
or with a human collaborator) can continue the project without re-deriving the
reasoning. **Read this first.**

Status as of this writing: **v0.5.3.** The verified spine (v0.1.0) is complete
and all planned analytical layers have been built on top of it. 446 test
assertions pass, including reproduction of a real PCount report to the digit.
The Shiny counting app (`count_app()`) is functional and has been used in the
field. Two vignettes ship with the package: *Counting at the Microscope*
(`counting.Rmd`, primary) and *Legacy Workflow: CNT Files to Tilia XML*
(`legacy.Rmd`). Deprecated wrappers `as_rioja()`, `set_depth_age()`, and
`set_depth()` have been removed. New in v0.5.2: concentration method selector
(spike / volumetric / none), optional preservation codes, and
`extract_metadata()`. New in v0.5.3: counting app performance and input
reliability fixes (see NEWS.md).

---

## 1. What this package is

`pcountr` is a keystroke-driven counting application and analysis toolkit for
stratigraphic microscopy. Although built around the MS-DOS program **PCount**
and its pollen-counting workflow, the package is proxy-agnostic: diatoms,
charcoal morphotypes, phytoliths, or any assemblage counted by traversing a
slide follow the same workflow unchanged. The package:

1. provides a **Shiny counting app** (`count_app()`) to replace the DOS
   counting loop — keystroke-driven grain entry, live running totals,
   concentration and PAR, YAML autosave, resume from any saved count;
2. **reads** legacy PCount files (`.DIC` dictionaries, `.CNT` counts, `.RPT`
   reports);
3. **converts** them into a modern, self-contained native format (YAML), adding
   sample depth and optional age;
4. **reproduces** PCount's report calculations (assemblage sums, tracer-spike
   ratio, grain concentration, traverse statistics, preservation tabulations);
5. **exports** to downstream tools (`rioja` stratigraphic plots, tidy community
   matrices for statistics, Tilia XML `.tlx` for Neotoma upload).

### Origins and acknowledgements

`pcountr` is dedicated to the memory of **Dr. Eric C. Grimm (1951–2020)**, who
developed PCount at the Illinois State Museum and Research and Collections Center
in Springfield, Illinois, and distributed it freely to the palynological community
beginning in 1994. The `.CNT` grammar documented in §3, the concentration equation
in §10, and the preservation scheme in §6 are all derived directly from PCount 2.0.
All credit for the original design belongs to Grimm.

### Scope boundary — chronology is delegated

`pcountr` does **not** build age–depth models. It stores analyst-supplied ages
and will compute accumulation rates *arithmetically* from them
(`rate = concentration × deposition rate`), but the age model itself comes from
dedicated tools: **`rbacon`, `clam`, `neotoma2`**. This boundary is deliberate —
the package must not quietly reimplement Bacon. The age fields on a sample are
the seam between the two worlds.

---

## 2. The domain, briefly

A palynologist looks down a microscope and, for each grain, types a 1–2 letter
**taxon code** (defined in a dictionary) plus a **preservation digit**. A known
quantity of **tracer spike** (exotic marker grains — here *Microspheres*, code
`.`) is added to the sample so that pollen **concentration** can be computed from
the ratio of pollen counted to spike counted. The counter watches two running
totals: the **terrestrial pollen sum** and the **spike count**. Counting
proceeds along **traverses** (passes across the slide), with the analyst noting
the microscope stage position so they can find their place again.

---

## 3. The legacy `.CNT` grammar (reverse-engineered and verified)

A `.CNT` file is:

```
Line 1:  program tag           e.g. "pcount 2.0" / "File created ..."
Line 2:  timestamp
Line 3:  config line            "ECG.DIC, 1, 2, 9666, 0, 2;"
Line 4:  pollen-sum definition  "POLLEN SUM = ABF"
Line 5:  title line             "Little Mosquito Lake   LM23sh#001   13MAY24"
Line 6+: the count stream, wrapped at ~68 columns (must be de-wrapped/rejoined)
```

The config line fields are:
`dictionary, sample_quantity, spike_tablets, spike_density, <zero>, units_code;`
where `units_code` 1 = ml (→ grains/cm³), 2 = g (→ grains/g).

The count stream, after de-wrapping, is a sequence of these token types:

| Token | Meaning |
|-------|---------|
| `{ ... }` | slide description (appears once, at the start) |
| `CODE` + base digit `1`–`8` + optional modifiers `{0,9}` | one pollen grain |
| `.` | one tracer-spike microsphere (no digit) |
| `/<label>/` | traverse marker (see §5 — label is free text) |
| `[ ... ]` | inline remark, kept verbatim at its position |

### Preservation digits

- A grain has one **base** preservation digit `1`–`8`.
- `0` is **not a state** — it is a *weight modifier* meaning the grain is a
  **half-grain fragment**, counting as **0.5** instead of 1.0. It can ride on top
  of any base digit (e.g. `I80` = Picea, broken, half-weight = 0.5 under class 8).
- `9` (hidden) is also a modifier that can follow another digit.
- **Known code meanings:** 1 = perfect, 2 = corroded, 6 = crumpled, 8 = broken,
  9 = hidden, 0 = half-grain.
- **Undocumented:** 3, 4, 5, 7 — analyst is sourcing documentation. They are
  placeholders in the scheme and may be relabelled per project.
- Combination codes like `680` (crumpled + broken + half) are *possible* but
  **rare and absent from the verified data**, so the multi-state summary rule is
  provisional (see §6).

---

## 4. Validation philosophy (analyst's explicit instruction)

There are two classes of "wrong" tokens, treated very differently:

1. **Dictionary-resolvable things — validate and call out.** A taxon code that
   isn't in the dictionary, or a preservation digit outside the defined set, is a
   meaningful anomaly. `read_cnt()` imports the valid grains, records the anomaly
   in the `anomalies` attribute, and warns. The same call-out must happen during
   live counting (future Shiny app). The point is to let the analyst decide:
   fix a typo, or add/update a dictionary entry.

2. **Traverse labels — never validate.** The text between the slashes is an aid
   for the analyst to find their place on the slide; it is *not* structured data.
   Store it **verbatim**, whatever it is.

### Known anomalies in the example data
The 20-file Little Mosquito Lake site contains exactly **7 genuine data-entry
typos** (e.g. `A11`, `I88`, `ER21` — a doubled or stray digit). These are real
mistakes in the original counts. The parser flags them rather than guessing, and
a regression test pins the count at 7 so the behaviour can't silently change.

---

## 5. Traverse labels — RESOLVED in v0.2.0

`read_cnt()` now matches traverse markers with `^/([^/]+)/`, accepting any
free-text label verbatim. The test was renamed to "any traverse label parses
verbatim and produces no anomalies". This does not affect any metric, since
traverse labels are only counted, never validated.

The Shiny counting app (`count_app()`) also accepts any free-text traverse
label typed inline as `/label/`, and provides a Traverse button for
mouse-driven entry.

---

## 6. Provisional / unverified decisions

- **Multi-state preservation precedence.** When a single grain has more than one
  state (e.g. crumpled + broken) and a summary table allows one class per grain,
  `preservation_table(collapse_multistate = TRUE)` picks one via
  `default_precedence` (currently `8 > 6 > 2 > 9 > 1`). The raw per-grain set is
  always retained, so nothing is lost. **This precedence is a documented guess.**
  The verified data has no genuine multi-state grains, so we cannot yet confirm
  how PCount itself attributes them. *To verify:* obtain a `.CNT`/`.RPT` pair
  containing combination codes and check PCount's preservation table against ours.

- **Preservation codes 3/4/5/7.** Labelled `undocumented-N` until the analyst
  finds the original PCount documentation.

---

## 7. Data model (the objects)

Two-tier, reflecting that some config is shared across a site and some is
per-sample.

### `pollen_site` (site-level config)
- `name`
- `dictionary` (a `pollen_dictionary` data frame: code, alias, group, name, is_special)
- `pollen_sum` — group codes forming the *basic* sum (default `A,B,F`)
- `preservation` — named code→label vector (configurable)
- `precedence` — multi-state attribution order (configurable)

The dictionary **can differ from site to site**. Within one site it is assumed
consistent; `read_cnt(site=)` warns if a code doesn't resolve.

### `pollen_count` (per-sample)
- `grains` — a data frame, **one row per grain, in counting order**:
  `code, base, pres (";"-joined state set), weight, hidden, traverse, position`
- `spike_n` — tracer count
- `traverses` — ordered vector of labels
- `remarks` — list of `{text, position, traverse}`, verbatim, in sequence
- `events` — the full ordered event list (grains, spikes, traverses, remarks)
  interleaved by position — this is what preserves exact counting order
- `meta` — `sample_quantity, units, spike_tablets, spike_density, spike_units,
  pollen_sum_groups, depth_top, depth_bottom, age_top, age_bottom,
  sample_name, dic_path, slide, title, source_file`
- `site` — optional attached `pollen_site`
- `attr(x, "anomalies")` — data frame of `position, text, reason`

**`dic_path`** stores the full filesystem path to the dictionary file used
when counting. It is written to YAML by the Shiny app's autosave and read back
by `read_pollen_count()`. Its only consumer is `count_app()`, which uses it to
auto-reload the correct dictionary when resuming a past count on the same
machine. It has no effect on any analytical function.

**Granularity decision:** per-grain in sequence, because counting *order matters*
to analysts (re-count audits, "find where I was"). Aggregation is a derived view.

---

## 8. Native format (YAML)

One self-contained file per sample. Scalar metadata at the top (including
depth/age slots, which legacy `.CNT` lacks), then the full ordered grain list and
remarks. `.CNT` is read once and converted into this. CSV export (per sample) is
planned as an *additional* output, not the primary store, because CSV has no
clean home for the scalar metadata header.

The package prefers the real `yaml` package and falls back to a minimal built-in
emitter when `yaml` is unavailable (it was unavailable in the original sandbox;
it will be available via CRAN in Cowork — install it).

---

## 9. Verification status

Reproduced **to the digit** against `LM23SH00.RPT` (the PCount report for
`LMSH001.CNT` from the Little Mosquito Lake site). These files are local only
and gitignored (unpublished data); they remain in the analyst's working
directory for local test runs.

| Quantity | Value |
|----------|-------|
| Sum A / B / F / Q | 292.5 / 32.0 / 7.0 / 7.0 |
| Basic / Total pollen sum | 331.5 / 338.5 |
| Spike counted | 72 |
| Sum/spike ratio | 4.7014 |
| Concentration | 90887 (exact 90887.25) |
| Traverses / mean per traverse | 6 / 56.42 |

All 20 site files parse; exactly 7 anomalies surface; Picea (`I`) = 42.5
including 5 half-grains. See `tests/testthat/`.

---

## 10. The Stockmarr concentration equation

```
concentration = (total_pollen_sum / spike_counted) × (spike_tablets × spike_density) / sample_quantity
```

Unit follows the sample's units flag: grains/cm³ (ml) or grains/g (g). Units can
vary per sample, so the label is computed per sample, not per site.

---

## 11. Counting app design decisions (`count_app()`)

The Shiny app replicates the DOS PCount counting loop in a modern browser
window. Key decisions:

### Entry model
Grains are entered as a single text token (`I8`, `B1`, `A80`) and submitted
with Enter. The app parses the token synchronously in JavaScript at keypress
time, bypassing Shiny's 250 ms textInput debounce, so rapid entries are never
dropped. Traverses (`/label/`), remarks (`[text]`), and spike (`.`) are entered
in the same field. The spike token (`.`) has a single-key shortcut: pressing `.`
on an empty input field submits it immediately without Enter, since `.` is never
a valid prefix for any other token.

### Unknown-code and malformed-input handling
Any entry that fails to parse (not in dictionary, or not a valid token at all,
e.g. `I8A1`) triggers a large modal with an audio beep. The analyst is shown
exactly what was typed and offered two choices: **Re-enter** (dismiss and
retype) or **Edit Dictionary** (jump to the Dictionary tab to add or correct
the taxon). No silent acceptance, no quiet corner notification — the analyst
is often looking through the microscope and must notice the alert.

### Autosave strategy
Grain entries are debounced: the YAML is written within 300 ms of the last
grain keystroke rather than after every individual grain. All other actions —
spike, traverse, remark, undo, new slide, Done / Save, New Sample, and any
Sample Info tab change — trigger an immediate write. In practice this means
the file is always current within a fraction of a second; at most ~300 ms of
rapid grain entries could be lost in a power failure.

"Done / Save" is a manual confirmation button, not the primary save trigger.
Resuming from the autosaved YAML restores grains, traverses, remarks, and
spike total exactly. Individual spike positions within the stream are not
stored in the YAML (only the total); on resume the stream display reconstructs
grain and traverse order but spike marks are not interleaved at their original
positions. All totals and calculated metrics are exact.

### Live metrics
Concentration and PAR are recalculated and displayed after every entry. They
show `NA` when the required inputs are absent rather than hiding the field.
This gives the analyst real-time feedback on whether their metadata is complete
and lets them watch concentration stabilise as the count grows.

### Metadata mutability
All sample metadata (depth, age, title, spike parameters, ΣP groups) are
editable mid-count via the Sample Info tab. Changes take effect immediately and
autosave. The save path is intentionally not editable once counting starts —
changing it mid-count would split a single count across two files.

### Dictionary tab
The loaded dictionary is always inspectable and editable during counting. The
Save Dictionary button writes back to the CSV file. If the source was a `.DIC`
file (fixed-column, read-only format), clicking Save prompts for a CSV path
and converts, after which the session continues with the CSV as the live
dictionary. This means a `.DIC` user is gently migrated to CSV the first time
they edit a taxon mid-count.

### Concentration method
The setup screen asks "Calculate concentration?" with three options, stored as
`conc_method` in `pollen_count$meta` and the YAML:

- **spike** (default) — Stockmarr tracer equation. Spike fields shown.
- **volumetric** — ΣP / sample quantity. Spike fields hidden. Suitable for
  analysts who do not add an exotic spike and instead process a known volume
  of suspension.
- **none** — no concentration computed; Conc and PAR show `NA`.

The method is carried forward on New Sample and restored on Resume. All three
analytical functions that compute concentration (`count_metrics()`,
`site_matrix()`, and the live app display) branch on this field per sample, so
a site can contain samples with different methods and each is handled correctly.

### Preservation codes optional
The setup screen asks "Use preservation codes?" (Yes / No), stored as
`use_pres` in `pollen_count$meta` and the YAML.

When **No**: grain tokens are entered as code only (e.g. `B`, `I`) without a
trailing digit. The count stream displays grains separated by `_` rather than
concatenating code + digit, keeping the stream readable during counting. The
Grain History table shows `—` in the Preservation column and blocks editing of
that column. This mode is designed for proxies (e.g. diatoms, charcoal) where
preservation state is either not recorded or not meaningful.

Default is `TRUE` to preserve backward compatibility with existing YAMLs and
CNT-derived counts.
