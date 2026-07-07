# pcountr

An interactive counter and analysis toolkit for pollen counting that can be used for diatoms, charcoal morphotypes, or any stratigraphic assemblage counted by traversing a
slide. Built around a keystroke-driven Shiny app that mirrors the PCount DOS
workflow while saving to a modern, self-contained format.

## What it does (v0.5.1)

### Interactive counting app
- **`count_app()`** — launch the Shiny counting app in your browser. Type grain
  tokens (`B1`, `I80`, `A1`) and press Enter. Live running totals (Σ, ΣP,
  traverses, spike), running concentration and accumulation rates, YAML autosave after every
  entry, mid-count metadata and dictionary editing, and resume from any saved
  count.

### Site-level analysis
- **`read_site()`** — load a folder of `.yaml` and/or legacy `.CNT` files as a
  `pollen_site`, with optional depth/age metadata sheet (CSV/TSV).
- **`set_metadata()`** — update depth, age, sample identity, quantity, and spike
  fields on a sample; re-sorts the site.
- **`site_matrix()`** — wide samples × taxa matrix (percentages, concentrations,
  accumulation rates) for plotting and export.
- **`write_tlx()`** — export a `pollen_site` to Tilia XML format (`.tlx`) for
  Neotoma upload, with Data, Percents, Concentrations, and Accumulation sheets,
  including full sample metadata rows matching Tilia's native format.

### Calculations
- **`count_metrics()`** — per-group assemblage sums, basic/total sums, spike
  count, sum/spike ratio, grain concentration (grains/cm³ or grains/g), and
  traverse statistics.
- **`preservation_table()`** — taxon × preservation-class tabulation, with a
  configurable precedence rule for multi-state grains.
- **`accum_rate()`** — accumulation rates for a full site, with per-taxon influx
  matrices.

### Native YAML format
- **`write_pollen_count()` / `read_pollen_count()`** — one self-contained YAML
  file per sample carrying grains, metadata, and analyst-supplied depth and age.

### Reading legacy PCount files
- **`read_dic()`** — parse a PCount `.DIC` dictionary (taxon code → name + group
  A/B/F/Q/X, plus non-pollen markers); also reads the modern CSV dictionary format.
- **`read_cnt()`** — parse a legacy `.CNT` count file into a per-grain
  `pollen_count` object, preserving counting order, traverse labels, tracer-spike
  marks, and inline `[...]` remarks.

## Quick start — count, plot, export

```r
# install.packages("remotes")  # if you don't have it
remotes::install_github("wnanavati/pcountr")

library(pcountr)

# 1. Count at the microscope (saves YAML automatically)
count_app()

# 2. Load completed counts
site <- read_site("path/to/your/yaml/folder")

# 3. Stratigraphic diagram
library(rioja)
mat <- site_matrix(site, min_present = 2)
rioja::strat.plot(mat$TaxaPerc, yvar = mat$DepTop, y.rev = TRUE,
                  scale.percent = TRUE)

# 4. Export to Tilia
write_tlx(site, file = "my_site.tlx")
```

`y.rev = TRUE` puts depth 0 at the top, which is standard for stratigraphic diagrams.

## Not just pollen

pcountr works for any assemblage counted by traversing a slide. The dictionary
format, token syntax, and YAML output are not pollen-specific — diatom, charcoal
morphotype, or phytolith counts follow the same workflow unchanged.

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

This package was developed with the assistance of **Claude AI** (claude-sonnet-4-6,
Anthropic, 2025–2026). All analytical logic, test assertions, and scientific
decisions were authored a