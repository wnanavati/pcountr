# pcountr NEWS / changelog

## pcountr 0.8.0.9000 (development version)

### New — release and contribution metadata

Groundwork for a citable release:

- **`inst/CITATION`** — so `citation("pcountr")` returns something sensible. A
  `citFooter` asks that PCount be cited separately where its file formats or
  report calculations are central, which is the honest attribution given how
  much of §3 and §10 derive from Grimm's work.
- **`CITATION.cff`** — drives GitHub's "Cite this repository" panel, and carries
  a `references` entry for PCount 2.0.
- **`.zenodo.json`** — so the Zenodo deposit gets real metadata rather than
  whatever it infers from the repository name.
- **`CONTRIBUTING.md`** — issue guidance, the `dev`-branch workflow, the
  `document()` / `test()` / `check()` expectation, and the fact that `NAMESPACE`
  is hand-maintained. It states plainly which real data is published on purpose
  (`LMSH001.CNT`, `LM23SH00.RPT`, all of Fake Lake) and that nothing else from
  that site may ever be committed.
- **`.github/workflows/R-CMD-check.yaml`** — Ubuntu, Windows and macOS at R
  release. Windows earns its slot because `tilia.R` discovers the lookup
  directory from `%LOCALAPPDATA%` and `C:/ProgramData`, and that branch runs
  nowhere else. No job needs the network: the Neotoma tests either fail argument
  validation before any request or point `pcountr.neotoma_api` at
  `127.0.0.1:1`.

The citation files deliberately carry **no DOI**. A placeholder would be an
identifier that does not resolve, so the field is omitted until the first Zenodo
deposit exists; ROADMAP.md records the one-line edit each file then needs.

`.Rbuildignore` gained the four new paths, and also `vignettes/legacy_files` —
the build has been producing that directory since the vignette was renamed,
while the ignore rule still read `workflow_files`.

Not done, and tracked in ROADMAP.md: the `DESCRIPTION` title still reads
"Interactive Stratigraphic **Grain** Counter", which the agnostic pass missed.
It is the string that propagates into all three citation files, so it wants
settling alongside the manuscript title — and it is far cheaper to change before
a DOI exists than after.

### Changed — the counting app no longer assumes pollen

pcountr has always worked for diatoms, charcoal morphotypes and other proxies,
but its interface said otherwise. The labels an analyst actually reads are now
neutral:

| Was | Now |
|---|---|
| "Grain History" tab | "Count History" |
| `Conc (grains/cm³)`, `PAR (grains/cm²/yr)` | `counts/cm³`, `counts/cm²/yr` |
| "ΣP — Analyst defined pollen sum" | "ΣP — analyst-defined sum" |
| `0 = half-grain` | `0 = half weight` |
| "Special marker (non-pollen, e.g. #NPP code)?" | "Special marker, excluded from sums (e.g. #NPP code)?" |
| "No grains counted yet." | "No counts yet." |
| "Loaded: … (N grains)" | "Loaded: … (N identifications)" |

`count_app()`'s help page and the README lead with the general case rather than
naming pollen first.

Relabelling the app's concentration display exposed a second source for the same
string: `count_metrics()` builds its own `concentration_unit` from the sample's
units flag, so the app would have read `counts/cm³` while the function returned
`grains/cm3`. `count_metrics()` now returns `counts/cm3`, `counts/g` and
`counts/unit`, and `accumulation_rate()`'s documented units follow. The
descriptions that quote those labels back to the reader — the live-metrics lists
in the `counting` and `legacy` vignettes, the `ΣP` row of the QUICKSTART setup
table, and the format and concentration sections of `DESIGN.md` — were corrected
to match. These are accuracy fixes rather than part of the labelling pass: they
document what the app displays, so leaving them would have made the docs wrong.

The pass then extended to the roxygen for every function that operates on live
counts — `accumulation_rate()`, `count_metrics()`, `preservation_table()`,
`pollen_site()`, `pollen_count()`, `remarks()`, `site_matrix()`, `write_tlx()`
and `write_count_yaml()`. "Grain" becomes "entry" or "identification", "pollen
sum" becomes "count sum" (\eqn{\Sigma P}), and `SpikeCount` / `SpikeConc` are
described in "markers" rather than "grains", which is also more accurate for
microsphere tracers.

One change reaches exported **data** rather than documentation:
`default_preservation["0"]` was the label `"half-grain"` and is now
`"half weight"`, matching the app legend. No test asserted the old value and no
print method indexes the vector, but it is a user-visible string and anyone
matching on it should know.

Two stale claims surfaced while doing this and were corrected: `read_dic()`'s
column table still described taxon codes as "1–2 characters", which stopped
being true when codes became unbounded earlier in this version, and
`accumulation_rate()`'s title promised "pollen influx". `PAR` is retained as the
conventional acronym, with its palynological origin now stated explicitly rather
than implied.

Names that stay, because renaming them breaks saved counts or callers' code:
the `pollen_site` / `pollen_count` / `pollen_dictionary` classes, the `grains`
data frame and YAML key, the `pollen_sum` and `pollen_sum_groups` arguments,
`site$pollen_sum`, and `count_metrics()`'s `mean_grains_per_traverse` field.
Each is now documented as keeping a historical name, so the docs no longer imply
the package only counts pollen.

**What was deliberately left alone**, and why:

- The `pollen_site`, `pollen_count` and `pollen_dictionary` class names, and the
  `grains` key in the YAML format. Renaming the key would break every saved
  count; the classes are largely invisible to users, and renaming them is a
  breaking API change better made once, deliberately, than folded into a
  labelling pass.
- Everything documenting a legacy file format — the `.CNT` and `.DIC` reader,
  the `.RPT` report whose quantities `count_metrics()` reproduces, and the Tilia
  lookup (`.TIL`) and alias machinery in `read_tilia_lookup()` and
  `standardize_dic()`. Those formats came out of PCount and Tilia, which were
  pollen tools; describing them in neutral language would misrepresent what they
  are. The `.CNT` header literal `POLLEN SUM =` is PCount's own — changing it
  would produce files PCount could not read. Note that Tilia lookups are
  themselves proxy-aware, so `read_tilia_lookup(type = )` already accepts
  `"diatom"`, `"ostracode"`, `"phytolith"` and the rest.
- `QUICKSTART.md`, which declares itself a guide for palynologists in its first
  line. Pollen language there is accurate rather than careless, and a beginner
  guide reads more clearly with one concrete proxy throughout. A sibling guide
  for a non-pollen proxy is on the roadmap.
- `rarefaction()`'s "Grains" column heading. Worth noting that rarefaction is
  *not* a pollen technique — paleolimnology uses it routinely to standardise
  diatom richness across unequal counts, and count-adequacy studies exist for
  testate amoebae, cladocera and chironomids — so the label is narrower than
  the function. Queued rather than done, since the Michaelis–Menten target
  scheme itself derives from pollen work.

### New — entry codes of any length, and suggested codes

**The two-character cap on entry codes is gone.** Codes may now be any number
of letters. Nothing required the old limit: codes are letters and preservation
codes are digits, so a greedy letter match stops at the first digit whatever
the code's length. One or two characters remains the sensible habit — every
keystroke is one an analyst repeats hundreds of times per sample — and the
documentation says so, but it is advice rather than a rule.

Legacy `.CNT` reading stays capped at two, since files written by PCount cannot
contain longer codes and keeping that parser tight still catches corruption.

**The Add Dictionary Row dialog now validates the code.** It previously accepted
any non-empty string, so a code such as `A1` could be added and would then be
untypeable — the entry parser reads trailing digits as preservation, so it would
arrive as code `A` with preservation `1`. Codes containing digits, and duplicates
of existing codes, are now refused with an explanation.

**`build_dic_neotoma()` suggests codes.** The `code` column is filled by default
(`suggest_codes = TRUE`), from two sources in order:

- Where a Neotoma name matches an entry in the dictionary shipped with the
  package, that curated code is reused — a code an analyst actually chose beats
  one derived mechanically. This is why *Artemisia* comes back as `R` and
  *Apiaceae* as `UM`, which no derivation would produce.
- Otherwise the code is built from the name, following the convention in that
  dictionary: initials for a two-word name (*Acer negundo* → `AN`), the first
  two letters for a single word (*Abies* → `AB`), with longer forms only when
  those are taken.

Every candidate is letters only, so a suggested code can never end in a digit
and become unparseable. Assignment is deterministic given the input order, so
rebuilding a dictionary does not reshuffle codes. `suggest_codes = FALSE`
restores the blank column.

Neotoma's own `taxoncode` is deliberately not used: it is a Tilia display
abbreviation (`Ace.sa-t`, `Ane.s.`) carrying periods and hyphens, and `.` alone
is the spike, so sanitising it would produce collisions and keystroke-hostile
codes.

**One shipped-dictionary name updated.** The entry for code `V` was
`Asteraceae subfam. Asteroideae undiff.`, which Neotoma does not recognise, so
it reconciled as `unmatched` *and* a Neotoma-built dictionary derived a fresh
code for `Asteroideae undiff.` instead of reusing `V`. Renaming it to Neotoma's
spelling fixes both: reconciliation of the shipped dictionary is now 211 `exact`
and 6 `unmatched`, and `Asteroideae undiff.` gets the curated code `V`. A test
pins that so a future edit cannot silently undo it.

`ECG.DIC` is deliberately left alone. It spells the same taxon
`Asteraceae subfam. Tubuliflorae undiff.`, older still, and its job is to be
the legacy PCount artefact that `read_dic()` parses — it happens to illustrate
exactly the nomenclature drift `standardize_dic()` exists to catch.

### New — the Neotoma taxonomy without Tilia

`standardize_dic()` previously required Tilia's lookup files, and **Tilia
installs only on Windows** — so macOS and Linux analysts could not reconcile a
dictionary at all. The limitation was not even documented; it was communicated
by a hardcoded path in an error message.

`neotoma_taxonomy()` fetches the same taxonomy from Neotoma's API and returns it
in the same shape, so `standardize_dic()` accepts either interchangeably:

```r
lk <- neotoma_taxonomy()                      # all proxies
lk <- neotoma_taxonomy(taxa_group = "DIA")    # diatoms only
standardize_dic(my_dic, lk)
```

With no `lookup` supplied, `standardize_dic()` now tries a local Tilia install
first — it is offline and pinned to that install's version — and falls back to
the API.

**Verified to agree with the Tilia path.** The 231-taxon ECG dictionary
reconciles identically through both sources — 211 `exact`, 14 `suggestion`,
6 `unmatched`, same targets, same similarity scores — so the two are genuinely
interchangeable rather than merely similar. The live taxonomy has drifted a
little from the Tilia snapshot (22,462 palynomorphs against 22,426), but no
difference changed an outcome. The cached taxonomy is 780 KB.

**One table, all proxies.** This outgrows the Tilia route rather than merely
matching it. Tilia ships eleven per-proxy XML files and pcountr defaulted to the
pollen one, so pollen was baked into the file layout. Neotoma's API has a single
table spanning vascular plants, diatoms, ostracodes, phytoliths and the rest,
distinguished by `taxa_group`. A diatom analyst now gets a real vocabulary from
the same call that serves a palynologist.

**Cached, because the fetch is large.** Nothing filters server-side —
`taxagroupid=DIA` is silently ignored and vascular-plant rows come back anyway —
so the whole table is paged and filtered locally. The result is cached under
`tools::R_user_dir("pcountr", "cache")`, the one location CRAN policy permits a
package to write, so the download happens once per machine rather than once per
session. `neotoma_taxonomy_cache()` reports where it lives and can clear it. The
verbose `publication` field is dropped as pages arrive, so the cache is a small
fraction of the download.

Two caveats stated plainly. The taxonomy is live, so a reconciliation run today
may not match one next year; the object records its fetch time and prints it.
And `dbtables/` is undocumented — it works, and Neotoma's own Taxonomy-Viewer is
built on it, but it is not a published contract, so `read_tilia_lookup()`
remains as the fallback.

Neotoma data are CC BY 4.0. Cite the database (Williams et al., 2018) alongside
pcountr if you use this in published work.

### Corrected — an earlier claim about the API was wrong

DESIGN.md section 13 stated that the Neotoma API "does not expose the
synonymy", and that was the stated reason for rejecting it at v0.7.0. **The
claim was false.** Only the documented `/data/taxa` route had been tested;
`/data/dbtables/synonyms` returns `invalidtaxonid -> validtaxonid`, which is
exactly the deprecated-to-accepted mapping, and it matches Tilia's XML row for
row. The `valid` flag said not to exist is in `dbtables/taxa`. The section has
been rewritten to record the mistake rather than quietly drop it.

### Fixed

- Tilia's lookup path is now discovered rather than hardcoded.
  `C:/ProgramData/Tilia/Lookup` was the only location checked, but Tilia's own
  documentation gives `%LOCALAPPDATA%/Tilia/Lookup`; both are tried, first
  existing wins, and `options(pcountr.tilia_lookup)` still overrides.

- `default_preservation` and `default_precedence` were documented with
  `@export` and shipped help pages, but were absent from `NAMESPACE`, which is
  maintained by hand. Neither object was actually reachable — `default_preservation`
  raised "object not found" — so the documented ability to inspect the default
  preservation scheme did not work. Both are now exported. `R CMD check` had not
  flagged this: an object that is documented but unexported is not a checked
  condition.

### Changed — the test suite no longer depends on unpublished data

Every test now runs against data distributed with the package. Previously seven
test files read a local, unpublished site, so the suite passed only on one
machine; it could not run in continuous integration and would have failed on
CRAN's builders.

- Site-level tests use the bundled **Fake Lake** example site (20 `.CNT` files)
  and its `metadata_FL.csv`. That sheet uses the standard column names, so the
  fixtures no longer need a `col_map`.
- Two files are now published deliberately: `inst/extdata/LMSH001.CNT` and the
  PCount report `LM23SH00.RPT`. These back the golden test that reproduces an
  original PCount `.RPT` to the digit, so that claim is now independently
  reproducible rather than resting on one machine. One sample of twenty; the
  remaining samples and the depth sheet stay unpublished.
- Edge cases moved to equivalent Fake Lake material: decimal traverse labels to
  `FL019`, the inline remark to `FL011`. The site-wide anomaly total is
  unchanged at 7, since Fake Lake derives from the same counts and carries the
  same data-entry typos.
- Three long-standing warnings in the suite are resolved. Two came from
  metadata sheets that covered a single file, so `.check_sheet_coverage()` also
  warned about the other nineteen and that second warning leaked past
  `expect_warning()`; those sheets now cover all twenty. The third was a genuine
  coverage gap — `read_site()` emits conflict warnings for both `depth_top` and
  `depth_bottom`, but only the first was asserted.


## pcountr 0.8.0

### New — region-specific dictionaries from Neotoma

`build_dic_neotoma()` builds a draft dictionary from the Neotoma records
nearest a coordinate:

```r
build_dic_neotoma(lat = 46.45167, long = -112.16583,
                  radius_km = 250, max_sites = 20,
                  datasettype = "pollen", n = 50)
```

It returns the taxa recorded at the most distinct sites within the radius,
plus fixed entries for the spike, `Unknown` and `Indeterminable`. Entry codes
are left **blank** on purpose — codes are the analyst's muscle memory, and
nobody should inherit someone else's. The result is therefore a plain data
frame, not a `pollen_dictionary`, and will not load until the codes are filled
in; `read_dic_csv()` drops rows with a blank code. Pass `file =` to write it
as CSV, then finish it by hand and check it with `standardize_dic()`.

**Proximity rather than a political boundary.** An earlier design took a
country and a state. It was replaced because vegetation does not stop at a
state line, and the difference is measurable: a 250 km search around a site in
western Montana finds 38 sites, reaching into Idaho and Wyoming, where
`gpid = "Montana"` finds 16. A coordinate is also unambiguous, where
`gpname = Montana` resolves to both a US state and a Bulgarian province with no
warning.

**Ranked by presence, not abundance.** Taxa are ordered by the number of
distinct sites they occur in. Abundance ranking would return little beyond
*Pinus*, *Artemisia* and Poaceae, and sample-count ranking would favour a taxon
abundant at one site over one present across the region. The tally counts
distinct site-taxon pairs from `samples()`; `taxa()` is not used, because it
aggregates by units and element type and its site counts cannot be
re-aggregated to unique taxa without double-counting.

**Cost is set by you, not by the region.** Enumeration uses `all_data = TRUE`
— without it the API silently caps at 25 records, and ranking an arbitrary 25
sites by distance would be meaningless — while `max_sites` bounds the download,
which is the expensive part at roughly 92 KB per dataset. A generous
`radius_km` is nearly free: about 70 s of the query is fixed overhead, and the
50–500 km range spans only 74–210 s, so shrinking the box to save time does not
work.

**Groups are a starting value.** Neotoma's `ecologicalgroup` is imported into
the `group` column, on the same reasoning as `standardize_dic()`: a
dictionary's groups encode your pollen-sum decisions and are not the lookup's
to correct. Note this means groups arrive as `TRSH`/`UPHE`/`AQVP` rather than
single letters, and that `Cyperaceae` arrives as `UPHE` — exactly the case
where local knowledge may say otherwise.

Non-pollen palynomorphs are kept: algal colonies such as *Botryococcus* are
`NISP` and genuinely tallied, so `datasettype = "pollen"` yields a palynomorph
dictionary rather than a strictly-pollen one. Slash-combined names such as
`Larix/Pseudotsuga` are single morphotypes and are never split.

### Notes and limitations

- **Charcoal returns nothing useful.** None of Neotoma's five charcoal
  datasettypes carries a taxon vocabulary — every row is `Charcoal` or
  `Sample quantity`, with the size fraction in `elementtype`. `datasettype` is
  passed through verbatim, so a charcoal type simply yields a near-empty draft.
- **`neotoma2` is in `Suggests:`**, guarded at runtime. It imports `sf`,
  `leaflet` and `dplyr`, which is a poor trade for software that must work
  offline at a microscope. `sf` is avoided even for the geometry — the bounding
  box is a GeoJSON string built with `sprintf()`, and distances use haversine
  in base R.
- **Two cosmetic `samples()` warnings are muffled.** One is
  `"no non-missing arguments to max"`; the other has an empty message, because
  neotoma2 formats it with `sprintf()` on a value that is always `NULL`. Both
  concern age attribution only and no rows are dropped. The muffling is matched
  by exact text or emptiness, so `"No assigned samples. Did you run
  get_downloads()?"` still surfaces.
- **The network path is not tested,** by design. `R CMD check` must not depend
  on api.neotomadb.org. The tally, filtering, fixed entries, geometry and
  distance arithmetic are tested against a fixture shaped like real `samples()`
  output.
- If you pass a geometry yourself, note that neotoma2's `loc` does not accept
  an `sfc` — `parseLocation()` has no `sfc` branch and fails with
  `object 'geojson' not found` before sending anything. Use `sf::st_sf()`.

See DESIGN.md section 14 for the measured timings behind each default.


## pcountr 0.7.0

### New — Tilia / Neotoma taxon lookup integration

Two functions for reconciling a dictionary against Neotoma's taxon authority, as
distributed with Tilia.

**`read_tilia_lookup(path, type)`** parses Tilia's lookup XML into a data frame:
`taxon_id`, `name`, `author`, `code`, `taxa_group`, `ecol_group`, `higher_id`,
with Neotoma's own synonymy attached as `attr(, "synonyms")` and the
`TaxaGroup`/`EcolGroup` hierarchy as `attr(, "groups")`. Defaults to
`C:/ProgramData/Tilia/Lookup`, overridable by argument or
`options(pcountr.tilia_lookup =)`, and handles eleven proxy files. Results are
cached for the session, keyed on path and modification time, because the pollen
file is ~11 MB. A pure reader: it makes no judgements about what it finds.

**`standardize_dic(dic, lookup, aliases, apply)`** classifies every taxon name in
a dictionary and reports what it found. By default **nothing is changed.**

### Why reconcile rather than adopt the lookup wholesale

A lookup cannot serve as a counting dictionary. Its `Code` field holds Tilia's
display abbreviation (`Ane.s.`, `Pla.sp1LLC`), not the one- or two-character
keystroke code typed at the microscope. And the pollen file is the entire Neotoma
taxonomy — 49,188 taxa, of which 8,513 are diatoms and 15,257 insects. Only
22,426 are palynomorphs, and a working dictionary holds tens. The lookup is an
authority to check against; the dictionary stays the analyst's.

Matching is therefore restricted to palynomorph `TaxaGroup`s by default
(`VPL BRY UPA ALG FUN ACR DIN PLA LAB CHR`), which also removes any chance of
matching a pollen taxon against a beetle.

### The `status` classes

Assigned by cascade — exact, then alias, then Neotoma synonymy, then
orthographic, then fuzzy:

- **`exact`** — name found verbatim among accepted taxa.
- **`variant`** — differs only in orthography: diacritics, `c.f.`/`cf.`,
  `subgen.`/`subg.`. Safe to apply mechanically.
- **`synonym`** — Neotoma's own synonymy maps it to a different accepted taxon.
  Authoritative, but still a taxonomic judgement, and the revision can run
  either way: modern segregates such as *Spinulum annotinum* are *newer* than the
  lookup's *Lycopodium annotinum*.
- **`alias`** — matched your own `aliases` file. Your assertion, so applicable in
  bulk.
- **`suggestion`** — closest name by string similarity, with score.
- **`unmatched`** — nothing above `cutoff`.

**`suggestion` is never applicable as a class**, only by individual code or name,
and there is deliberately no `"all"` shorthand. Testing against a real 231-taxon
dictionary showed why. `Cerealia undiff.` scores 0.75 against *Sordaria* undiff.
— cereal grasses against a fungus — and `Primula quadriflora-type` scores 0.75
against a different species, *Primula farinosa-type*. Yet the correct
`Dendrolycopodium obscurum` → *Lycopodium obscurum* scores only 0.72, *below*
both. Any threshold admitting the good matches admits the bad ones. Scores also
tie: `Spinulum annotinum` hits 0.60 against the correct *Lycopodium annotinum*
and against a clover simultaneously, and the row displayed is decided by pool
order. The signal is not in the string.

### `apply` takes classes and individual rows together

```r
dic <- standardize_dic(dic, lookup, apply = c("variant", "synonym", "V", "ZG"))
```

Classes for what you trust wholesale, codes or names for what you have vetted
individually. Any element matching neither a class nor a row is an **error**, not
a silent no-op, and every change is echoed old → new. The call itself becomes a
record of exactly what was adopted.

### Orthographic normalisation is deliberately narrow

It folds diacritics, punctuation and abbreviation variants — nothing else. In
particular it does **not** strip `-type`, `cf.` or `aff.`, which encode how
precise a determination is: `Betula-type` is a morphotype resembling *Betula*,
not a determination of *Betula*. Stripping it would classify
`Tidestromia lanuginosa-type` as a mechanical variant of
*Tidestromia lanuginosa*, silently promoting a morphotype to a species
identification. Diacritic folding uses explicit `\u` escapes rather than
`iconv(to = "ASCII//TRANSLIT")`, whose output is platform-dependent and can emit
`?` on Windows.

### Ecological groups are not compared by default

`standardize_dic()` makes **no comparison** between your ecological groups and
the lookup's: `group_map` defaults to `NULL` and `group_differs` is `NA` unless
you supply a mapping. `ecol_group` is still reported, for reference when
preparing an upload.

This is on the reasoning that an ecological group is in practice a "sum by"
list, and that the baggage around ecological affinity makes a single standardised
list impractical to hold centrally. Cyperaceae is `UPHE` in the lookup but
legitimately aquatic in some settings, and the analyst who saw the landscape is
better placed to judge than an authority file. Flagging such a row as a
disagreement would present the lookup as correct and the analyst as deviant,
which is not a defensible default. `pcountr` already treats this as local
configuration -- `pollen_sum` is the sum-by list, set per site.

Pass e.g. `group_map = c(A = "TRSH", B = "UPHE", F = "VACR", Q = "AQVP",
X = "UNID")` if you do want the audit. Even then, nothing is changed.

### Bundled dictionary updated to Tilia 3.2 nomenclature

`inst/extdata/fake_lake/ECG.csv` -- the dictionary shipped with the example data
-- has been reconciled against the Neotoma pollen lookup with
`apply = c("variant", "synonym")`, updating 15 of its 231 names so that new users
begin with current nomenclature. Notably `Alnus rugosa` to *Alnus incana*,
`Pinus subgen. Diploxylon`/`Haploxylon` to *Pinus* subg. *Pinus*/*Strobus*,
`Polygonum amphibium` to *Persicaria amphibia*, and `Potentilla palustris-type`
to *Comarum palustre*-type. Codes, groups, aliases and `is_special` flags are
untouched, so existing counts are unaffected -- `.CNT` and YAML files reference
codes, not names.

Two consequences worth knowing. `Potamogeton subgen. Eupotamogeton` becomes
`Potamogeton`, which is Neotoma's accepted equivalent but drops a rank; revert
that row if you record the subgenus deliberately. And `Isoetes` becomes
`Isoëtes`, the first non-ASCII character in a shipped dictionary --
`read_dic_csv()` now passes `encoding = "UTF-8"` so it survives on machines whose
native encoding is not UTF-8.

### No alias table ships with the package

Cases that need one are lab conventions rather than universal facts — whether
`Monolete spore undiff.` is Neotoma's `Filicopsida (monolete) undiff.`, or how
reworked pre-Quaternary grains are recorded. A package asserting those on the
analyst's behalf would be making a scientific claim it cannot stand behind, and
imposing a North American view on users elsewhere. Instead, point `aliases` at a
path that does not exist and a template is written from the unresolved rows for
you to fill in once.

### Note on fuzzy scores

Similarity is normalised Levenshtein distance via `utils::adist`, so scores are
not comparable to those from other string-distance measures. It is stricter than
a longest-common-subsequence ratio, and usefully so: on a real 231-taxon
dictionary, five of six locally-defined reworked pre-Quaternary categories fall
below the 0.55 cutoff and report `unmatched`, which is the honest answer —
`Pre-Quaternary (Cingutriletes)` peaks at 0.50 against *Arecaceae* (trilete), a
palm. The sixth, `Pre-Quaternary undiff.`, still draws a suggestion at 0.59,
tied across four unrelated families, which is why suggestions are advisory only.

### Robustness

A synonym's accepted taxon may lie outside the filtered pool -- 439 of the 2,182
synonyms in the pollen lookup point at non-palynomorph taxa. Resolving those with
`[[` raised "subscript out of bounds"; such rows now fall through to fuzzy
matching, which is correct, since the accepted taxon is out of scope for a pollen
dictionary. Regression test added.

### New — optional confirmation tone on each count

`count_app()` gains a **Beep on count** Yes/No control beneath the Undo button.
When set to Yes, a soft tick sounds each time a grain or spike is recorded, so an
analyst can keep their eyes on the microscope and still know the entry landed.

Deliberate choices:

- **The tone is distinct from the error beep.** The existing alert is a 0.35 s
  880 Hz square wave, meant to be noticed. The confirmation is a 0.06 s 1200 Hz
  sine at roughly a third of the volume. Reusing the alert tone would have
  destroyed its purpose — the analyst could not tell a recorded grain from a
  rejected one.
- **Grains and spike only.** Traverses, remarks, and Undo are deliberate single
  actions rather than repeated tallies, so they stay silent.
- **Session-only, default No.** The setting is read straight from the control and
  is never stored on the sample or written to YAML — it is a preference, not data.
  It resets whenever the app is reopened. To have it on by default, set
  `options(pcountr.count_beep = TRUE)` in your `.Rprofile`.

The tick fires server-side once the entry is confirmed valid, so a rejected token
produces the error beep alone.

### New — `QUICKSTART.md`

A standalone guide for palynologists who have never used R: installing R and
RStudio, installing the package, counting a sample, loading finished counts,
reading the `rarefaction()` output, and producing a stratigraphic diagram. Every
code block is complete and copy-pasteable, and there is a troubleshooting section
covering the traps that actually occur — chiefly the need to restart R after
installing, and Windows path backslashes.

Linked from `README.md` and excluded from the build via `.Rbuildignore`, like
`DESIGN.md` and `ROADMAP.md`.

### Packaging

`utils` added to `Imports`.

---

## pcountr 0.6.2

### Bug fix — malformed `man/rarefaction.Rd` truncated the help page

Installing 0.6.1 emitted a run of `unexpected section header` warnings and
`unexpected END_OF_INPUT`. The package installed and worked correctly, but
everything in `?rarefaction` from `\description` onward was discarded — the
description, all four `@section` blocks, the references, and the see-also list.

The cause was in the roxygen for `@return`. A blank line followed by *indented*
prose inside a `\describe{}` item is read by roxygen's markdown parser as an
indented code block, so it emitted `\preformatted{}` and swallowed the remaining
`\item{}` entries as literal text. That left `\value{}` with an unclosed brace,
and Rd parsing consumed the rest of the file.

The `pct_smax` explanation has been moved out of `\value{}` — where a multi-
paragraph note did not belong — into the section that defines the tier targets.
`\value{}` is again a compact field list.

Note that neither `devtools::document()` nor `install_github()` fails on invalid
Rd; both only warn. `devtools::check_man()` catches it, and is now the
recommended check before release.

No change to any function, result, or test.

### Portability — non-ASCII characters removed from R code

`R CMD check --as-cran` raised a WARNING for non-ASCII characters in
`R/metadata_io.R` and `R/site_loader.R`. Three `message()` strings contained an
em-dash (`U+2014`), which is now a plain hyphen:

- `apply_metadata()`: "no source_file - updated in memory only."
- `apply_metadata()`: "source_file is not a YAML - updated in memory only."
- `write_site()`: "Skipping (exists): ... - use overwrite = TRUE to replace."

A hyphen was chosen over the `—` escape because these print to the console,
and an em-dash renders as mojibake on a Windows console not running UTF-8.

Non-ASCII characters remain in roxygen comments, which the check permits, and in
the counting app's UI strings under `inst/`, which are served as UTF-8 and are
outside the scope of this check.

`devtools::check()` now reports 0 errors, 0 warnings, 0 notes.

---

## pcountr 0.6.1

### Bug fix — `pct_smax` contradicted the tier columns

In 0.6.0, `pct_smax` was `100 * n_taxa / s_max` — an **observed** richness over a
**modelled** asymptote — while `n70`/`n80`/`n90` came purely from the fitted
model. Mixing the two made rows self-contradictory. A sample could report having
reached 90% of `Smax` on 347 grains while its own `n90` column asked for 531:

```
Sample        Grains  Taxa  Smax  %Smax    70%   80%   90%
KF24-1A130       347    11    12  90.4%    138   236   531   <- 90% at 347?
```

The cause is that the least-squares fit sits slightly *below* observed richness at
`n = N` — Michaelis–Menten approximates the whole curve rather than interpolating
its endpoint. The observed ratio is therefore systematically more optimistic than
the model, so every sample looked closer to its ceiling than the targets implied.

`pct_smax` is now the share of `Smax` the **fitted curve** reaches at the count
made:

```
pct_smax = 100 * N / (K + N)
```

which is exactly equivalent to the tiers, since `N >= K*p/(1-p)` if and only if
`N/(K+N) >= p`. A row can no longer disagree with itself, and the quantity now
matches what Lesven et al. mean by "250 grains recovers >70% of richness." The
row above becomes `%Smax = 85.5%` — past `n80`, short of `n90`.

The observed share is unchanged and still available: compare `n_taxa` against
`s_max` directly. Only the derived percentage was wrong; `s_max`, `k`, and all
tier targets are unaffected, so **counts reported by 0.6.0 remain valid** — it was
the percentage column that misrepresented them.

New regression test asserts the equivalence for every tier on every converged
sample.

---

## pcountr 0.6.0

### Breaking — `rarefaction()` rewritten; the old "optimal pollen sum" was circular

**The bug.** A rarefaction curve computed from a sample terminates, by
construction, at that sample's observed richness: drawing all `N` grains always
recovers every taxon present, so `E[S(N)] = S_obs` identically. The previous
implementation defined the "optimal pollen sum" as the count at which the curve
reached `threshold × S_obs` — a fraction of the sample's *own* observed
richness. Consequences:

- `pct_asymptote` was `curve_mean[N] / S_obs`, arithmetically pinned at
  **100.0%** for every sample, in every dataset.
- Because the curve ends at `S_obs ≥ threshold × S_obs`, a crossing point always
  existed at or before `N`. `optimal_sum ≤ n_grains` always held, so
  `meets_optimal` had **no code path to `FALSE`** — a 69-grain count passed
  exactly as readily as a 328-grain one.
- `optimal_sum` scaled with `n_grains`, because it answered "at what count had I
  found 90% of the taxa I happened to find?" It measured effort, not the
  assemblage.

**The fix.** The asymptote is now *extrapolated beyond* the observed count,
following Lesven et al. (2026). Richness is modelled as

```
R(n) = Smax * n / (K + n)
```

where `Smax` is maximum (asymptotic) richness and `K` the count recovering half
of it. Since `Smax` exceeds what was observed, a sample can genuinely fall short
and the recommended count no longer tracks the count already made. Inverting the model gives targets in closed form:

```
n_p = K * p / (1 - p)
```

so 70%, 80%, and 90% of `Smax` need `7K/3`, `4K`, and `9K` grains. This is
consistent with Table 3 of Lesven et al.: solving for `K` independently from
each of their published tier columns agrees to within 0.4 grains at all ten of
their sites. Their figures are not reproducible digit-for-digit, since each cell
is rounded independently and the tabulated `K` is itself rounded to an integer.

**No verdict is returned.** `threshold`, `threshold_taxa`, `optimal_sum`,
`meets_optimal`, and `pct_asymptote` are all removed, and the `threshold`
argument is gone. Adequacy depends on the analytical objective, which belongs to
the analyst: Lesven et al. found ~250 grains sufficient for dominant vegetation
assemblages (~70% of richness) but recommend ~1000 for biodiversity work or
detection of rare taxa (85–95%). New columns `s_max`, `k`, `pct_smax`, `n70`,
`n80`, `n90`, and `converged` report what a count recovered and what further
effort would buy.

**Site-level target.** `site_target` gives the 90th percentile of the per-sample
targets at each tier, printed as a final table row. Samples whose fit is
unusable are excluded and counted in `n_failed`.

### Deterministic targets — exact rarefaction replaces simulation

This is a deliberate departure from both source papers: Lesven et al. estimated
the curve by resampling (1000 draws per increment) and Iglesias et al. by 100
random rearrangements. `pcountr` computes it analytically from the exact
expectation given by Hurlbert (1971):

```
E[S(n)] = sum_i [ 1 - C(N - N_i, n) / C(N, n) ]
```

summed over the taxa present — implemented as the algebraically identical
`S_obs - sum_i C(N - N_i, n) / C(N, n)`, evaluated on the log scale — so
`Smax`, `K`, and every target are **deterministic and reproducible without
`set.seed()`**. Permutations (`n_sim`) are used only for the confidence band on
the returned curves and affect no reported number. This also removes the
percentile-clamping workaround the old code needed because 100 draws gave an
unstable 2.5th percentile.

The model is fitted by separable least squares: `Smax` has a closed-form
solution for any given `K`, so only `K` is optimised (via `stats::optimize()`,
over `log(K)`), reducing the fit to one well-conditioned dimension with no
starting values. `optimize()` assumes unimodality and returns a local optimum;
on the curves tested this agreed with a dense grid search, but that is not
guaranteed in general. Lesven et al. fitted the same model by
Levenberg–Marquardt; both approaches minimise the same sum of squares.

### Other changes to `rarefaction()`

- **Half-grains count as whole grains.** Each recorded grain is one detection; a
  fragment is still an observed individual. The old `ceiling(sum(weight))` per
  taxon turned three half-grains into two individuals and biased precisely the
  rare taxa that determine where the curve flattens.
- **Unusable fits return `NA`, not a fabricated number.** Counts with `N < 30`
  or fewer than 4 taxa are not extrapolated, nor are fits where `Smax` falls
  below observed richness or `K` exceeds `20N` (no saturation information).
  These print as `--` and set `converged = FALSE`. A failed fit means *unknown*,
  not *inadequate*.
- `stats` added to `Imports` and all `stats` calls qualified.

### Interpretation guidance now in the documentation

`?rarefaction` and `DESIGN.md` §12 record that `Smax` is an extrapolation, not
an observation; that Lesven et al. found *no* curve reaching a true asymptote
within 1000 grains; and that fits from ~300-grain counts sit on the steep limb
of the curve, so `Smax` is unstable and generally **underestimated** — targets
should be read as conservative lower bounds. Also noted: tier counts depend only
on `K`, so two samples can need identical counts while having different
ceilings; and richness depends on taxonomic resolution, so a lumping dictionary
yields smaller targets.

### Migration

Code reading `$summary$optimal_sum`, `$meets_optimal`, `$pct_asymptote`, or
`$threshold_taxa`, or passing `threshold =`, must be updated. The nearest
equivalents are `n70`/`n80`/`n90` for recommended counts and `pct_smax` for the
share of richness recovered. Any previously reported "optimal pollen sum" from
`pcountr` should be recomputed and should not be cited.

---

## pcountr 0.5.8

### New — `extract_remarks()`

Returns a data frame of every inline remark across all samples in a
`pollen_site`, so an analyst can find their way back to a flagged spot on a
slide. Columns: `sample_name`, `slide`, `traverse`, `id`, `remark`.

The `id` column is the taxon ID of the grain adjacent to the remark — the
taxon code concatenated with its preservation string (e.g. `"I1"`, or just
`"I"` when preservation is not recorded). `id = "before"` (default) reports the
grain counted immediately before the remark; `id = "after"` reports the one
immediately after.

Slides are tracked per sample: every sample begins on slide 1, and each
`slide_desc` event begins the next one. The `slide` column reports the
analyst's name for the active slide, or its ordinal within the sample if it was
never named. Samples in the legacy `format_version: 1` YAML have no event
stream, so their remarks report `id = NA` and a single slide; convert them with
`write_site()`.

### Bug fix — preservation code `9` rejected on entry

Entering a grain as a taxon code plus a bare modifier (e.g. `ts9` — hidden,
with no base preservation state) was rejected with "Entry not recognised". The
entry regex in `count_app()` required a base digit `1`–`8`, so `9` and `0` alone
could never match. Both the grain entry parser and the Grain History
preservation-cell editor now treat the base digit as optional, requiring only
that at least one digit be present.

### Bug fix — multi-slide `.CNT` files lost every slide boundary after the first

`read_cnt()` stripped the leading `{...}` slide descriptor into `meta$slide`,
but `.tokenise_stream()` had no branch for `{...}`, so every *subsequent*
`{SLIDE NAME}` token fell through to the anomaly path — silently discarded and
reported as unparseable. Mid-stream `{...}` tokens now produce `slide_desc`
events, and the leading descriptor is emitted as the opening event so
CNT-derived event streams match app-created ones. This also corrects the
counting app's slide counter when resuming a CNT-derived count.

Note: this adds one `slide_desc` event per slide to CNT-derived event streams.
Any test asserting an exact event count will shift, and mid-stream `{...}`
tokens that were previously counted as anomalies no longer are.

### Scope decision — the preservation scheme is analyst-defined

Both the code→label mapping and the multi-state precedence order are already
`pollen_site()` arguments (`preservation`, `precedence`), making them defaults
rather than claims about the world. Documenting them as unverified guesses was
a mistake, and two long-standing validation debts have been retired rather than
resolved:

- Documentation for preservation codes `3`, `4`, `5`, `7` — these carry no
  canonical meaning in `pcountr`; labels come from the analyst's `preservation`
  vector, so there is nothing to source.
- A `.CNT`/`.RPT` pair with combination codes (e.g. `680`) to check multi-state
  attribution against original PCount output — attribution follows the analyst's
  `precedence` order, a reversible presentation choice, not a PCount behaviour
  to reproduce.

`DESIGN.md` §6 was rewritten from "Provisional / unverified decisions" to state
the design directly. `default_precedence`'s documentation no longer describes
itself as unverified. No code changed.

Separately, the `accum_rate()` and `write_tlx()` validation items are marked
resolved — both are verified in use on real sites with analyst-supplied ages.

### Bug fix — vignette documented a `rioja::strat.plot()` argument that does not exist

The *Counting at the Microscope* vignette instructed analysts to pass
`y2var = mat$AgeTop` (and `y2label`) to `rioja::strat.plot()` to add a secondary
age axis. `strat.plot()` has no such arguments. They fell through `...` into base
graphics and were discarded, so the age axis was never drawn — silently. The only
symptom was a `'"y2var" is not a graphical parameter'` warning repeated on every
internal plotting call (128 per diagram).

`strat.plot()` takes a single y-axis variable, `yvar`. The vignette now shows
depth or age passed as `yvar`, and leaves axis styling to rioja.

The accompanying test asserted the same untruth — it was named "accepts AgeTop as
secondary y axis" and passed because `expect_no_error()` cannot see a warning. It
now verifies that AgeTop works as *the* y-axis variable, and both `strat.plot()`
smoke tests use `expect_no_warning()` so an unrecognised argument fails loudly
instead of passing quietly.

### `pres` is now a concatenated digit string

The per-grain `pres` field changed from a semicolon-separated set (`"1;9"`) to a
plain concatenated digit string (`"19"`). Each preservation state is a single
digit, so the separator carried no information and the two formats were used
inconsistently across the codebase — the Grain History editor validated against
the concatenated form while the parsers wrote the separated form, which is what
surfaced the `9` bug above. `read_pollen_count()` strips semicolons on read, so
existing YAMLs written in the old format load correctly.

Callers that split `pres` on `";"` were updated:
- `preservation_table(collapse_multistate = TRUE)` — had silently stopped
  collapsing multi-state grains, since splitting `"19"` on `";"` yields the
  whole string rather than its digits.
- The counting app's Grain History preservation column — now also displays
  modifier-only grains (previously shown as `—`).

---

## pcountr 0.5.7

### Bug fix — CNT → YAML round-trip lost `hidden` flag and `pres` for modifier grains

`.tokenise_stream()` in `read_cnt.R` was building grain events with a `pres_set`
field (a character vector) instead of the `base`, `pres`, and `hidden` fields
expected by `write_pollen_count()`. As a result, any grain parsed from a `.CNT`
file with a `9` (hidden) or `0` (half-grain) modifier would be written to YAML
with `hidden: false` and `pres: null`, silently dropping those flags on
round-trip. Grains entered live in the counting app were unaffected.

Specifically:
- `B19` (hidden Betula): round-tripped as `hidden=FALSE`, `pres=""`.
- `I80` (half Picea): `weight=0.5` was preserved (correct) but `pres` became
  empty.
- `A190` (hidden + half): both `hidden` and `pres` were dropped.

The fix aligns the CNT event structure with the app's event format:
`base`, `pres` (semicolon-separated string), `hidden`, and `anomaly` are now
set correctly for every grain event produced by `.tokenise_stream()`.

New test file `tests/testthat/test-modifier-roundtrip.R` adds 7 assertions
covering token parsing, event field correctness, and full CNT → YAML
round-trips for `9`, `0`, and `90` modifier combinations.

---

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
- Depth sheet for the 20-sample local validation site (unpublished data; held
  locally and not distributed with the package).

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

- Reproduces an original PCount `.RPT` report exactly (all sums, spike, ratio,
  concentration, traverse stats).
- Parses all 20 samples of the local validation site; surfaces every known
  data-entry anomaly.
- 87 test assertions passing.
