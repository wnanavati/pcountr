# pcountr

Read, convert, and analyse pollen counts from the legacy MS-DOS **PCount**
program — and store them in a modern, self-contained format.

## What it does (v0.5.1)

### Reading legacy PCount files
- **`read_dic()`** — parse a PCount `.DIC` dictionary (taxon code → name + group
  A/B/F/Q/X, plus non-pollen markers); also reads the modern CSV dictionary format.
- **`read_cnt()`** — parse a legacy `.CNT` count file into a per-grain
  `pollen_count` object, preserving counting order, traverse labels, tracer-spike
  marks, and inline `[...]` remarks. Data-entry anomalies are imported permissively
  and reported.

### Calculations
- **`count_metrics()`** — reproduce PCount's report numbers: per-group pollen sums,
  basic/total sums, spike count, sum/spike ratio, grain concentration
  (grains/cm³ or grains/g), and traverse statistics.
- **`preservation_table()`** — taxon × preservation-class tabulation, with a
  configurable precedence rule for multi-state grains.
- **`accum_rate()`** — pollen accumulation rates (PAR) for a full site, with
  per-taxon influx matrices.

### Native YAML format
- **`write_pollen_count()` / `read_pollen_count()`** — one self-contained YAML
  file per sample carrying grains, metadata, and analyst-supplied depth and age.

### Site-level analysis
- **`read_site()`** — load a folder of `.CNT` and/or `.yaml` files as a
  `pollen_site`, with optional depth/age metadata sheet (CSV/TSV).
- **`set_metadata()`** — update depth, age, sample identity, quantity, and spike
  fields on a sample; re-sorts the site. (`set_depth_age()` is a deprecated alias.)
- **`site_matrix()`** — wide samples × taxa matrix (percentages, concentrations,
  accumulation rates) for plotting and export. (`as_rioja()` is a deprecated alias.)
- **`write_tlx()`** — export a `pollen_site` to Tilia XML format (`.tlx`) for
  Neotoma upload, with Data, Percents, Concentrations, and Accumulation sheets,
  including full sample metadata rows matching Tilia's native format.

### Interactive counting app
- **`count_app()`** — a Shiny-based replacement for the DOS counting loop.
  Keystroke-driven grain entry, live running totals (Σ, ΣP, traverses, spike),
  running concentration and PAR, YAML autosave after every entry, mid-count
  metadata and dictionary editing, and resume from YAML.

## Quick start — stratigraphic plot from a folder of YAML counts

```r
library(pcountr)
library(rioja)

site <- read_site("path/to/your/folder")
mat  <- site_matrix(site)
rioja::strat.plot(mat$TaxaPerc, mat$DepTop, y.rev = TRUE)
```

`y.rev = TRUE` puts depth 0 at the top, which is standard for stratigraphic diagrams.
Pass `min_present = 3` to `site_matrix()` to hide rare taxa.

## Verified against real data

Reproduces `LM23SH00.RPT` **to the digit** and parses all 20 samples of the
Little Mosquito Lake site. 432 test assertions pass. See `tests/testthat/`.

## Design boundaries

- Preservation code `0` is a **half-grain modifier** (weight 0.5), not a state.
  Codes `1` perfect, `2` corroded, `6` crumpled, `8` broken, `9` hidden are
  known; `3/4/5/7` are placeholders pending documentation.
- Chronology construction is **out of scope** — `pcountr` performs
  accumulation-rate arithmetic from ages you supply, but age–depth modelling is
  delegated to tools such as `rbacon`, `clam`, or `neotoma2`.

## Project documentation

- **`DESIGN.md`** — the decisions log: why everything is built the way it is.
  Read this first if you're continuing the project.
- **`ROADMAP.md`** — what's done and what's next.
- **`NEWS.md`** — changelog.

## Acknowledgements

`pcountr` is dedicated to the memory of **Dr. Eric C. Grimm (1951–2020)**,
who developed PCount at the Illinois State Museum and distributed it freely to
the palynological community. This package exists because of his generosity as a
mentor and his commitment to open science.

The Little Mosquito Lake example data (`inst/extdata/`) were collected as part
of ongoing palynological research at the University of Montana.

This package was developed with the assistance of **Claude AI** (claude-sonnet-4-6,
Anthropic, 2025–2026). All analytical logic, test assertions, and scientific
decisions were authored and verified by W. Nanavati.
