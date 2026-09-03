# Contributing to pcountr

Contributions are welcome — bug reports, feature requests, documentation fixes
and pull requests alike. This file explains how the repository is laid out and
the few rules that matter.

If you are a working analyst rather than a developer, a bug report is worth as
much as a patch. Say what you typed, what you expected, and what happened.

---

## Reporting a bug

Open an issue at <https://github.com/wnanavati/pcountr/issues> and include:

- what you were doing (counting, loading a site, exporting)
- the exact command or keystroke, and the exact error text
- the output of `sessionInfo()`
- if it involves a file, the *format* and roughly how large — please do **not**
  attach unpublished site data

A minimal reproducible example using the bundled **Fake Lake** dataset
(`system.file("extdata", "fake_lake", package = "pcountr")`) is the fastest
route to a fix, because it lets the problem be reproduced without your data.

---

## Never commit unpublished site data

This is the one rule with no exceptions. The repository deliberately ships a
small amount of real data to back the validation tests, and nothing more:

| Tracked, published deliberately | Why |
|---|---|
| `inst/extdata/LMSH001.CNT` | One Little Mosquito Lake sample (`LM23sh#001`) |
| `inst/extdata/LM23SH00.RPT` | Its matching PCount report, for the golden test |
| `inst/extdata/fake_lake/` | Twenty simulated samples — safe for any use |

Everything else from that site is **unpublished** and is excluded in
`.gitignore`:

```
/inst/extdata/LMSH*.CNT
!/inst/extdata/LMSH001.CNT
/inst/extdata/LM_depths.txt
/inst/extdata/ECG.DIC
```

Do not remove or weaken those lines, and do not add real site data of your own.
Write tests against Fake Lake instead. If a test genuinely needs a real file,
open an issue first so the licensing and consent can be sorted out before
anything lands in git history — once committed, it is effectively permanent.

---

## Branches

- **`main`** — release branch. Tagged, citable, carries the Zenodo DOI. Do not
  push work in progress here.
- **`dev`** — where development happens. Branch from `dev`, open the pull
  request against `dev`.

---

## Setting up

```r
install.packages("devtools")
devtools::install_deps(dependencies = TRUE)
```

The counting app needs `shiny`, `DT` and `shinyFiles`; Tilia XML work needs
`xml2`; the Neotoma helpers need `neotoma2` and `jsonlite`; the test suite uses
`withr`. All are in `Suggests`, so `dependencies = TRUE` is what you want.

---

## Before opening a pull request

Run all three, and say in the PR that you did:

```r
devtools::document()   # regenerate man/ if you touched any roxygen
devtools::test()
devtools::check()
```

`check()` should be clean — **0 errors, 0 warnings, 0 notes**. That standard is
maintained deliberately; a new note is a regression, not a detail.

`NAMESPACE` is **hand-maintained**, not generated. If you export something new,
add the `export()` line yourself. `devtools::document()` will not do it for you,
and forgetting has caused a real bug before.

---

## Conventions worth knowing

- **Tests are the specification.** Every behavioural change needs a test that
  fails before it and passes after. Assertions currently number in the
  hundreds; please add rather than reshape existing ones.
- **Historical names stay.** The `pollen_site` / `pollen_count` /
  `pollen_dictionary` classes, the `grains` key in the YAML format, and
  arguments like `pollen_sum` predate the package's move to proxy-neutral
  language. Renaming them would break saved counts and callers' code, so they
  are documented as historical rather than descriptive. New code should not
  extend the pollen-specific vocabulary.
- **Legacy formats stay pollen-framed.** `.CNT`, `.DIC`, `.RPT` and the Tilia
  lookup came out of pollen-only tools; their documentation says so on purpose.
  The `.CNT` header literal `POLLEN SUM =` must not change — PCount could not
  read the result.
- **No fabricated numbers in documentation.** Every figure in the docs should be
  reproducible from shipped data or a cited source. If you add an example
  output, generate it and paste the real result.
- **Chronology is out of scope.** pcountr does arithmetic on analyst-supplied
  ages and does not build age–depth models. Age modelling belongs to `rbacon`,
  `clam` and `neotoma2`.
- **Style** — base R, 2-space indent, roughly 80 columns, `<-` for assignment.
  No new hard dependencies without discussion; `Imports` is deliberately small.

---

## Licence

pcountr is MIT licensed. By contributing you agree your contribution may be
distributed under those terms.
