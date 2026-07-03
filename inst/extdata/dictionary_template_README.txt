pcountr dictionary CSV format
==============================

This file documents the CSV dictionary format used by pcountr.
The companion file dictionary_template.csv is a working example you can
copy and customise for your site.

To use in R:
  dic <- pcountr::read_dic("my_dictionary.csv")

To migrate an existing PCount .DIC file to CSV:
  pcountr::write_dic_csv(pcountr::read_dic("ECG.DIC"), "ECG.csv")


COLUMNS
-------

code  (required)
  The 1–2 character taxon code typed at the microscope.
  - Regular pollen/spore taxa: 1–2 letters, e.g. "A", "SF", "PT"
  - Non-pollen palynomorphs: prefix with "#", e.g. "#FUN", "#ALG"
  - Tracer spike: use "." (a single period)
  Codes are matched case-insensitively during counting.

name  (required)
  Full taxon name, e.g. "Alnus", "Sphagnum", "Fungal spore".

group  (required)
  Single letter identifying which pollen-sum group the taxon belongs to.
  Leave blank for non-pollen markers and the spike.
  Common conventions (customise freely for your project):
    A  – arboreal pollen (trees)
    B  – non-arboreal pollen (shrubs, herbs)
    F  – ferns and spores
    Q  – aquatic pollen
    X  – excluded / unidentifiable types

alias  (optional)
  Short alternative label or abbreviation, e.g. "Fun", "Alg".
  Used as column headers in plots when "alias" taxon labelling is selected.
  Leave blank to fall back to the code.

is_special  (optional)
  TRUE or FALSE.
  Marks taxa that should be excluded from all pollen sums (non-pollen
  markers, the tracer spike).  If this column is absent, pcountr infers
  it automatically: any code beginning with "#" or "." is special, as is
  any row whose group column is blank.


NOTES
-----

- Column names are matched case-insensitively (Code, CODE, code all work).
- Row order does not matter; pcountr sorts internally when needed.
- Blank rows are ignored.
- Additional columns beyond those listed above are ignored.
- Ages in pcountr are stored as years BP (before present),
  where "present" = 1950 CE.
- Save the file as UTF-8 CSV for best compatibility.
