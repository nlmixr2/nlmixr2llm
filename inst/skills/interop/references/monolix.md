# Monolix reference — running via babelmixr2 and importing via monolix2rx

## Running an nlmixr2 model in Monolix (babelmixr2)

```r
library(babelmixr2)
options("babelmixr2.monolix" = "monolix")    # CLI name / path; or install lixoftConnectors

fit <- nlmixr(model_fn, data, est = "monolix",
              monolixControl(modelName = "run001"))
```

`monolixControl()` arguments that matter most:

| Argument | Role |
|---|---|
| `modelName` | Output directory / project name. **Always set it.** |
| `runCommand` | Monolix CLI command, or a function for cluster submission. If `lixoftConnectors` is installed and the option is unset, babelmixr2 drives Monolix through the connectors. |
| `exploratoryIterations`, `smoothingIterations`, `burnInIterations`, `simulatedAnnealingIterations` | SAEM schedule written into the `.mlxtran`. |
| `useLinearization` | Linearized vs stochastic likelihood / Fisher information. |
| `stiff` | Use the stiff ODE solver in Monolix. |
| `addProp` | How combined additive + proportional error is expressed in Mlxtran. |

babelmixr2 writes the `.mlxtran` project, the model text file, and the dataset into the `modelName` directory, runs Monolix, then reads the results folder and combines it with the original nlmixr2 model into a fit object; it does not re-translate the Mlxtran.

## Importing a finished Monolix project (monolix2rx)

```r
library(monolix2rx)

# Bundled example
pkgTheo     <- system.file("theo", package = "monolix2rx")
mlxtranFile <- file.path(pkgTheo, "theophylline_project.mlxtran")
mod <- monolix2rx(mlxtranFile)

# A user's project — the results folder must sit beside the .mlxtran
mod <- monolix2rx("path/to/project.mlxtran")

# Structural parse only (no conversion)
proj <- mlxtran(mlxtranFile)
str(as.list(proj))

fit <- babelmixr2::as.nlmixr2(mod)   # promote the qualified import to an nlmixr2 fit
```

Arguments of note: `update` (use the final estimates from the results folder when present), `thetaMatType` (`c("sa", "lin")` by default: which `FisherInformation/covarianceEstimates*.txt` to load, stochastic-approximation preferred), `theta` / `sd` / `cor` (fallback values for estimates missing from the results), `ci` / `sigdig` (tolerance used by the built-in validation).

### Required files on disk

The results folder is the `exportpath` named inside the `.mlxtran` (often the project name, next to the file).

| File / folder | Role |
|---|---|
| `project.mlxtran` | Monolix project (passed to `monolix2rx()`) |
| model text file | the structural model referenced by the project (or a `lib:` library reference) |
| `<exportpath>/summary.txt` | run information, observation and dose counts, Monolix version |
| `<exportpath>/populationParameters.txt` | final estimates |
| `<exportpath>/FisherInformation/covarianceEstimatesSA.txt` or `covarianceEstimatesLin.txt` | covariance of fixed effects (whichever standard-error task ran; `thetaMatType=` picks) |
| `<exportpath>/IndividualParameters/estimatedRandomEffects.txt` | per-ID ETAs (`$etaData`) |
| `<exportpath>/predictions*.txt` | Monolix predictions used for `$predCompare` / `$ipredCompare` |
| dataset CSV | as referenced in the `.mlxtran` |

With only the `.mlxtran`, `monolix2rx()` still succeeds (message: `cannot find individual parameter estimates`) and returns the model with the **initial** estimates from `<PARAMETER>`, `$omega` at its starting values, and `$thetaMat` / `$etaData` `NULL`. That is easy to mistake for a fitted model: check `$thetaMat` and `$etaData` are non-`NULL`, and flag missing artifacts rather than continuing silently.

### What you get back

An **rxode2 model** (not an nlmixr2 fit) carrying `$theta` (fixed effects), `$omega` (random-effect covariance), `$thetaMat` plus `dfSub`/`dfObs` metadata (so `rxSolve(mod, ev, nStud = 100)` simulates parameter uncertainty directly), the μ-referencing table, compartments / state variables, and a normalized R-function model body. Solve it with `et()` + `rxSolve()`.

### Library models

Monolix built-in library models are referenced as `lib:bolus_1cpt_TlagVCl.txt` and cannot be resolved by monolix2rx alone. On `lib:...txt not found`, choose one:

1. `options(monolix2rx.library = "/path/to/library")` pointing at a text-file mirror of the library;
2. install `lixoftConnectors` so the library is looked up live;
3. export the model to a text file inside Monolix and re-point the `.mlxtran` at it.

### Qualification

`monolix2rx()` compares rxode2 PRED/IPRED to Monolix's own predictions during conversion and stores the result in `$predCompare` / `$ipredCompare` / `$iwresCompare`; `summary(mod$ipredCompare)` should be ~0 to working precision. The `rxode2-validate` article walks through it. Non-zero differences mean an unsupported Mlxtran feature: custom distributions, unusual transforms, IOV with a non-standard structure, BLQ parsing. Print the generated model body, diff against the Mlxtran, patch the rxode2 model (or fix the project and re-run Monolix), re-qualify.

### Pitfalls

- Results folder missing or elsewhere — you silently get initial estimates (`$thetaMat` / `$etaData` `NULL`).
- `lib:` model without a resolution path configured.
- No `FisherInformation/covarianceEstimates*.txt` — the standard-error task was skipped; re-run with it enabled if you need `$thetaMat`.
- `$omega` populated but wrong, or empty — random-effect parsing hit a structure monolix2rx does not translate; inspect the model body.
- BLQ handling differs between tools — confirm `CENS` / `LIMIT` columns survive the round-trip.
- Treating the result as an nlmixr2 fit — it is an rxode2 model; `babelmixr2::as.nlmixr2(mod)` gives the fit.

## References

- babelmixr2: `vignettes/articles/running-monlix.Rmd`
- monolix2rx: `vignettes/articles/rxode2-validate.Rmd`, `convert-nlmixr2.Rmd`, `simulate-new-dosing.Rmd`, `simulate-uncertainty.Rmd`, `simulate-extra-items.Rmd`, `create-vpc.Rmd`, `create-augPred.Rmd`, `create-office.Rmd`
