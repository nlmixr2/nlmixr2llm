# NONMEM reference — running via babelmixr2 and importing via nonmem2rx

## Running an nlmixr2 model in NONMEM (babelmixr2)

```r
library(babelmixr2)
options("babelmixr2.nonmem" = "nmfe743")     # executable name or full path

fit <- nlmixr(model_fn, data, est = "nonmem",
              nonmemControl(modelName = "run001"))
```

`nonmemControl()` arguments that matter most:

| Argument | Role |
|---|---|
| `modelName` | Output directory name. **Always set it**; unset or reused names collide. |
| `runCommand` | NONMEM executable string, or a function `FUN(ctl, directory, ui)` for cluster submission (must return after outputs exist); `NA` writes the files without running. Defaults to `getOption("babelmixr2.nonmem")`. |
| `readRounding` | `FALSE` by default. Set `TRUE` to read partial results after a rounding-error termination. |
| `est`, `maxeval`, `sigdig`, `sigl` | Mirror NONMEM `$EST` settings (`est` is `"focei"`, `"imp"`, `"its"`, or `"posthoc"`). |
| `advanOde`, `tol`, `atol` | ODE solver ADVAN for the generated `$SUBROUTINES` (`"advan13"`, `"advan8"`, `"advan6"`) and its tolerances. |
| `muRef` | babelmixr2 generates MU-referenced code by default; keep it unless comparing to a hand-written ctl. |
| `cov` | Covariance step setting written to `$COV`. |

What babelmixr2 writes into the `modelName` directory: control stream, NONMEM-format dataset, and after the run the listing / `.xml` / `.phi` / table files. It reads those outputs and combines them with the original nlmixr2 model into a fit object; it does not re-translate the control stream.

## Importing a finished NONMEM run (nonmem2rx)

```r
library(nonmem2rx)

# Bundled example — pass the listing file; the ctl is found alongside it
resFile <- system.file("mods/cpt/runODE032.res", package = "nonmem2rx")
mod <- nonmem2rx(resFile, validate = TRUE, save = FALSE)

# A user's run — pass the control stream and point at a non-default listing extension
mod <- nonmem2rx("path/to/run123.ctl", lst = ".lst", validate = TRUE)

cat(deparse(as.function(mod)), sep = "\n")   # generated rxode2 model body

fit <- babelmixr2::as.nlmixr2(mod)            # promote the qualified import to an nlmixr2 fit
```

Arguments:

- First argument: control stream (`.ctl` / `.mod`) **or** listing (`.lst` / `.res`); the rest is discovered beside it.
- `lst`, `xml`, `phi`, `ext`, `cov`: extension or path overrides when the run uses non-default names.
- `validate = TRUE` (the default): run the rxode2-vs-NONMEM comparison and populate `$ipredCompare` / `$predCompare`. Leave it on.
- `save`: `NA` by default, which saves the parsed object automatically when translation plus validation takes longer than `saveTime` (15 s); `TRUE` always saves, `FALSE` never. It is written as an `.rds` beside the source (`saveRDS()`), and `load = TRUE` (the default) reuses it on the next call.
- `inputData`: explicit dataset path when `$DATA` cannot be resolved relative to the ctl directory.
- `thetaNames`, `etaNames`, `cmtNames`, `rename`: rename THETA/ETA/compartments to readable names during translation.

### Required files on disk

| File | Role |
|---|---|
| `run.ctl` / `run.mod` | control stream |
| `run.lst` / `run.res` | listing (final estimates, termination status) |
| `run.xml` | structured output (THETA/OMEGA/SIGMA, SEs) |
| `run.phi` | per-ID ETAs (FOCE / FOCEI runs) |
| `run.ext`, `run.cov` | iteration history, covariance (optional but used when present) |
| `$TABLE` output files | as named in the control stream; joined into `$nonmemData` and used for PRED / IPRED comparison |
| dataset CSV | as referenced in `$DATA` (relative to the ctl directory) |

Missing pieces yield a partially populated object, not an error. Flag them.

### What you get back

An **rxode2 UI object** (not an nlmixr2 fit). Useful slots:

| Slot | Contents |
|---|---|
| `$nonmemData` | NONMEM table output joined to the dataset |
| `$etaData` | per-ID empirical Bayes ETAs |
| `$ini` | tidy parameter table (THETA + variability) |
| `$props$pop` | names of population (THETA) parameters |
| `$thetaMat` | NONMEM's full `$COV` matrix (thetas, sigma, omega). With `dfSub`/`dfObs` in the model metadata, `rxSolve(mod, ev, nStud = 100)` uses it automatically |
| `$predData`, `$ipredData` | NONMEM PRED / IPRED |
| `$predCompare`, `$ipredCompare`, `$iwresCompare` | rxode2 vs NONMEM differences (qualification) |

### Qualification

```r
plot(mod)                          # built-in qualification plot (prints; returns NULL)
plot(mod, page = 1, log = "y")     # log-scale page
p <- autoplot(mod)                 # ggplot object, e.g. for ggsave()
summary(mod$ipredCompare)          # differences should be ~0 to working precision
summary(mod$predCompare)
```

Non-zero differences point at an unsupported construct: unusual ADVAN, custom `$PRED`, `$MIX`, `$PRIOR`, hand algebra in `$ERROR`, duplicate ETA names. Diff the generated rxode2 body against the ctl, patch the rxode2 model (or fix the ctl and re-run NONMEM), and re-qualify.

### Pitfalls

- `cannot find lst file` — wrong `lst=` extension (`.lst` vs `.res` is project-dependent).
- `dataset not found` — `$DATA` is relative to the ctl directory; `setwd()` there or pass `inputData=` / an absolute path.
- Listing reports rounding errors — see the `read-rounding` article before trusting estimates.
- Duplicate ETA names are not auto-renamed; fix the source ctl or use `etaNames=`.
- `parameter not found` when solving — a THETA used only inside `$ERROR` did not propagate; patch the model.
- Reading computed slots with `[[ ]]` (`mod[["thetaMat"]]`) returns `NULL`; use `$`.
- Treating the result as an nlmixr2 fit — it is an rxode2 UI. `babelmixr2::as.nlmixr2(mod)` gives the fit when you need one.

## References

- babelmixr2: `vignettes/articles/running-nonmem.Rmd`
- nonmem2rx: `vignettes/import-nonmem.Rmd`; `vignettes/articles/rxode2-validate.Rmd`, `convert-nlmixr2.Rmd`, `read-rounding.Rmd`, `simulate-new-dosing.Rmd`, `simulate-uncertainty.Rmd`, `simulate-extra-items.Rmd`, `simulate-with-covs.Rmd`, `create-vpc.Rmd`, `create-augPred.Rmd`, `create-office.Rmd`
