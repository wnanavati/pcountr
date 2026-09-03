# pcountr — Design & Decisions Log

This document is the single source of truth for *why* `pcountr` is built the way
it is. It exists so that any new working session (in Claude Cowork, Claude Code,
or with a human collaborator) can continue the project without re-deriving the
reasoning. **Read this first.**

Status as of this writing: **v0.8.0.9000** (development; v0.8.0 released). The verified spine (v0.1.0) is complete
and all planned analytical layers have been built on top of it. 716 test
assertions pass, including reproduction of a real PCount report to the digit.
The Shiny counting app (`count_app()`) is functional and has been used in the
field. Two vignettes ship with the package: *Counting at the Microscope*
(`counting.Rmd`, primary) and *Legacy Workflow: CNT Files to Tilia XML*
(`legacy.Rmd`). Deprecated wrappers `as_rioja()`, `set_depth_age()`, and
`set_depth()` have been removed. New in v0.5.2: concentration method selector
(spike / volumetric / none), optional preservation codes, and
`extract_metadata()`. New in v0.5.3: counting app performance and input
reliability fixes. New in v0.5.4: `apply_metadata()` round-trip workflow,
`set_metadata()` gains `title` and `conc_method`, `spike_units` fix in autosave,
and `read_site()` now stamps full `source_file` path. New in v0.5.5:
`write_site()` for batch YAML export and CNT migration. New in v0.5.6:
optional `value` column in `pollen_dictionary` for half-weight codes in no-pres
counting mode. New in v0.5.7: bug fix — CNT → YAML round-trip now correctly
preserves `hidden` flag and `pres` string for `9`- and `0`-modifier grains
(see NEWS.md). New in v0.5.8: `extract_remarks()`; `pres` standardised to a
concatenated digit string (`"19"`, not `"1;9"`); modifier-only preservation
entries (e.g. `ts9`) now accepted; multi-slide `.CNT` files no longer discard
slide boundaries after the first (see NEWS.md). New in v0.6.0: `rarefaction()`
rewritten — the previous "optimal pollen sum" was circular and always reported
sufficiency; counts are now derived from an extrapolated richness asymptote
(§12). v0.6.1: `pct_smax` redefined as the fitted curve's share at the count
made, so it can no longer contradict the tier columns (§12). v0.6.2: repaired a
malformed `rarefaction` help page (documentation only). New in v0.7.0:
Tilia/Neotoma lookup integration -- `read_tilia_lookup()` and
`standardize_dic()` (§13); an optional confirmation tone on each count in
`count_app()` (session-only, default off); and `QUICKSTART.md` for users with no
R experience. New in v0.8.0: `build_dic_neotoma()` drafts a region-specific
dictionary from the Neotoma records nearest a coordinate (§14).

---

## 1. What this package is

`pcountr` is a keystroke-driven counting application and analysis toolkit for
stratigraphic microscopy. Although built around the MS-DOS program **PCount**
and its pollen-counting workflow, the package is proxy-agnostic: diatoms,
charcoal morphotypes, phytoliths, or any assemblage counted by traversing a
slide follow the same workflow unchanged. The package:

1. provides a **Shiny counting app** (`count_app()`) to replace the DOS
   counting loop — keystroke-driven entry, live running totals,
   concentration and PAR, YAML autosave, resume from any saved count;
2. **reads** legacy PCount files (`.DIC` dictionaries, `.CNT` counts, `.RPT`
   reports);
3. **converts** them into a modern, self-contained native format (YAML), adding
   sample depth and optional age;
4. **reproduces** PCount's report calculations (assemblage sums, tracer-spike
   ratio, concentration, traverse statistics, preservation tabulations);
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

An analyst looks down a microscope and, for each identification, types a short
**taxon code** (defined in a dictionary) plus a **preservation digit**. A known
quantity of **tracer spike** (exotic marker particles — here *Microspheres*, code
`.`) is added to the sample so that **concentration** can be computed from the
ratio of identifications counted to spike counted. The counter watches two
running totals: the **count sum** (ΣP — traditionally the terrestrial pollen
sum) and the **spike count**. Counting proceeds along **traverses** (passes
across the slide), with the analyst noting the microscope stage position so they
can find their place again.

---

## 3. The legacy `.CNT` grammar (reverse-engineered and verified)

A `.CNT` file is:

```
Line 1:  program tag           e.g. "pcount 2.0" / "File created ..."
Line 2:  timestamp
Line 3:  config line            "ECG.DIC, 1, 2, 10000, 0, 2;"
Line 4:  pollen-sum definition  "POLLEN SUM = ABF"
Line 5:  title line             "Fake Lake   FL001   13MAY24"
Line 6+: the count stream, wrapped at ~68 columns (must be de-wrapped/rejoined)
```

The config line fields are:
`dictionary, sample_quantity, spike_tablets, spike_density, <zero>, units_code;`
where `units_code` 1 = ml (→ counts/cm³), 2 = g (→ counts/g).

The count stream, after de-wrapping, is a sequence of these token types:

| Token | Meaning |
|-------|---------|
| `{ ... }` | slide name — the leading one names slide 1; each subsequent one starts a new slide within the sample |
| `CODE` + base digit `1`–`8` + optional modifiers `{0,9}` | one pollen grain |
| `.` | one tracer-spike microsphere (no digit) |
| `/<label>/` | traverse marker (see §5 — label is free text) |
| `[ ... ]` | inline remark, kept verbatim at its position |

### Preservation digits

- A grain has one **base** preservation digit `1`–`8`.
- `0` is **not a state** — it is a *weight modifier* meaning the grain is a
  **half-weight fragment**, counting as **0.5** instead of 1.0. It can ride on top
  of any base digit (e.g. `I80` = Picea, broken, half-weight = 0.5 under class 8).
- `9` (hidden) is also a modifier that can follow another digit.
- **Known code meanings:** 1 = perfect, 2 = corroded, 6 = crumpled, 8 = broken,
  9 = hidden, 0 = half weight.
- **Codes 3, 4, 5, 7** carry no fixed meaning in `pcountr`. Labels for every
  code come from the `preservation` argument to `pollen_site()`, so the scheme
  is defined per project (see §6).
- The base digit is **optional at entry**: a grain may be recorded with a
  modifier alone (e.g. `ts9` = hidden, no base state). Such grains have an
  empty `base` and a `pres` of just the modifier.
- In the data model, `pres` is a **concatenated digit string** — `"19"` for
  base 1 + hidden, not `"1;9"`. Each state is a single digit, so no separator
  is needed. YAMLs written before v0.5.8 used semicolons; `read_pollen_count()`
  strips them on read.
- Combination codes like `680` (crumpled + broken + half) parse correctly; how
  they are attributed in a one-class-per-entry summary is controlled by the
  analyst's `precedence` order (see §6).

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

### Anomalies in real counts
Legacy `.CNT` files accumulated over decades contain genuine data-entry
mistakes — typically a doubled or stray preservation digit. The parser imports
the valid grains, records each anomaly with its stream position and reason, and
warns; it never guesses at the analyst's intent. Regression tests pin the
anomaly count for the validation corpus so the behaviour cannot change silently.
The validation corpus is unpublished site data held locally and is not
distributed with the package (see §9).

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

## 6. Preservation scheme — analyst-defined by design

**The preservation scheme belongs to the analyst, not to `pcountr`.** Both the
code→label mapping and the multi-state precedence order are arguments on
`pollen_site()`:

```r
pollen_site(name, dictionary,
            preservation = default_preservation,   # code -> label
            precedence   = default_precedence)     # multi-state order
```

`default_preservation` follows Cushing (1967), and
`default_precedence` is `8 > 6 > 2 > 9 > 1`. Both are **defaults, not
assertions** — a project using a different taxonomy of damage states overrides
them and every downstream function follows suit.

Consequences of this decision:

- **Codes 3, 4, 5, 7 need no canonical meaning.** They are valid states whose
  labels come from the analyst's `preservation` vector. There is nothing to
  look up and no documentation debt.
- **Multi-state precedence needs no external validation.** When an entry carries
  more than one state and a summary table allows one class per entry,
  `preservation_table(collapse_multistate = TRUE)` resolves it via `precedence`.
  The raw per-entry `pres` string is always retained, so collapsing is a
  presentation choice that discards nothing and is reversible.

This closes what earlier versions of this document tracked as two open
validation debts (confirming 3/4/5/7 against original PCount documentation, and
checking combination-code attribution against a `.CNT`/`.RPT` pair). Neither is
a gap in the package; both were artefacts of treating a configurable default as
a fact needing verification.

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
- `grains` — a data frame, **one row per entry, in counting order**:
  `code, base, pres (concatenated digit string, e.g. "19"), weight, hidden, traverse, position`
- `spike_n` — tracer count
- `traverses` — ordered vector of labels
- `remarks` — list of `{text, position, traverse}`, verbatim, in sequence
- `events` — the full ordered event list (grains, spikes, traverses, remarks,
  slide descriptors) interleaved by position — this is what preserves exact
  counting order
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

**Granularity decision:** per-entry in sequence, because counting *order matters*
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

`count_metrics()` has been verified **to the digit** against an original PCount
`.RPT` report generated by the DOS program from the matching `.CNT` file — every
group sum, the basic and total pollen sums, spike count, sum/spike ratio, grain
concentration, and traverse statistics agree exactly. A 20-sample site parses
completely, with half-grain weighting and anomaly detection confirmed against the
same report.

**The validation corpus is unpublished site data and is not distributed.** The
`.CNT` files, depth sheet, dictionary, and `.RPT` report are gitignored and live
only in the analyst's working directory. The tests that depend on them therefore
run locally but not from a clean checkout; see the note at the head of
`tests/testthat/`.

Data that *is* distributed with the package — the synthetic **Fake Lake** site
(`inst/extdata/fake_lake/`, 20 `.CNT` files, a dictionary, and a metadata sheet)
— exercises the full `read_site()` → `site_matrix()` → `write_tlx()` pipeline and
supports the portable portion of the test suite. It has no corresponding PCount
report, so it cannot substitute for the digit-level verification above.

---

## 10. The Stockmarr concentration equation

```
concentration = (total_pollen_sum / spike_counted) × (spike_tablets × spike_density) / sample_quantity
```

Unit follows the sample's units flag: counts/cm³ (ml) or counts/g (g). Units can
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
Since v0.4.0 the whole ordered event list — grains, spikes, traverses, remarks,
slide descriptors — is serialised to YAML (`format_version: 2`), so resuming
restores the stream exactly as counted, including individual spike positions.
Older `format_version: 1` YAMLs fall back to the previous reconstruction path,
which recovers grain and traverse order and the spike *total* but does not
interleave spike marks at their original positions. Totals and calculated
metrics are exact in both cases.

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

### Slides within a sample
A sample may span several slides. Every sample begins on slide 1; each
`slide_desc` event begins the next one. In a legacy `.CNT` file these are the
`{SLIDE NAME}` tokens — the leading one names slide 1, each subsequent one
starts a new slide. In the app they come from the New Slide button, which
prompts for a slide ID.

Slide identity is therefore a property of *position in the event stream*, not a
scalar on the sample. `meta$slide` holds only the first slide's name, kept for
backward compatibility; anything needing the active slide must walk the stream.
`extract_remarks()` does this to tell the analyst which slide to return to.

### Preservation codes optional
The setup screen asks "Use preservation codes?" (Yes / No), stored as
`use_pres` in `pollen_count$meta` and the YAML.

When **No**: grain tokens are entered as code only (e.g. `B`, `I`) without a
trailing digit. The count stream displays entries separated by `_` rather than
concatenating code + digit, keeping the stream readable during counting. The
Count History table shows `—` in the Preservation column and blocks editing of
that column. This mode is designed for proxies (e.g. diatoms, charcoal) where
preservation state is either not recorded or not meaningful.

Default is `TRUE` to preserve backward compatibility with existing YAMLs and
CNT-derived counts.

---

## 12. Pollen count targets — why the asymptote must be extrapolated

`rarefaction()` answers "how many grains should I count?" This section records
this updated methodology to v0.5.8.

### The circularity

A rarefaction curve built from a sample **terminates at that sample's observed
richness**. Drawing all `N` grains always recovers every taxon present, so
`E[S(N)] = S_obs` as an identity, not an empirical result. Any criterion phrased
as a fraction of observed richness is therefore self-referential:

- "% of asymptote reached" is `E[S(N)] / S_obs` = **1, always**.
- "Smallest `n` reaching `threshold × S_obs`" always exists at or before `N`,
  so "did I count enough?" can only ever answer yes.
- The recommended count scales with the count already made, because it asks at
  what point you had found most of the taxa you happened to find.

A sample cannot be used to test its own sufficiency. The reference must come
from outside the observed count.

### Approaches considered and rejected

**Pooling samples into a site-level type pool** (after Iglesias et al., 2017,
whose reference was a *vegetation zone*). Their 48 modern surface samples were
each counted to ≥300 grains and grouped into six zones defined in the field, and
their reported optima of 180–290 grains therefore sat inside the counts made — a
single sample could reach 90% of its zone's type pool. A fossil core is
different: the union of types down a core encodes **taxon turnover between
samples**, not counting effort. On a nine-sample test core the union was
42 taxa while individual samples held 12–28 — so 90% of the union was 38 taxa,
which no 300-grain count could reach. Every sample would censor. Restricting the
pool to "characteristic" recurrent taxa rescues the arithmetic but requires an
arbitrary recurrence cut, and makes targets incomparable between sites.

**Richness estimators on the observed sample** (Chao1, Good–Turing coverage).
Statistically sound and non-circular, but they estimate richness, not the count
needed to reach it; converting an estimator to a grain target requires an
extrapolation model anyway.

### The method used

Following **Lesven et al. (2026)**, richness is modelled with a
Michaelis–Menten function:

```
R(n) = Smax * n / (K + n)
```

`Smax` is asymptotic richness; `K` is the count recovering half of it. Because
`Smax` lies beyond the observed count, the reference is external to the sample
and a count can genuinely fall short. Inverting gives targets in closed form:

```
n_p = K * p / (1 - p)
```

so 70/80/90% of `Smax` cost `7K/3`, `4K`, `9K` grains. This is the relationship
underlying Lesven et al.'s Table 3: solving for `K` independently from each of
their published 60/70/80/90% columns yields values agreeing to within 0.4 grains
at every one of their ten sites. Their cells cannot be reproduced
digit-for-digit — each is rounded independently, and the tabulated `K` is itself
rounded to an integer — but the internal consistency confirms the inversion.

**One deliberate departure from both papers:** Lesven et al. estimated the curve
by resampling (1000 draws per increment) and Iglesias et al. by 100 random
rearrangements, whereas `pcountr` computes it **analytically** from the exact
expectation given by Hurlbert (1971),
`E[S(n)] = sum_i [ 1 - C(N - N_i, n) / C(N, n) ]`. This makes `Smax`, `K`, and
all targets deterministic and independent of `set.seed()`. Permutations are
retained only for the confidence band on plotted curves. Fitting is by separable least squares — `Smax` is closed-form given `K`,
so only `K` is optimised, over `log(K)` — which reduces the problem to one
well-conditioned dimension with no starting values and no added dependency.
`stats::optimize()` assumes unimodality and returns a local optimum; on the
curves tested this matched a dense grid search, but that is not guaranteed.

### Reported quantities must come from the same source

`pct_smax` is the share of `Smax` the **fitted curve** reaches at the count made,
`100 * N / (K + N)`. It is deliberately *not* `n_taxa / s_max`.

This distinction caused a real defect in v0.6.0, worth recording. `pct_smax` was
defined as observed richness over the modelled asymptote while the tier columns
came purely from the model. Because Michaelis–Menten approximates the whole curve
rather than interpolating its endpoint, the fit sits slightly *below* observed
richness at `n = N` — so the observed ratio was systematically more optimistic
than the model, and rows contradicted themselves: a sample could report reaching
90% of `Smax` on 347 grains while its own `n90` column asked for 531.

Taking the share from the model makes the row consistent by construction, since

```
N >= K*p/(1-p)   <=>   N/(K+N) >= p
```

so `pct_smax >= 80` holds exactly when `N >= n80`. It also matches the sense in
which Lesven et al. state that 250 grains recovers >70% of richness — a model
quantity, not an observed one.

The general lesson: an observed quantity and a modelled one should not be placed
in the same row inviting comparison unless they are commensurable. The observed
share remains available by comparing `n_taxa` against `s_max` directly.

### No verdict is returned

Adequacy is objective-dependent, so `pcountr` reports and does not judge.
Lesven et al. found ~250 grains adequate for dominant vegetation assemblages
(~70% of richness) but recommend ~1000 grains for biodiversity assessment or
detection of rare taxa (85–95%). Iglesias et al. likewise report their optima as
consistent with the established convention of 300 grains for standard studies
and 500–1000 where rare pollen types are of interest. The output gives
`pct_smax` (what this count recovered) and the 70/80/90% tiers (what more effort
buys); the analyst chooses.

### Known limits

- **`Smax` is extrapolated, not observed.** Lesven et al. found *no* curve
  reaching a true asymptote within 1000 grains in their samples. Fits from ~300-grain counts sit
  on the steep limb of the curve, where `Smax` is poorly constrained by the data
  — a small change in curvature moves the asymptote a long way. Treat targets as
  provisional and read `s_max` and `k` alongside them.
- **Tiers depend only on `K`.** Two samples may need identical counts while
  having different ceilings; `K` is curve steepness, `Smax` is the ceiling.
- **Evenness matters alongside richness.** Iglesias et al. (2017) note that the
  count required depends on both: a dominated assemblage spends much of its count
  on the dominant taxon, leaving fewer grains to sample the rest. Two samples of
  equal size and equal observed richness can therefore return different targets.
- **Taxonomic resolution is confounded.** A dictionary that lumps types lowers
  `Smax` and shrinks targets. Comparisons across sites require a common
  dictionary.
- **Targets are site-specific** and should be recomputed rather than transferred.

### Half-grains

Each recorded grain counts as one detection, so a half-grain (modifier `0`,
weight 0.5) contributes one individual. Richness is about detections, and
rounding summed weights per taxon biases exactly the rare taxa that determine
where the curve flattens.

---

## 13. Tilia / Neotoma lookups — an authority, not a source

`read_tilia_lookup()` and `standardize_dic()` reconcile a dictionary against
Neotoma's taxon authority as distributed with Tilia. This section records why the
lookup is checked against rather than copied from.

### A lookup cannot be a counting dictionary

Two reasons, both structural:

- **The codes are the wrong kind.** Every lookup taxon has a `Code`, but it is
  Tilia's display abbreviation — `Ane.s.`, `Nit.or`, `Pla.sp1LLC` — three to ten
  characters for spreadsheet column headers. Counting needs one or two characters
  the analyst can type three hundred times without looking. Those are the
  analyst's own and cannot come from an authority file.
- **The scale is wrong.** The pollen lookup holds 49,188 taxa because it is the
  whole Neotoma taxonomy: 8,513 diatoms, 15,257 insects, 890 ostracodes. Only
  22,426 are palynomorphs. A working dictionary holds tens. Matching is therefore
  restricted to palynomorph `TaxaGroup`s by default, which also stops a pollen
  taxon matching a beetle.

So the dictionary stays the analyst's, and the lookup supplies standardised names
and ecological groups on request. The payoff is chiefly Neotoma submission via
`write_tlx()`.

### Two group dimensions, and why they are not remapped

Tilia nests a four-letter `EcolGroup` inside a three-letter `TaxaGroup`. The
ecological groups relevant to pollen are `TRSH` trees and shrubs, `UPHE` upland
herbs, `VACR` terrestrial vascular cryptogams, `AQVP` aquatic vascular plants,
`UPBR`/`AQBR` bryophytes, `UNID` unknown palynomorphs, `ANAC` anachronic
(reworked), plus `SUCC`, `MANG`, `PALM` and others.

These do **not** map one-to-one onto PCount's `A`/`B`/`F`/`Q`/`X`. Checking a
231-taxon dictionary against the lookup found 19 disagreements: taxa filed under
`B` that Neotoma classes `TRSH`, others it classes `SUCC` or `AQVP`.

**No comparison is made by default.** `group_map` is `NULL`, `group_differs` is
`NA`, and `ecol_group` is reported purely as reference for a Neotoma upload.

The reasoning: an ecological group is in practice a "sum by" list, and the
baggage around ecological affinity makes a standardised list impractical to hold
centrally. Cyperaceae is `UPHE` in the lookup but legitimately aquatic in some
settings, and the analyst who saw the landscape is better placed to judge than an
authority file. Flagging such a row as a disagreement would present the lookup's
assignment as correct and the analyst's as deviant, which is not a defensible
default.

The comparison is therefore opt-in via `group_map`, and even then nothing is
changed — reassigning a group moves a taxon between pollen sums and so alters
every percentage, concentration and accumulation rate.

This is consistent with how the rest of the package already works: `pollen_sum`
*is* the sum-by list, configured per site, and `preservation` / `precedence` are
overridable the same way (§6).

Read with `group_map` supplied, the audit does still surface real filing errors —
*Cystopteris bulbifera* (a fern) under herbs, cf. *Hypericum* (a herb) under
spores — which is why it remains available rather than removed.

### Fuzzy matching may never be applied in bulk

String similarity is unreliable on taxon names, and the failures are not subtle.
Ranking the `suggestion` rows from the 231-taxon ECG dictionary by score
interleaves the useful with the unusable:

| Similarity | Dictionary name | Best candidate | Verdict |
|---|---|---|---|
| 0.91 | `Lycopodiella inundatum` | *Lycopodiella inundata* | right — gender agreement |
| 0.89 | `Zygadenus` | *Zigadenus* | right — spelling |
| 0.75 | `Cerealia undiff.` | *Sordaria* undiff. | wrong — cereal grasses to a fungus |
| 0.75 | `Primula quadriflora-type` | *Primula farinosa-type* | wrong — a different species |
| 0.72 | `Dendrolycopodium obscurum` | *Lycopodium obscurum* | right — a real synonymy |
| 0.67 | `Microcharcoal` | Microchaetaceae | wrong — charcoal to a cyanobacterium |

No cutoff separates these. A threshold of 0.75 would accept the fungus and the
wrong *Primula* while rejecting the correct *Lycopodium* synonymy directly below
them. The signal is not in the string.

Ties compound it. `Spinulum annotinum` scores 0.60 against three candidates at
once — *Lycopodium annotinum*, which is the correct answer, plus *Tripolium
pannonicum* (an aster) and *Trifolium pannonicum* (a clover). `Pre-Quaternary
undiff.` scores 0.59 against four families simultaneously (*Arecaceae*,
*Primulaceae*, *Proteaceae*, *Pteridaceae* undiff.). `which.max` returns whichever
appears first in the pool, so on tied rows the displayed candidate is an artefact
of pool order rather than a property of the data.

Hence `status = "suggestion"` is advisory only: reachable by individual code or
name, never as a class, and with no `"all"` shorthand.

### Normalisation folds spelling, not meaning

`.norm_taxon()` folds diacritics, punctuation and abbreviation variants
(`c.f.`/`cf.`, `subgen.`/`subg.`, `subfam.`/`subf.`) and nothing else.

It must not touch `-type`, `cf.` or `aff.`. Those encode determination precision:
`Betula-type` is a morphotype resembling *Betula*, not a determination of it. An
early draft stripped `-type` and classified `Tidestromia lanuginosa-type` as a
mechanical variant of *Tidestromia lanuginosa*, which would have promoted a
morphotype to a species identification without comment.

Extending normalisation to the **synonym** table as well as the accepted-name
table matters more than it sounds. A dictionary written with `subgen.` where
Neotoma writes `subg.` hides authoritative answers behind an abbreviation: doing
so resolved `Pinus subgen. Diploxylon` to *Pinus* subg. *Pinus* and
`Pinus subgen. Haploxylon` to *Pinus* subg. *Strobus* — precisely the pair that
fuzzy matching got backwards.

Diacritic folding uses explicit `\u` escapes rather than
`iconv(to = "ASCII//TRANSLIT")`, whose output is platform-dependent and can emit
`?` on Windows, silently breaking matches such as *Isoetes* / *Isoëtes*.

### No alias table ships with the package

Once normalised synonym matching is in place, what remains unresolved is not
universal fact but local convention: whether `Monolete spore undiff.` is
Neotoma's `Filicopsida (monolete) undiff.`, how reworked pre-Quaternary grains
are recorded, whether a regional morphotype has an authority equivalent at all.

A bundled table would mean `pcountr` asserting taxonomic equivalences on the
analyst's behalf, maintaining them as Neotoma revises, and imposing a North
American ECG-derived view on users whose hard cases differ entirely. So
`aliases` is a user file, `read_tilia_lookup()` stays a pure reader, and pointing
`aliases` at a non-existent path writes a template from the unresolved rows.
Alias matches are reported as `status = "alias"`, distinct from an authoritative
`synonym`, so it is always clear which substitutions came from Neotoma and which
from the analyst.

### The Neotoma API: rejected at v0.7.0 on a mistaken premise, adopted at v0.9.0

Neotoma serves taxa over HTTP at `api.neotomadb.org/v2.0`, without a key. At
v0.7.0 the API was rejected for reconciliation on one stated reason: that it
**did not expose the synonymy**. The evidence looked convincing. `Alnus rugosa`
returns `taxonid` 14749 from `/data/taxa`, flagged only by a bracketed
`taxoncode` (`[Aln.rg]`) and a null `ecolgroup`, with nothing in the response
pointing at taxon 344, *Alnus incana*. The XML states that mapping outright.

**That conclusion was wrong, and the error was one of search rather than of
reasoning.** Only the documented `/data/taxa` route had been tested. There is
also a generic table passthrough, `/data/dbtables/{table}`, and
`dbtables/synonyms` returns exactly the missing mapping:

```
{"synonymid":3,"invalidtaxonid":14747,"validtaxonid":62,"synonymtypeid":1}
```

`invalidtaxonid -> validtaxonid` is the deprecated-to-accepted pointer. It
matches the XML row for row: synonym 14747 is `<Synonym ID="14747">`
`<Name>Iva ciliata-type</Name><TaxonID>62</TaxonID>`. The `valid` flag that this
section previously said did not exist is in `dbtables/taxa`; `/data/taxa` omits
it and offers `status` instead, which is extant/extinct and a different field
entirely. Two routes, two vocabularies, one wrong inference.

The synonymy is what `standardize_dic()` depends on most -- it resolves every
`synonym` row, and it is what turns `Pinus subgen. Diploxylon` into *Pinus*
subg. *Pinus* authoritatively, where fuzzy matching scores that name highest
against *Cornus* subg. *Cynoxylon*, a dogwood, at 0.62. So the requirement was
real; only the belief that the API could not meet it was mistaken.

### Why the API path was then built (v0.9.0)

The v0.7.0 decision had a cost that had nothing to do with the synonymy:
**Tilia installs only on Windows**, so macOS and Linux analysts could not
reconcile a dictionary at all. The limitation was not even documented -- it was
communicated solely by a hardcoded path in an error message.

`neotoma_taxonomy()` therefore fetches the taxonomy from the API and returns it
in the same `tilia_lookup` shape, so `standardize_dic()` accepts either
interchangeably. `read_tilia_lookup()` remains, and remains the default when a
Tilia install is present: it is offline and pinned to whatever version that
install carries.

Three implementation points, each forced by something measured:

- **The taxa table comes from `/data/taxa`, not `dbtables/taxa`.** The dbtables
  route is leaner but has no `ecolgroup`. Getting groups from
  `dbtables/ecolgroups` would mean a second unfilterable table *and* a choice
  of "ecolset" -- there is one per proxy (1 = Default plant, 8 = Default
  diatom, 10 = Default palynomorph, and so on), and picking wrongly would
  mislabel every taxon. `/data/taxa` returns the group already resolved, which
  removes the decision.
- **Nothing filters server-side.** `taxagroupid=DIA` is silently ignored on
  both routes -- vascular-plant rows still come back. So the whole table is
  paged and `taxa_group` is applied to the cached copy. The `publication`
  string is roughly 60% of the payload and is dropped per page, so the cache is
  a small fraction of the download.
- **The result is cached** under `tools::R_user_dir("pcountr", "cache")`, the
  one location CRAN policy permits a package to write. Without a cache the
  download would repeat every session, which is both slow and inconsiderate to
  a community server.

Two consequences worth stating plainly. The API taxonomy is live, so a
reconciliation run today may not match one next year; the object records its
fetch time and prints it. And `dbtables/` is undocumented -- it works, and
Neotoma's own Taxonomy-Viewer is built on it, but it is not a published
contract, so `read_tilia_lookup()` is the fallback if it ever changes.

**Verified against the Tilia path on real data.** The 231-taxon ECG dictionary
reconciles identically through both sources: 211 `exact`, 14 `suggestion`,
6 `unmatched`, with the same suggested targets and the same similarity scores to
two decimals. (At the time of the first comparison this was 210/14/7; renaming
the dictionary's entry for code `V` to Neotoma's spelling, `Asteroideae
undiff.`, moved one row from `unmatched` to `exact` -- an illustration of the
reconciliation being used for its intended purpose rather than a change in
either source.) `Alnus rugosa` resolves to taxon 344, *Alnus incana* -- the exact
case this section previously cited as something the API could not do. The two
snapshots are not identical (the live taxonomy holds 22,462 palynomorphs against
the Tilia file's 22,426, having gained 36 since that file was written), but none
of the difference changed a reconciliation outcome. The API fetch returns 59,077
taxa, of which 56,167 are accepted once the 2,910 deprecated ones are removed --
a figure that matches the 2,911 synonyms almost exactly, so the accepted and
deprecated sets are self-consistent. Cached, the whole taxonomy is 780 KB.

**One table, all proxies.** This is the part that outgrows Tilia rather than
merely matching it. Tilia ships eleven per-proxy XML files and pcountr defaulted
to the pollen one, so the pollen framing was baked into the file layout. The API
has a single table spanning vascular plants, diatoms, ostracodes, phytoliths and
the rest, distinguished by `taxagroupid`. A diatom analyst now gets a real
vocabulary from the same call that serves a palynologist.

Three later uses remain open, none of them replacements:

- `status = "extinct"` bears on reworked pre-Quaternary categories and is absent
  from the lookup entirely.
- Authority publications would let a methods section cite *why* a name is
  accepted.
- A light currency check could flag names revised since the lookup snapshot was
  written, without re-downloading 11 MB.

Two things were not established and would need confirming before any of that:
whether an undocumented synonymy endpoint exists -- the Swagger UI is a
JavaScript shell and could not be read programmatically -- and whether
bracketed-`taxoncode`-with-null-`ecolgroup` is a documented contract or an
implementation detail unsafe to rely on.

**This was later revisited, and the conclusion narrowed rather than reversed.**
The API remains unsuitable for `standardize_dic()`, for exactly the reason
above: reconciling a deprecated name requires the synonymy, and the API does
not expose it. But *building* a dictionary needs the opposite thing -- accepted
names in current use -- which the API serves well. So the API is now used for
that one purpose only, in `build_dic_neotoma()`. See section 14. The Tilia XML
remains the sole authority for reconciliation, and the offline path is
untouched.

---

## 14. Region-specific dictionaries from Neotoma (v0.8.0)

`build_dic_neotoma()` returns a draft dictionary of the taxa most widely
recorded near a coordinate. It is a starting point, not an authority: the
analyst fills in the codes and reviews the groups, then checks the result
against a Tilia lookup with `standardize_dic()`.

### Proximity, not political boundaries

The first design used `country` and `region`, since Neotoma stores nested
geopolitical units and `gpid` accepts them directly. That was replaced by a
coordinate and a radius, because vegetation does not stop at a state line. The
measured difference is not small: a 250 km search around a site in western
Montana returns 38 sites reaching into Idaho and Wyoming, where `gpid =
"Montana"` returns 16. The state boundary was excluding the nearest analogues.

Ambiguity was a secondary reason. `gpname=Montana` resolves to two units --
7754, a state of the United States, and 637, a province of Bulgaria -- and the
API picks one silently. A coordinate cannot be ambiguous.

### Measured costs, which shaped the defaults

| Query | Time | Result |
|---|---|---|
| `gpid = "Montana"`, pollen, `all_data` | 4.8 s | 16 sites |
| `loc` 50 km, sites, `all_data` | 74.2 s | 5 sites |
| `loc` 100 km | 143.1 s | 24 sites |
| `loc` 250 km | 146.0 s | 166 sites |
| `loc` 500 km | 209.6 s | 1284 sites |
| **`loc` 250 km + `datasettype`, datasets** | **39-49 s** | **38 sites** |

Three conclusions follow, and each is a default in the code:

1. **Query datasets, not sites.** Filtering `datasettype` server-side made the
   same 250 km box three times faster than the equivalent `get_sites()` call.
2. **A generous radius is nearly free.** 74 s to return five sites at 50 km
   means roughly 70 s is fixed overhead, and the whole 50-500 km range spans
   only 74-210 s. Shrinking the box to save time does not work, so the default
   radius is 250 km.
3. **Bound the download, not the search.** Enumeration is cheap; each download
   is about 92 KB. So enumeration uses `all_data = TRUE` -- without it the API
   silently caps at 25 and ranking an arbitrary 25 sites by distance would be
   meaningless -- while `max_sites` caps the expensive step. Cost is therefore
   set by the analyst rather than by how dense the region happens to be.

### Presence, not abundance

Taxa are ranked by the number of distinct sites they occur in. Ranking by
abundance would return little beyond *Pinus*, *Artemisia* and Poaceae; ranking
by sample count would reward a taxon that is locally abundant at one site over
one that is present across the whole region. A dictionary should list what an
analyst is likely to *meet*, which is a presence question.

The tally counts distinct site-taxon pairs, not rows, and is computed from
`samples()` rather than `taxa()`. `taxa()` looks like the natural choice --
it returns `sites` and `samples` counts directly -- but it aggregates by
`units`, `element`, `elementtype` and more, so one taxon can span several rows.
Summing those double-counts sites that appear in two of them and taking the
maximum undercounts sites that appear in one, and the true distinct-site count
cannot be recovered from the aggregate. Counting pairs is correct by
construction.

### What is filtered, and what deliberately is not

`units == "NISP"` does most of the work: it drops every laboratory row, since
tablets are recorded in `grains/tablet`, sample quantity in `ml` and the spike
count in `number`. `LABO` and unidentified groups are then excluded from the
ranking explicitly.

Two things are kept on purpose. Algal colonies (`Botryococcus`, `Pediastrum`)
are `NISP`, neither laboratory nor unidentified, and analysts genuinely tally
them -- so `datasettype = "pollen"` yields a palynomorph dictionary rather than
a strictly-pollen one. And `Unknown` and `Indeterminable` are added back as
fixed entries alongside the spike, in Neotoma's own spelling, so they return
`exact` from `standardize_dic()`.

Slash-combined names such as `Larix/Pseudotsuga` are single morphotypes and are
never split.

### Codes are left blank, and groups are only a starting value

Entry codes are an analyst's muscle memory; nobody should inherit someone
else's. The consequence is that the result is not a `pollen_dictionary` and
will not load until the codes are filled, because `read_dic_csv()` drops rows
with a blank code. The function therefore returns a plain data frame and says
so, rather than handing back something that looks valid and loads empty.

Groups are imported from Neotoma's `ecologicalgroup` because a blank group
would make `read_dic_csv()` infer `is_special = TRUE` for every taxon. They are
a starting value only. This follows the same reasoning as section 13: a
dictionary's groups encode the analyst's pollen-sum decisions and are not the
lookup's to correct. The first real run returned `Cyperaceae` as `UPHE`, which
is precisely the case where an analyst with local knowledge may say `AQVP`.

### Charcoal does not work, and cannot

Charcoal has five datasettypes, and none carries a taxon vocabulary. Every
`datum` in a macrocharcoal dataset has one of two `variablename` values,
`Charcoal` or `Sample quantity`. What varies is the size fraction in
`elementtype` -- two records inspected used `>500 um` and `>125 um`. A "which
size classes are used near me" query would be useful and is a different
function. `datasettype` is passed through verbatim, so a charcoal type returns
a near-empty draft without a special case.

### Dependency and testing

`neotoma2` is in `Suggests:`, guarded by `requireNamespace()` and called with
`::`. It imports `sf`, `leaflet`, `dplyr` and more, which is a poor trade for
software that must work offline beside a microscope. `sf` is avoided even for
the geometry: `parseLocation()` accepts a GeoJSON character string, so the
bounding box is built with `sprintf()` and the distances with haversine in base
R.

One neotoma2 constraint is worth recording, since it cost an afternoon: `loc`
accepts an `sf` object, an `sfg`, a numeric bbox or a GeoJSON string, but *not*
an `sfc`. `parseLocation()` has no `sfc` branch and no `else` guard, so an
`sfc` falls through every branch and fails with `object 'geojson' not found`
before any request is sent. Present in both CRAN 1.0.12 and GitHub 1.1.0.

The network path is not tested. `R CMD check` must not depend on
api.neotomadb.org, and a spatial query there takes tens of seconds. The tally,
the filtering, the fixed entries, the geometry and the distance arithmetic are
all tested against a fixture shaped like real `samples()` output -- the same
approach as the synthetic Tilia lookup in section 13.

