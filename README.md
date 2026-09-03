# pcountr

<!-- badges: start -->
[![R-CMD-check](https://github.com/wnanavati/pcountr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/wnanavati/pcountr/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

An interactive counter and analysis toolkit for stratigraphic assemblages counted
by traversing a slide — pollen, diatoms, charcoal morphotypes, phytoliths, or any
proxy tallied the same way. Built around a keystroke-driven Shiny app that
mirrors the PCount DOS workflow while saving to a modern, self-contained format.

## What it does (v0.8.0)

### Interactive counting app
- **`count_app()`** — launch the Shiny counting app in your browser. Type entry
  tokens (`B1`, `I80`, `A1`) and press Enter. Choose concentration method (spike /
  volumetric / none) and whether to record preservation codes — the app adapts
  accordingly. Live running totals (Σ, ΣP, traverses, spike), running concentration
  and accumulation rates, continuous YAML autosave, mid-count metadata and
  dictionary editing, and resume from any saved count.

### Site-level analysis
- **`read_site()`** — load a folder of `.yaml` and/or legacy `.CNT` files as a
  `pollen_site`, with optional depth/age metadata sheet (CSV/TSV).
- **`write_site()`** — export every sample to a YAML file; the primary route
  for migrating a legacy `.CNT` folder to the modern YAML format. Returns the
  updated site with `source_file` stamped, ready for `apply_metadata()`.
- **`set_metadata()`** — update depth, age, sample identity, quantity, and spike
  fields on a sample; re-sorts the site.
- **`extract_metadata()`** — extract a metadata data frame from a `pollen_site` or
  folder path; the reverse of `set_metadata()`. Optional `file =` writes CSV.
- **`apply_metadata()`** — apply an edited metadata CSV back to a site and write
  the updates to the source YAML files; completes the `extract_metadata()` →
  edit → `apply_metadata()` round-trip.
- **`extract_remarks()`** — table of every inline remark across a site, with the
  sample, slide, traverse, and the taxon ID counted next to it, so you can find
  your way back to a flagged spot on a slide.
- **`site_matrix()`** — wide samples × taxa matrix (percentages, concentrations,
  accumulation rates) for plotting and export.
- **`write_tlx()`** — export a `pollen_site` to Tilia XML format (`.tlx`) for
  Neotoma upload, with Data, Percents, Concentrations, and Accumulation sheets,
  including full sample metadata rows matching Tilia's native format.

### Calculations
- **`count_metrics()`** — per-group assemblage sums, basic/total sums, spike
  count, sum/spike ratio, concentration (counts/cm³ or counts/g), and
  traverse statistics.
- **`preservation_table()`** — taxon × preservation-class tabulation, with a
  configurable precedence rule for multi-state identifications.
- **`accum_rate()`** — accumulation rates for a full site, with per-taxon influx
  matrices.
- **`rarefaction()`** — how many to count. Extrapolates each sample's
  richness asymptote (`Smax`) with a Michaelis–Menten model and reports the
  counts needed for 70%, 80%, and 90% of it, plus a site-level target. Reports
  rather than judges: adequacy depends on your objective, and the output shows
  what a count recovered alongside what more effort would buy.

### Dictionaries — build one from nearby records

- **`build_dic_neotoma()`** — draft a dictionary from the Neotoma records
  nearest a coordinate, ranked by how many distinct sites each taxon occurs in.
  Proximity rather than state lines: a 250 km search in western Montana reaches
  into Idaho and Wyoming and finds more relevant analogues than the state does.
  Entry codes are left blank for you to fill in, and groups arrive from
  Neotoma's ecological groups as a starting value. Requires `neotoma2`.

### Taxonomy — Tilia / Neotoma reconciliation

- **`neotoma_taxonomy()`** — fetch Neotoma's taxon list and synonymy from the
  API, covering every proxy in one table (filter with `taxa_group`, e.g.
  `"VPL"`, `"DIA"`). Cached locally after the first call. Use this instead of
  the Tilia lookups on macOS and Linux, since Tilia is Windows-only.

- **`read_tilia_lookup()`** — read Tilia's Neotoma taxon lookup (`.xml`, normally
  in `C:/ProgramData/Tilia/Lookup`) into a data frame, with Neotoma's own synonymy
  and the `TaxaGroup`/`EcolGroup` hierarchy attached.
- **`standardize_dic()`** — check your dictionary against that authority and
  report what it finds: exact matches, orthographic variants, deprecated names
  with their accepted replacements, and where your groups disagree with Neotoma's
  ecological groups. Nothing is changed unless you ask; names are adopted
  selectively with `apply =`, by class or by individual code. Smooths Neotoma
  submission via `write_tlx()`.

### Native YAML format
- **`write_pollen_count()` / `read_pollen_count()`** — one self-contained YAML
  file per sample carrying identifications, metadata, and analyst-supplied depth
  and age.

### Reading legacy PCount files
- **`read_dic()`** — parse a PCount `.DIC` dictionary (taxon code → name + group
  A/B/F/Q/X, plus markers excluded from sums); also reads the modern CSV dictionary format.
- **`read_cnt()`** — parse a legacy `.CNT` count file into a per-grain
  `pollen_count` object, preserving counting order, traverse labels, tracer-spike
  marks, and inline `[...]` remarks.

## New to R?

**Start with [QUICKSTART.md](QUICKSTART.md)** — a step-by-step guide that assumes
no programming experience. It covers installing R, counting a sample in the app,
checking whether you counted enough, and producing a stratigraphic
diagram.

## Quick start — count, plot, export

```r
# Install from GitHub
remotes::install_github("wnanavati/pcountr")

library(pcountr)

# 1. Count at the microscope (saves YAML automatically)
count_app()

# 2. Load completed counts (dic = required — defines sum groups for analysis)
site <- read_site("path/to/your/yaml/folder",
                  dic = "path/to/your/dictionary.csv")

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

- Preservation code `0` is a **half-weight modifier** (weight 0.5), not a state.
  The base digit is optional at entry, so a modifier alone (e.g. `ts9`) is a
  valid entry.
- The **preservation scheme is yours to define.** `pollen_site()` takes both the
  code→label mapping (`preservation`) and the multi-state precedence order
  (`precedence`). The built-in defaults are `1` well-preserved, `2` corroded,
  `6` crumpled, `8` broken, `9` hidden, after Cushing (1967) — but any project
  can substitute its own damage-state taxonomy and every downstream function
  follows.
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
decisions were authored and verified by W. Nanavati
([ORCID 0000-0003-4853-5429](https://orcid.org/0000-0003-4853-5429)).
