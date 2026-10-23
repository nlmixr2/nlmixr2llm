---
name: design
description: Use this skill when the user wants optimal design for a population PK/PD study in R — evaluating how precisely a planned design will estimate the model's parameters (expected RSE%, FIM), optimizing sampling times or doses, comparing candidate designs (including group sizes), predicting shrinkage, computing the power or sample size to detect a covariate effect, or using prior information (a previous study's FIM) in a design. Works from an nlmixr2 / rxode2 model through babelmixr2 and PopED. Triggers include `est = "poped"`, `popedControl()`, `evaluate_design()`, `poped_optim()`, `get_rse()`, `shrinkage()`, `evaluate_power()`, `babel.poped.database()`, `PopED`, "optimal design", "D-optimal", "sampling schedule", "how many subjects", "expected precision of this study".
---

# Design — optimal design for population PK/PD with PopED

Design answers "how well would this study estimate the model?" *before* any data exist. It needs three parts:

1. **Model** — an ordinary nlmixr2 model function with the parameter values you expect (thetas, omegas, residual error). These values are assumptions, not estimates, so say where they come from.
2. **Design** — groups, doses, and sampling times, written as an rxode2 event table or data frame. Design windows go in `low` / `high` columns; design variables such as `DOSE` go in `popedControl(a = )`.
3. **Criterion** — usually D-optimality on the Fisher information matrix (FIM). PopED reports the expected relative standard error (RSE%) of each parameter.

babelmixr2 turns the model and design into a PopED database with `nlmixr2(model, design, "poped", popedControl(...))`, generating PopED's model, parameter, and error functions for you. Everything after that uses PopED's own functions.

## Minimum viable example

```r
library(babelmixr2)
library(PopED)

warf <- function() {
  ini({
    tCl <- 0.15; tV <- 8; tKA <- 1.0
    tFavail <- fix(1)
    eta.cl ~ 0.07; eta.v ~ 0.02; eta.ka ~ 0.6
    prop.sd <- sqrt(0.01)
    add.sd <- sqrt(0.25)
  })
  model({
    CL <- tCl * exp(eta.cl); V <- tV * exp(eta.v); KA <- tKA * exp(eta.ka)
    Favail <- tFavail
    y <- (DOSE * Favail * KA / (V * (KA - CL / V))) * (exp(-CL / V * time) - exp(-KA * time))
    y ~ prop(prop.sd) + add(add.sd)
  })
}

# one group of 32 subjects, 8 samples; sampling allowed anywhere in 0-120 h
e <- et(c(0.5, 1, 2, 6, 24, 36, 72, 120)) |> as.data.frame()

db <- nlmixr2(warf, e, "poped",
              popedControl(groupsize = 32, minxt = 0, maxxt = 120,
                           a = c(DOSE = 70), mina = c(DOSE = 0), maxa = c(DOSE = 100)))

res <- evaluate_design(db)   # list: $ofv, $fim, $rse
res$rse                      # expected RSE% per parameter
shrinkage(db)                # expected eta shrinkage (variance and SD scale)
plot_model_prediction(db, PI = TRUE)
```

Run it and read the RSEs before optimizing: they show which parameters the current design already pins down and which it cannot.

## Optimizing

```r
out <- poped_optim(db, opt_xt = TRUE)                 # optimize sampling times (ARS + BFGS + LS by default)
summary(out)
get_rse(out$FIM, out$poped.db)                        # RSE% under the optimized design
plot_model_prediction(out$poped.db)

out2 <- poped_optim(db, opt_xt = TRUE, opt_a = TRUE)  # times and dose together
```

- `opt_xt` optimizes sampling times and `opt_a` design variables (dose, covariates). Sample-count and group-size optimization (`opt_samps`, `opt_inds`) is **not implemented** in R PopED and stops with an error: compare group sizes by evaluating candidate designs, or get the minimum N for a target power with `evaluate_power(..., find_min_n = TRUE)`.
- `method = "LS"` (line search) or `"GA"` (genetic algorithm) change the search strategy. `parallel = TRUE` speeds it up but does not work well on Windows.
- Discrete design spaces: `popedControl(discrete_xt = list(0:120), discrete_a = list(seq(10, 100, 10)))` restricts times and doses to allowed values.
- `plot_efficiency_of_windows(out$poped.db, xt_windows = 0.5)` shows how much efficiency is lost if samples drift within a window.

## Authoring rules

1. **The model's values are the design assumptions.** Use literature or prior-study estimates, and report them next to the design. A design is only optimal *for* those values.
2. **Error parameters become variances.** babelmixr2 writes residual error as variances (`sig_prop.var`), not the model's SDs; the RSE table uses those names.
3. **Name parameters, don't count them.** Fixed parameters change PopED's indices. Use `babelBpopIdx(db, "tCl")` wherever PopED wants a `bpop` index (e.g. `evaluate_power()`).
4. **Modify a babelmixr2 database with `babel.poped.database()`**, never `create.poped.database()`. babelmixr2 tracks which compiled model is loaded, and the PopED constructor can leave the wrong one loaded: R may crash or give wrong results.
5. **Covariances in omega** show up as `D[#,#]` in PopED output; `$popedD` on the model gives the name translation.
6. **Not supported yet:** inter-occasion variability (IOV). A model using `mtime()` still works but forces a slower solver.
7. **Multiple groups** use a design table with a **single `id`** plus one `a` entry per group: `a = list(c(DOSE = 20), c(DOSE = 40))`. PopED infers the number of groups (`m`) from `a`, and `groupsize` must be a single value, applied to every group. Two `id`s in the table, or `groupsize = c(10, 20)`, error. **Multiple responses** (PK and PD) use an integer `dvid` column, which becomes PopED's `model_switch`.

Design criteria other than D-optimal (Ds for a subset of parameters, ED over parameter uncertainty), prior information, power, and covariate distributions are in `references/poped-recipes.md`.

## Workflow

1. Write the model with the assumed values, and say where they come from.
2. Build the design table and `popedControl()`; create the database.
3. `evaluate_design()` and `shrinkage()` the current (or proposed) design first.
4. Optimize what the protocol can actually change (sampling times, doses), and compare candidate group sizes by evaluation.
5. Report the before and after RSEs, the design, and the assumptions it depends on.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| R crashes or results look wrong after editing a database | used `create.poped.database()` on a babelmixr2 database; use `babel.poped.database()` |
| RSE is 0 or `NaN` for a parameter | the design carries no information about it (e.g. a covariate effect with no covariate variation); change the design or fix the parameter |
| `evaluate_power()` reports the wrong parameter | used a hard-coded `bpop` index; use `babelBpopIdx()` |
| RSE names don't match the model's SDs | residual error is expressed as variances in PopED |
| IOV model gives wrong precision | IOV is not supported yet |
| `parallel = TRUE` hangs on Windows | set `parallel = FALSE` |

## References

- babelmixr2: `vignettes/articles/PopED.Rmd`; ported PopED examples in `system.file("poped", package = "babelmixr2")` (`ex.*.babelmixr2.R`): evaluation, optimization, ED and Ds designs, priors and power, covariate distributions, shrinkage, PK/PD, TMDD, adaptive dosing
- PopED: package vignettes (`vignette(package = "PopED")`) and the help for `evaluate_design()`, `poped_optim()`, `evaluate_power()`
