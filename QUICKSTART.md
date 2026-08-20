# pcountr — Quick Start

A guide for palynologists who have never used R.

You will install two free programs, paste in three lines of text, and then count
pollen. Everything after that is copy-and-paste. No programming required.

**Contents**

1. [One-time setup](#1-one-time-setup-about-15-minutes)
2. [Count a sample](#2-count-a-sample)
3. [Load your finished counts](#3-load-your-finished-counts)
4. [Did I count enough grains?](#4-did-i-count-enough-grains)
5. [Make a stratigraphic diagram](#5-make-a-stratigraphic-diagram)
6. [If something goes wrong](#6-if-something-goes-wrong)

---

## 1. One-time setup (about 15 minutes)

You only ever do this once.

### Install R

R is the engine. Go to <https://cran.r-project.org>, download the version for
your computer, and install it with all the default options.

### Install RStudio

RStudio is the window you actually work in. Go to
<https://posit.co/download/rstudio-desktop/>, download RStudio Desktop (it is
free), and install it with the default options.

### Open RStudio and install pcountr

Open RStudio. On the left you will see a panel with a `>` symbol. That is the
**Console** — it is where you paste things.

Click next to the `>`, paste the two lines below, and press Enter.

```r
install.packages("remotes")
remotes::install_github("wnanavati/pcountr")
```

Text will scroll past for a minute or two. When it stops and you see `>` again,
it worked.

> **Now restart R.** In RStudio's menu: **Session → Restart R**. This matters —
> if you skip it, the next step may fail with a confusing error.

### Check that it worked

Paste this and press Enter:

```r
library(pcountr)
```

If nothing happens except a new `>`, you are ready. (No news is good news in R.)

---

## 2. Count a sample

Paste these two lines:

```r
library(pcountr)
count_app()
```

A counting window opens in your web browser. R must stay open while you count —
minimise RStudio, don't close it.

### The setup screen

Fill in what you know and leave the rest. The fields, in the order they appear:

| Field | What to put |
|---|---|
| **Open Existing Count (.yaml)** | Only if you are picking up a count you started earlier. The dictionary loads automatically from the saved file |
| **Dictionary file (.DIC or .csv)** | Browse to your taxon dictionary |
| **ΣP — analyst defined pollen sum groups** | Tick the groups that make up your pollen sum. The choices come from your dictionary, so this stays empty until one is loaded |
| **Calculate concentration?** | **Yes, using spikes** if you added exotic marker tablets, **Yes, volumetrically** if you processed a known volume, **No** if you don't need concentrations |
| **Sample quantity** | Update for your sample |
| **Sample units** | Update for your sample — `ml` or `g` |
| **Spike quantity** | Update for your sample. Only shown if you chose spikes |
| **Spike density** | Update for your sample. Only shown if you chose spikes |
| **Spike units** | Update for your sample — `ml`, `g` or `tablets`. Only shown if you chose spikes |
| **Use preservation codes?** | **Yes** if you record grain condition, **No** if you only tally taxa |
| **Sample name** | Your label for the sample, e.g. `FL24#001` |
| **Depth top / bottom (cm)** | Depth of the sample in cm. Leave blank if unknown |
| **Age top / bottom (years BP)** | Leave blank unless you already have an age model. Present = 1950 CE |
| **First slide ID** | Your name for the first slide, e.g. `FL001-1`. New counts only |
| **Sample title** | Anything that identifies the sample, e.g. `Fake Lake FL001 13MAY24` |
| **Save YAML to** | Where to save. Type a path or use **Browse**. Pick a folder you'll remember |

Sample name, depths and ages are all optional — the heading above them says so.

Then click **▶ Start Counting**.

### Counting

Click into the input box and type. You need four things:

| You type | What happens |
|---|---|
| `B1` | One *Betula* grain, preservation 1. Your dictionary defines the letters |
| `.` | One spike marker. Just press the full stop — no Enter needed |
| `/23n/` | Marks a new traverse. Put anything between the slashes — a stage coordinate, a note to yourself |
| `[looks corroded]` | Records a remark at this exact point in the count |

Press **Enter** or **Space** to submit. The running totals update on the right.

Useful buttons, down the right-hand side:

- **Undo** — removes the last thing you entered
- **Beep on count** — set to **Yes** for a soft tick each time a grain or spike
  is recorded, so you can keep your eyes on the microscope. Off by default, and
  it resets each time you open the app
- **New Slide** — click when you move to a new slide, so remarks can be traced
  back to the right one
- **Done / Save** — when you're finished

Your work is saved continuously, so a crash costs you nothing. Preservation
codes, if you use them: `1` well-preserved, `2` corroded, `6` crumpled,
`8` broken, `9` hidden, `0` half-grain. Add `0` or `9` after the digit, e.g.
`B10` is a half *Betula* grain.

If you type something the app doesn't recognise you get a large red box and a
beep. The grain is **not** recorded — correct it and type again.

### Counting the next sample

Click **New Sample**. Your dictionary and spike settings carry over; you only
change the depth and title.

---

## 3. Load your finished counts

Once you have several samples saved, load them all at once.

You need two paths: the folder holding your saved counts, and your dictionary
file. To get a path on Windows, hold **Shift**, right-click the file or folder,
and choose **Copy as path**. Then paste it between the quotes below.

**Important:** change every backslash `\` to a forward slash `/`, and delete the
quotes Windows adds.

```r
library(pcountr)

site <- read_site("C:/Users/you/Documents/my_counts",
                  dic = "C:/Users/you/Documents/my_dictionary.csv")

site
```

That last line prints a summary: how many samples, and their depth range. If the
numbers look right, everything loaded.

---

## 4. Did I count enough grains?

```r
rarefaction(site)
```

You get a table like this:

```
Sample       Depth Grains Taxa Smax  %Smax      70%    80%    90%
FL004         15.0    375   13   14  88.6%      113    193    433
```

Reading it:

- **Grains / Taxa** — what you counted, and how many taxa you found
- **Smax** — the estimated *total* number of taxa in the sample, including ones
  you have not yet seen. This is a model estimate, not an observation
- **%Smax** — the share of that total your count has reached
- **70% / 80% / 90%** — how many grains you would need to reach those shares

That is one row from the middle of the output; you get one row per sample, and a
final `Site (q90)` row giving a single target for the whole site.

**How many should you aim for?** It depends on your question. Around 250–300
grains is enough to characterise the dominant vegetation. If you care about rare
taxa, published work suggests 1000. The table tells you the cost
of each choice for *your* material; it does not tell you which to pick.

Two cautions. `Smax` is extrapolated, so treat it as a rough lower bound —
especially from counts of a few hundred grains. And a sample dominated by one
taxon needs a larger count than an even one, because most of your effort goes on
the dominant.

---

## 5. Make a stratigraphic diagram

This uses a second free package called `rioja`. Install it once:

```r
install.packages("rioja")
```

Then:

```r
library(rioja)

mat <- site_matrix(site, min_present = 3)

rioja::strat.plot(mat$TaxaPerc,
                  yvar          = mat$DepTop,
                  y.rev         = TRUE,
                  scale.percent = TRUE,
                  ylabel        = "Depth (cm)")
```

`min_present = 3` hides taxa found in fewer than three samples, which keeps the
diagram readable. `y.rev = TRUE` puts the surface at the top.

To plot against age instead of depth, swap `mat$DepTop` for `mat$AgeTop` and
change `ylabel`.

### Export to Tilia

```r
write_tlx(site, file = "C:/Users/you/Documents/my_site.tlx")
```

Opens in Tilia, for onward submission to Neotoma.

---

## 6. If something goes wrong

**"there is no package called 'pcountr'"** — the install didn't finish, or you
didn't restart R. Run **Session → Restart R**, then `library(pcountr)`.

**"'x' is not an exported object from 'namespace:pcountr'"** — you updated
pcountr while R was already running. Restart R. This one catches everyone.

**"cannot open file" or "No such file or directory"** — a path problem. Check
that backslashes became forward slashes, and that no stray quotes remain.

**The counting window is blank or won't open** — R must be running. Check
RStudio hasn't been closed, and look for a "Stop" symbol in the Console meaning
the app is still live.

**The red "Entry not recognised" box** — the taxon code isn't in your dictionary,
or the token is malformed. Either retype it, or click **Edit Dictionary** to add
the taxon.

**Everything else** — open an issue at
<https://github.com/wnanavati/pcountr/issues> and say what you typed and what
happened.

---

## Where to go next

`README.md` lists everything the package can do. Inside R, put `?` before any
function name for its full documentation:

```r
?rarefaction
?read_site
```

And for a longer worked example:

```r
vignette("counting", package = "pcountr")
```
