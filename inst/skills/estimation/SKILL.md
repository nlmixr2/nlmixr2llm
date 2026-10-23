---
name: estimation
description: Use this skill when the user wants to fit a population PK/PD model to data in R with nlmixr2 — writing an `ini({}) / model({})` model for estimation, choosing an estimation method (SAEM, FOCEi, Laplace/AGQ, importance sampling, nonparametric, pooled optimizers, Bayesian via nlmixr2bayes), `prior()` lines, `setCov()`, tuning `saemControl()` / `foceiControl()`, building the model up (adding ETAs, covariates, residual error, OMEGA blocks), checking convergence and parameter precision, running bootstrap or likelihood-profile confidence intervals, comparing nested models, exploring the base structural model (number of compartments, absorption, elimination, PD link), fitting a model with an embedded neural network (nlmixr2nn `nn()`, universal differential equations / neural ODEs, learned covariate relationships), or debugging a fit that fails or gives implausible estimates. Triggers include `nlmixr2()` / `nlmixr()`, `est = "saem" | "focei" | ...`, `$parFixed`, `$omega`, `$objf`, `bootstrapFit()`, `profileLlp()`, `nn()` / `nnControl()`, "neural network", "fit this model", "estimate the parameters", "which estimation method should I use".
---

# Estimation — population PK/PD modeling with nlmixr2

A complete estimation task has four parts:

1. **Model function** — `function() { ini({...}); model({...}) }` (the rxode2 language plus initial estimates and a residual-error line).
2. **Dataset** — NONMEM-style `ID / TIME / EVID / AMT / CMT / DV` (+ covariates, `DVID`, `CENS` / `LIMIT`).
3. **Fit** — `nlmixr2(model, data, est = "...", control = ...Control(...))`.
4. **Inspection** — `print(fit)`, `fit$parFixed`, `fit$omega`, and at least one diagnostic before anything is reported.

Do not stop until the model has converged and been inspected.

## Minimum viable example

```r
library(nlmixr2)

one.compartment <- function() {
  ini({
    tka <- log(1.57); label("Ka")
    tcl <- log(2.72); label("Cl")
    tv  <- log(31.5); label("V")
    eta.ka ~ 0.6
    eta.cl ~ 0.3
    eta.v  ~ 0.1
    add.sd <- 0.7
  })
  model({
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + eta.cl)
    v  <- exp(tv  + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

fit <- nlmixr2(one.compartment, theo_sd, est = "saem", saemControl(print = 0))
print(fit)
fit$parFixed
```

## Authoring rules

1. **Hand `nlmixr2()` the function itself**, not `model()`; it instantiates internally.
2. **Log / logit scale for fixed effects.** `tcl <- log(2.72)` in `ini`, `cl <- exp(tcl + eta.cl)` in `model`. Use `logit()` / `expit()` for (0, 1) parameters, or `logit(x, low, hi)` / `expit(x, low, hi)` for (low, hi) bounds. Forgetting `log()` is the most common cause of a fit that wanders.
3. **`label()` every THETA** so `$parFixed` and reports are readable.
4. **Random effects** use `~` with a starting *variance*: `eta.cl ~ 0.3`. Correlated ETAs: `eta.cl + eta.v ~ c(0.3, 0.01, 0.1)` (lower-triangle order).
5. **Residual error** ends `model({})`: `cp ~ add(add.sd)`, `prop(prop.sd)`, `add(add.sd) + prop(prop.sd)`, `lnorm(lnorm.sd)`; transforms and heavier tails via `add(add.sd) + boxCox(lambda)` or `add(add.sd) + dt(df)`; a fully custom likelihood via `ll(cp) ~ <log-likelihood expression>` (FOCEi family or SAEM). Multi-endpoint: one line per endpoint bound to the data with `| endpointName` (a bare name matching the `CMT` / `DVID` value, e.g. `effect ~ add(eff.sd) | effect`).
6. **Bounds / fixed values.** `tcl <- log(c(0, 2.7, 100))` gives lower / initial / upper; `tv <- fixed(log(31.5))` fixes a THETA.
7. **Pick `est=` deliberately** (see table) and always pass the matching control (`saemControl()`, `foceiControl()`, `foceControl()`, `foControl()`, `laplaceControl()`, `agqControl()`, `nlmeControl()`) with `print = 0` in scripts.
8. **Closed-form PK** can use `linCmt()` in place of the ODEs (`linCmt() ~ add(add.sd)`), which is faster for 1–3 compartment linear models.
9. **The model decides the family:** no etas needs a pooled method (`focei`, `nlm`, `nlminb`, `bobyqa`, ...). Full list, variants, and covariance tokens: `references/estimation-methods.md`.
10. **Priors** in `ini({})` work with the FOCEi family, `laplace`/`agq`, `imp`/`impmap`/`qrpem`, `posthoc`, and nlmixr2bayes; other methods refuse them. See `references/priors.md`.
11. **Neural networks → gradient-based estimation.** If the model contains `nn()` (nlmixr2nn), fit with `"focei"` (or `laplace`/`agq`, `impmap`, `vae`/`emvi`/`fbvi`); with no etas, a population estimator with gradients (`"lbfgsb3c"`, `"nlminb"`, `"n1qn1"`). Not SAEM, `imp` (no MAP step; `impmap` is fine), `qrpem`, nonparametric, or a derivative-free population estimator (`bobyqa`). The gradient that matters is on the inner step, where the weights train from exact sensitivities; FOCEi's `bobyqa` outer optimizer is fine. See `references/neural-networks.md`.

## Estimation methods

| `est=` | Use for |
|---|---|
| `"saem"` | Best when the model has **many** etas (but not when it contains `nn()`; see rule 11) (the BSV structure matters more than structural complexity); tolerant of poor initials. Computes SEs by default via `covMethod` in `saemControl()`; check they are present. Does not compute an objective function during the fit: `fit$objf` (Gaussian quadrature) or `addCwres(fit)` (FOCEi) adds one. |
| `"focei"` | Best when the model has **few** etas. Gradient-based with Hessian SEs; more sensitive to initials and stiffness; supports generalized `ll()` likelihoods (as does SAEM). Common pattern: SAEM first, then FOCEi from the SAEM estimates. |
| `"foce"`, `"fo"`, `"foi"` | Variants without interaction / first-order; legacy comparison. |
| `"laplace"`, `"agq"` | Laplace approximation (AGQ with one quadrature point) and adaptive Gaussian quadrature (`agqControl(nAGQ=)`); more accurate likelihoods, but keep `nAGQ` small and use only with few ETAs. |
| `"nlme"` | Wraps R's `nlme`; simple closed-form models. |
| `"posthoc"` | Freeze THETA/OMEGA, compute ETAs for (new) data. |
| `"imp"`, `"qrpem"`, `"npag"`, `"vae"`, pooled `"nlm"`/`"bobyqa"`/..., Bayesian `"nuts"` | see `references/estimation-methods.md` / `priors.md` |
| `"nonmem"`, `"monolix"`, `"pknca"`, `"nlmer"`, `"saemix"` | babelmixr2 — see the `interop` skill. |

`nlmixr2est::nlmixr2AllEstType()` lists everything registered, grouped by category.

## Model building

Order: data exploration → **base structural model** → stochastic model (etas, OMEGA, residual error) → covariates → evaluation. When the structure is not given ("how many compartments", "which absorption model", "what model fits this data"), run the structural exploration loop in `references/structural-model.md` first. Fit several candidates under an identical stochastic model, gate and rank them (OFV/AIC plus a VPC discrepancy), write a structured diagnosis, keep a log, and fall back to a neural-network term only when no candidate fits.

After that, start simple, add one thing at a time, and keep the OFV trail.

```r
fit2 <- fit |> ini(tka = log(2)) |> nlmixr2(theo_sd, est = "saem", saemControl(print = 0))   # new initials
fit3 <- fit |> model(cl <- exp(tcl + eta.cl + wt_cl * log(WT / 70))) |>                        # add a covariate
  ini(wt_cl <- 0.75) |> nlmixr2(theo_sd, est = "saem", saemControl(print = 0))
fit$objf; fit3$objf                                                                             # ΔOFV for nested models
```

- Model piping (`ini()` / `model()` on a fit or function) is the idiomatic way to iterate; it preserves the rest of the model.
- `nlmixr2lib` supplies starting models and edits: `readModelDb("PK_2cmt_des") |> addEta("cl") |> addResErr("propSd")`.
- Standard errors: `fit$parFixed` shows SE / %RSE; if missing, switch the covariance method with `setCov(fit, "analytic")` (no refit), call `nlmixr2extra::preconditionFit(fit)` for an ill-conditioned covariance, or bootstrap (`bootstrapFit()`), or profile (`profileLlp()`). Details in `references/model-building.md`.

## Inspecting a fit

| Accessor | Contents |
|---|---|
| `print(fit)` | population estimates, BSV, shrinkage, OFV, timing |
| `fit$parFixed` / `fit$parFixedDf` | formatted / numeric table: estimate, SE, %RSE, back-transformed value, BSV%, shrinkage |
| `fit$omega`, `fit$cov` | BSV variance-covariance; fixed-effect covariance |
| `fit$objf`, `fit$objDf` | OFV / −2LL, AIC, BIC. SAEM does not compute an OFV during the fit: `fit$objf` computes one (Gaussian quadrature) on first access, and `fit$objDf` shows `NA` until then. Access it before saving a fit. |
| `fit$shrink`, `fit$etaObf` | shrinkage per ETA; per-ID ETAs |
| `fit$parHist`, `nlmixr2plot::traceplot(fit)` | iteration history (SAEM / FOCEi) |
| `as.data.frame(fit)` | per-row `PRED`, `IPRED`, `IWRES`, `CWRES`, `ETA*` (add with `addCwres()`, `addNpde()` if absent) |

Acceptance checks before reporting: OFV finite; no THETA on a bound; %RSE reasonable (< ~50% for structural parameters); ETA shrinkage noted if > ~30%; residual-error estimate sensible for the DV scale; at least one diagnostic plot looked at (`plot(fit)`, `augPred(fit)`, or `vpcPlot(fit)` — see the `reporting` skill).

## Workflow

1. Read the data and model first; never guess column or compartment names.
2. Fit with `print = 0`; capture the console output — convergence messages and warnings live there.
3. Inspect the accessors above and one diagnostic.
4. If the fit fails the acceptance checks, change one thing (initials, method, OMEGA structure, error model), refit, compare OFV.
5. Report estimates with their precision and any caveats (shrinkage, bounds, non-convergence).

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `parameter not found` at compile | symbol not in `ini({})`, not a compartment, not in the data |
| SAEM OFV swings wildly / runs forever | initials off-scale (missing `log()`), or a covariate column missing for some rows |
| FOCEi Hessian / covariance failure | over-parameterized OMEGA, ETA variance near zero, identifiability; drop or fix ETAs, switch the outer optimizer away from the `bobyqa` default (`foceiControl(outerOpt = "nlminb")`, or `fast = TRUE` for `lbfgsb3c`), or `preconditionFit()` |
| SEs `NA` in `$parFixed` | covariance step failed; `setCov(fit, "analytic")` / `"sa"` (no refit), bootstrap, or profile |
| "needs to be a mixed effect model" / "can only have population estimates" | wrong method family (rule 9) |
| Parameter sits on its bound | not really estimated; rethink the structure or bounds |
| BSV% near 0 or > 100% | ETA unsupported by data; remove it |
| `vpcPlot` / `augPred` empty or flat | residual line missing, `dvid` mismatch, or `CMT` in data does not map to `d/dt(name)` |
| Fit "converges" but IPRED misses the data | dosing compartment or units wrong in the data |
| Model with `nn()` fit by SAEM has a huge OFV or never settles | wrong method: refit with `"focei"` (rule 11) |

## What NOT to do

- Don't rely on default initial estimates; set them on the right scale.
- Don't report SAEM output without confirming SEs exist and a diagnostic was inspected.
- Don't add several ETAs / covariates at once; you lose the OFV trail.
- Don't deliver pseudocode or a model that never ran.

## References (nlmixr2 repo unless noted)

- `vignettes/running_nlmixr.Rmd` — canonical intro
- `vignettes/residualErrors.Rmd`, `addingCovariances.Rmd`, `multiple-endpoints.Rmd`, `censoring.Rmd` — error models, OMEGA blocks, multi-endpoint, BLQ
- `vignettes/modelPiping.Rmd` — iterating with `ini()` / `model()`
- `vignettes/broom.Rmd` — tidying fit objects
- `vignettes/nimo.Rmd`, `mavoglurant.Rmd`, `wbc.Rmd` — worked PK/PD examples
- nlmixr2extra: bootstrap, likelihood profiling, preconditioning (see `references/model-building.md`)
- nlmixr2lib: `vignettes/list-of-models.Rmd`
- AgentODE (Yang et al. 2026, arXiv:2607.00733): the propose–diagnose–log loop behind `references/structural-model.md`
- nlmixr2nn: `vignettes/nlmixr2nn.Rmd`, `nlmixr2nn-node.Rmd` — neural networks in models (see `references/neural-networks.md`)
