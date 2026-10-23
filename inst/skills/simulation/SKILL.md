---
name: simulation
description: Use this skill when the user wants to simulate a pharmacokinetic or pharmacodynamic model in R with the nlmixr2 ecosystem — writing or editing an ODE model, building dosing / sampling event tables, single-subject or population simulation, clinical trial simulation, propagating parameter uncertainty (fits, imports, or `prior()`s), adaptive dosing, resampling fitted subjects, pulling a starting model from the nlmixr2 model library, or debugging rxode2 compile and solver errors. Triggers include `rxode2`, `rxSolve()`, `et()` / `eventTable()`, `d/dt(...)`, `nSub` / `nStud`, `omega=` / `thetaMat=`, `prior()`, `bolus()`, `useLinCmt`, "simulate this regimen", "what does exposure look like if...", `nlmixr2lib`, `readModelDb()`.
---

# Simulation — ODE-based PK/PD simulation with rxode2

Every simulation has three parts. Produce all three when asked for "a simulation"; a model alone is rarely useful.

1. **Model** — an R function with `ini({})` (parameters) and `model({})` (equations). This is rxode2's language and it is shared with nlmixr2; a fitted nlmixr2 model or an imported NONMEM/Monolix model simulates the same way.
2. **Event table** — `et()` describing doses and sampling times (or a NONMEM-style data frame with `ID/TIME/EVID/AMT/CMT`).
3. **Solve** — `rxSolve(model, events, ...)` returning a data frame over time.

## Minimum viable example

```r
library(rxode2)

mod <- function() {
  ini({
    ka <- 1.0
    cl <- 2.0
    v  <- 20
  })
  model({
    cp <- central / v
    d/dt(depot)   <- -ka * depot
    d/dt(central) <-  ka * depot - cl / v * central
  })
}

ev <- et(amountUnits = "mg", timeUnits = "hours") |>   # unit arguments need the `units` package
  et(amt = 100, cmt = "depot") |>
  et(time = 0:24)

sim <- rxSolve(mod, ev)
head(sim)
plot(sim, cp)
```

Run it. Confirm it compiles and solves before handing it back.

## Authoring rules

1. **Compartments are named by `d/dt(name)`.** Dose and set initial conditions by that exact name (`cmt = "depot"`, `depot(0) <- 0`). Initial conditions live inside `model({})`, not `ini({})`.
2. **Order matters.** Algebraic definitions (`cp <- central / v`) must precede the lines that use them.
3. **Parameters.** Fixed values use `<-` in `ini({})`. Between-subject variability uses `~` with a variance (`eta.cl ~ 0.1`) and enters the model as `cl <- exp(tcl + eta.cl)`. Residual error is a trailing line `cp ~ add(add.sd)` / `prop()` / `lnorm()` and is only needed when simulating observations with noise.
4. **Override at solve time**, not by editing the model: `rxSolve(mod, ev, params = c(cl = 4))`. `params=` also accepts a per-subject `data.frame` keyed by `id`.
5. **Name the sampling argument.** `ev |> et(time = 0:24)`. An unnamed vector (`ev |> et(0:24)`) errors with `improper arguments to 'et'` when piped.
6. **Units.** Keep `timeUnits` in `et()` consistent with the rate constants in `ini({})` (hours vs days is the classic bug).
7. **Reproducibility.** For anything random set both seeds: `set.seed(5446); rxode2::rxSetSeed(5446)`.
8. **Pipe; don't retype.** `x |> ini(...)` / `x |> model(...)` on a model or fit return a modified copy; use them for what-ifs and dosing protocols.
9. **`useLinCmt`.** The ODE → `linCmt()` conversion renames compartments (`centr` → `central`). Function-style models still convert by default ([rxode2#1389](https://github.com/nlmixr2/rxode2/issues/1389)); pass `useLinCmt = FALSE`, or name the compartment `central`.
10. **Starting from the model library.** `nlmixr2lib::readModelDb("PK_2cmt_des")` returns a ready model function; `nlmixr2lib::modellib()` lists what is available (1/2/3-compartment PK, indirect response, tumor growth, published mAb models). Pipe modifications: `|> addEta("ka") |> addResErr("propSd")`.

## Event-table cheatsheet

```r
et(amt = 100, cmt = "depot") |> et(time = 0:24)                        # single dose
et(amt = 100, addl = 9, ii = 12, cmt = "depot") |> et(time = 0:120)    # q12h x 10
et(amt = 100, ii = 12, ss = 1, cmt = "depot") |> et(time = 0:24)       # steady state
et(amt = 100, rate = 10, cmt = "central") |> et(time = 0:24)           # infusion by rate
et(amt = 100, dur = 2, cmt = "central") |> et(time = 0:24)             # infusion by duration
et(amt = 100, cmt = "depot") |> et(time = 0:24) |> et(id = 1:50)       # 50 subjects, same regimen

# Per-subject dosing (e.g. weight-based) — build per id, then add sampling
ev <- et()
for (i in seq_len(nSub)) {
  ev <- ev |> et(id = i, amt = dose[i], time = 0, addl = 9, ii = 12, cmt = "depot")
}
ev <- ev |> add.sampling(time = 0:240)
```

`etRbind()` stacks event tables. NONMEM-style data frames are accepted by `rxSolve()` directly.

## Population and trial simulation

```r
sim <- rxSolve(mod, ev, nSub = 200)                    # re-draw ETAs from the model's omega
sim <- rxSolve(mod, ev, nSub = 200, nStud = 50,
               thetaMat = fit$cov)                     # + parameter uncertainty across studies
confint(sim, "cp", level = 0.95) |> plot()             # median + interval ribbon (CI band needs >= 2500 sims)
```

- `nSub` draws new subjects from `omega`; `nStud` replicates trials, drawing population parameters from `thetaMat=` (from `fit$cov` or an imported `$thetaMat`).
- **From a fit or import, uncertainty is automatic:** `rxSolve(fit, ev, nStud = 100)` fills `thetaMat`, `dfSub`, `dfObs`. `prior()` lines in `ini({})` also drive the draws. See `references/uncertainty-and-priors.md` (prior forms, arguments, the `tnpri` caveat).
- **Adaptive dosing** (titration, holds, rescue): pipe `bolus()`/`infuse()` rules onto the model or fit; see `references/adaptive-dosing.md`.
- To honor **fitted** subjects (post-hoc ETAs from a fit or an imported NONMEM/Monolix model) build a per-subject parameter table and pass it as `params=`; see `references/population-simulation.md`.
- Covariates: non-time-varying ones go as columns of the `params=` data frame; time-varying ones must be merged into the event table as columns.
- `confint()` prints a note and draws only the median / prediction interval when fewer than 2500 simulated subjects (`nSub * nStud`) are available; the confidence band around the percentiles needs at least that many.

## Workflow

Done means executed and inspected, not written.

1. Write model + events + solve call as a complete script with `library(rxode2)`.
2. Run it and capture errors verbatim.
3. Sanity-check the output: `head(sim)`, Cmax / AUC / accumulation ratio / steady-state behaviour — whatever is physically meaningful.
4. Then report, including the seed(s) used.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `compartment 'X' not found` | `cmt=` does not match a `d/dt(X)` |
| Output has `central`, model says `centr` | `linCmt()` conversion ran (rule 9) |
| `cannot simulate from the prior` | prior mean ≠ estimate (e.g. a prior-bearing fit); `usePrior = FALSE` |
| `parameter 'X' not found` | symbol not in `ini({})`, not a compartment, not in `params=`, not a data column |
| `improper arguments to 'et'` | unnamed sampling vector piped into `et()`; use `et(time = ...)` |
| Compilation fails | `model({})` syntax; surface the exact rxode2 message |
| `non-finite values` / max steps exceeded | division by zero (volume unset), stiff system (`method = "lsoda"`), wrong initial conditions |
| Output flat or zero | dosing into the wrong compartment, or `amt` missing |
| Wrong magnitude | unit mismatch between `timeUnits` and rate constants |
| Every subject identical | model has no `~` random effects, or `omega=` not supplied |
| `there is no package called 'units'` | `et(amountUnits=, timeUnits=)` needs the `units` package; install it or drop the unit arguments |

## What NOT to do

- Don't invent syntax; check `inst/syntax-functions.csv` and `inst/reserved-keywords.csv` in the rxode2 repo.
- Don't deliver pseudocode or a model that never compiled.
- Don't silently change a user's parameter values; say so.
- Don't skip the seed when the result has randomness.

## References (rxode2 repo unless noted)

- `vignettes/rxode2-intro.Rmd`, `rxode2-syntax.Rmd`, `vignettes/articles/rxode2-ui-object.Rmd` — model language
- `vignettes/rxode2-event-table.Rmd`, `rxode2-event-types.Rmd`, `rxode2-events-classic.Rmd` — events
- `vignettes/rxode2-single-subject.Rmd`, `rxode2-sim-var.Rmd` — single-subject and population simulation
- `vignettes/articles/rxode2-clinical-trial-sim.Rmd`, `rxode2-parameter-uncertainty.Rmd`, `rxode2-eta-eps-resampling.Rmd` — trial simulation, uncertainty, resampling
- `vignettes/rxode2-covariates.Rmd`, `rxode2-prior-data.Rmd` — covariates and external data
- `vignettes/articles/Modifying-Models.Rmd` — model piping
- nlmixr2lib: `vignettes/list-of-models.Rmd`, `create-model-library.Rmd`
