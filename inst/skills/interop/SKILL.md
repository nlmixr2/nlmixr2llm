---
name: interop
description: Use this skill when a pharmacometrics task crosses between the nlmixr2 ecosystem and proprietary software — NONMEM, Monolix, or PKNCA. Also babelmixr2's in-R backends (optimal design with PopED is the `design` skill). Triggers include "run my nlmixr2 model in NONMEM/Monolix", `nlmixr(..., est = "nonmem" | "monolix" | "pknca" | "nlmer" | "saemix")`, `nonmemControl()` / `monolixControl()` / `pkncaControl()`, "bring this NONMEM run into R", "translate this Monolix project", references to `.ctl` / `.mod` / `.lst` / `.res` / `.xml` / `.phi` / `.mlxtran` files, `nonmem2rx()` / `monolix2rx()`, qualifying a converted model, or comparing the same model across estimation engines.
---

# Interop — NONMEM, Monolix, and PKNCA from R

Three packages cover two directions of travel:

| Direction | Package | What it does |
|---|---|---|
| **R → engine** (forward) | `babelmixr2` | Write one nlmixr2 model, fit it with `est = "nonmem"`, `"monolix"`, or `"pknca"`. Generates the engine input, runs the engine, reads the engine's output files, and combines them with the original model into an nlmixr2 fit. |
| **Engine → R** (import) | `nonmem2rx` | Finished NONMEM run (control stream + outputs) → rxode2 UI object with THETA/OMEGA/ETAs and predictions baked in. |
| **Engine → R** (import) | `monolix2rx` | Finished Monolix project (`.mlxtran` + results folder) → rxode2 model object. |
| **R → R packages** | `babelmixr2` | `est = "nlmer"`, `"saemix"`, `"fmeMcmc"`, `"pseudoOptim"`, `"poped"` (see the `design` skill): see `references/babelmixr2-backends.md`. |

babelmixr2 does **not** re-translate the engine's model on the way back: it already knows the nlmixr2 model it started from and only imports the engine's estimates and tables (using nonmem2rx's / monolix2rx's low-level file readers). nonmem2rx / monolix2rx are the independent path for runs that did not start in R. Both paths end in an nlmixr2 fit: `babelmixr2::as.nlmixr2(mod)` promotes an imported (and qualified) rxode2 model to a full fit. When a babelmixr2 fit looks wrong, load the same engine output with `nonmem2rx()` / `monolix2rx()` and `as.nlmixr2()` — a second route to the same fit that isolates an import problem. If it qualifies, babelmixr2's reading is at fault; if not, it's a translation limit, not bad engine output.

## Routing

- "Run / fit my model in NONMEM or Monolix", cross-engine comparison, NCA-based initial estimates → **forward path** (babelmixr2).
- "I have a finished NONMEM / Monolix run; simulate / VPC / report from it in R" → **import path** (nonmem2rx / monolix2rx), then hand off to the `simulation` or `reporting` skill.
- Either way, the shared rule: **qualify before you use**. A translation is only trustworthy once rxode2 reproduces the engine's own PRED/IPRED.

Engine-specific detail (file layouts, control options, returned slots, pitfalls) lives in `references/nonmem.md` and `references/monolix.md`; in-R backends in `references/babelmixr2-backends.md`.

## Forward path — babelmixr2

```r
library(babelmixr2)
options("babelmixr2.nonmem"  = "nmfe743")   # NONMEM executable or full path
# options("babelmixr2.monolix" = "monolix")  # or install lixoftConnectors

one.cmt <- function() {
  ini({
    tka <- log(1.57); label("Ka")
    tcl <- log(2.72); label("Cl")
    tv  <- log(31.5); label("V")
    eta.ka ~ 0.6; eta.cl ~ 0.3; eta.v ~ 0.1
    add.sd <- 0.7
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

fit_nm  <- nlmixr(one.cmt, nlmixr2data::theo_sd, est = "nonmem",
                  nonmemControl(modelName = "one_cmt_nm"))
fit_mlx <- nlmixr(one.cmt, nlmixr2data::theo_sd, est = "monolix",
                  monolixControl(modelName = "one_cmt_mlx"))
```

Rules:

1. **One model, many engines.** Never fork the model per engine or hand-write a control stream — that is the problem babelmixr2 exists to remove.
2. **Always set `modelName`.** It names the output directory; unset or reused names collide.
3. **Configure the engine once per session** via `options()`; pass `runCommand=` to the control object only for one-off overrides. `runCommand` may be a function `FUN(ctl, directory, ui)` (cluster submission) that returns after output files exist; `NA` writes the input without running.
4. **Check the engine exists before launching** (`getOption("babelmixr2.nonmem")`, binary on `PATH`) and tell the user if it is missing rather than starting a doomed run.
5. **The result is an nlmixr2 fit.** `print(fit)`, `fit$parFixed`, `fit$omega`, `augPred()`, `vpcPlot()` all work. An empty `$parFixed` after a "successful" run means the import of the engine output broke — see Debugging.
6. **PKNCA is not a model fit.** `est = "pknca"` runs non-compartmental analysis to seed popPK initial estimates. Drive it with `pkncaControl(concu=, doseu=, timeu=, volumeu=)`; units must match the dataset.

## Import path — nonmem2rx / monolix2rx

```r
library(nonmem2rx)
mod <- nonmem2rx("path/to/run123.ctl", lst = ".lst", validate = TRUE)
# or pass the listing (.lst / .res) and the ctl is found alongside it

library(monolix2rx)
mod <- monolix2rx("path/to/project.mlxtran")   # results folder must sit beside it
```

Both return an **rxode2 model, not an nlmixr2 fit**. Solve it with `et()` + `rxSolve()` like any rxode2 model. To get a real nlmixr2 fit (for the `reporting` skill's diagnostics against the original data) call `fit <- babelmixr2::as.nlmixr2(mod)` after qualification. Read slots with `$`: computed ones (`$ini`, `$thetaMat`, `$props`) return `NULL` under `[[ ]]`. Imports carry their covariance, so `rxSolve(mod, ev, nStud = 100)` works directly.

Rules:

1. **Read the source first.** Open the control stream / `.mlxtran` and note the usual translation pain points before converting: NONMEM — ADVAN, `$PRIOR`, `$MIX`, custom `$PRED`, algebra in `$ERROR`; Monolix — custom distributions, IOV, BLQ handling, `lib:` library models.
2. **Confirm the run artifacts exist** (listing, `.xml`, `.phi`, dataset for NONMEM; `summary.txt`, `FisherInformation/covarianceEstimatesLin.txt`, dataset for Monolix). Missing pieces give a silently partial object — flag them.
3. **Qualify every time.** Both converters compare rxode2 against the engine's own predictions during conversion (nonmem2rx when `validate = TRUE`, the default; monolix2rx always) and store the result in `$predCompare` / `$ipredCompare`. Check `summary(mod$ipredCompare)` and `plot(mod)` (nonmem2rx; `autoplot(mod)` returns the ggplot object); diffs must be ~0 to working precision. If diffs are not zero, print the generated model body (`cat(deparse(as.function(mod)), sep = "\n")`), diff it against the source, patch, re-qualify. Never proceed on a model whose IPRED disagrees with the engine.
4. **Resample fitted subjects** (`$etaData` + population THETAs) when downstream sims should honor post-hoc ETAs; re-draw from `$omega` for new-subject sims. Both patterns are in the `simulation` skill.

## Workflow

Done means executed, qualified, and inspected — not merely launched or loaded.

1. Confirm engine path (forward) or artifact set (import).
2. Run the fit or conversion; capture stdout/stderr — engine errors and translation warnings surface there.
3. Qualify: `$ipredCompare` / validation plot for imports; `print(fit)`, `$parFixed`, OFV finite, SEs present for forward fits.
4. Only then do the user's downstream task (simulate, VPC, report), and report qualification status alongside results.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `could not find NONMEM` / `Monolix` | engine option or `runCommand` unset / wrong; check `PATH` |
| Run ends with rounding errors, fit looks empty | non-convergence; fix the model, or `nonmemControl(readRounding = TRUE)` to read partial results |
| Monolix "runs" but no fit | neither `lixoftConnectors` installed nor `babelmixr2.monolix` set |
| `$parFixed` empty after a successful engine run | import of the engine output failed — load the output with `nonmem2rx()` / `monolix2rx()` and `babelmixr2::as.nlmixr2()` as a second route |
| OFV differs from a hand-written ctl | babelmixr2 generates MU-referenced code; compare `MU` refs, `$THETA` bounds, column order |
| `cannot find lst file` / `dataset not found` | wrong `lst=` extension; `$DATA` path is relative to the ctl directory — `setwd()` or use absolute paths |
| `lib:...txt not found` | Monolix library model — set `options(monolix2rx.library=)`, install `lixoftConnectors`, or export the model to text |
| `$thetaMat` / `$etaData` are `NULL` after conversion | Monolix results folder missing: you got the *initial* estimates from the `.mlxtran`, not the fit |
| `$omega` looks wrong | an unsupported random-effect structure; inspect the model body |
| Large `$ipredCompare` diffs | unsupported construct; inspect the generated rxode2 model and reconcile by hand |
| `saemix` errors | `linCmt()` or a theta without an eta ([#212](https://github.com/nlmixr2/babelmixr2/issues/212)) |
| Model with `prior()` lines refused | no babelmixr2 backend uses `ini()` priors |
| PKNCA result has no concentrations | unit arguments missing or inconsistent with the dataset |

## What NOT to do

- Don't hand-write a control stream or Mlxtran when babelmixr2 can generate it.
- Don't trust a fit or conversion you haven't inspected and qualified.
- Don't rebuild an imported model from scratch "to be safe" — patch only what the qualification diff shows is wrong.
- Don't treat an imported model as an nlmixr2 fit; it is an rxode2 model until `babelmixr2::as.nlmixr2()` makes it one.
- Don't reuse `modelName` across engines or runs.

## References (in each package's repo)

- babelmixr2: `vignettes/articles/running-nonmem.Rmd`, `running-monlix.Rmd`, `running-pknca.Rmd`, `new-estimation.Rmd`, `PopED.Rmd`
- nonmem2rx: `vignettes/import-nonmem.Rmd`; `vignettes/articles/rxode2-validate.Rmd`, `convert-nlmixr2.Rmd`, `read-rounding.Rmd`, `simulate-*.Rmd`, `create-vpc.Rmd`, `create-augPred.Rmd`, `create-office.Rmd`
- monolix2rx: `vignettes/articles/rxode2-validate.Rmd`, `convert-nlmixr2.Rmd`, `simulate-*.Rmd`, `create-vpc.Rmd`, `create-augPred.Rmd`, `create-office.Rmd`
