# Model building, precision, and model comparison

The order is data exploration → base structural model (`structural-model.md`) → stochastic model (etas, OMEGA blocks, residual error) → covariates → evaluation. This file covers the steps after the structure is chosen.

## Iterating with model piping

`ini()` and `model()` work on a model function, a UI object, or a fit, returning a new UI object that can be fitted again.

```r
# Change initial estimates
ui2 <- fit |> ini(tcl = log(3), eta.cl = 0.2)

# Fix a parameter
ui3 <- fit |> ini(tv = fixed(log(30)))

# Add a covariate effect (power model on weight, centred at 70 kg)
ui4 <- fit |>
  model(cl <- exp(tcl + eta.cl + wt_cl * log(WT / 70))) |>
  ini(wt_cl <- 0.75)                       # add label("...") lines in the model function itself

# Correlated ETAs (lower-triangle order: var(cl), cov(cl,v), var(v))
ui5 <- fit |> ini(eta.cl + eta.v ~ c(0.3, 0.01, 0.1))

# Swap the residual model
ui6 <- fit |> model(cp ~ add(add.sd) + prop(prop.sd)) |> ini(prop.sd <- 0.1)

fit4 <- nlmixr2(ui4, data, est = "saem", saemControl(print = 0))
```

Covariate columns must exist for every row in the data; missing values for some subjects are the usual reason a piped covariate model fails or drifts.

`nlmixr2extra::addorremoveCovariate(ui, "cl", "WT")` returns the model lines (a list of expressions, not a UI) with a *linear* term `cov_WT_cl * WT` added to `cl`; it is a building block for automated searches, not a drop-in for the power model above.

## Starting models from nlmixr2lib

```r
library(nlmixr2lib)
modellib()                                   # prints the available models (returns NULL)
ui <- readModelDb("PK_2cmt_des") |>
  addEta(c("cl", "vc")) |>
  addResErr(c("addSd", "propSd"))
fit <- nlmixr2(ui, data, est = "saem", saemControl(print = 0))
```

Other edits (on the ODE `_des` models): `addDepot()` / `removeDepot()`, `addTransit(3)`, `addLag("depot")`, `addBioavailability("depot")`, `addIndirect(stim = "in")`, `addDirectLin()` then `convertEmax()`. Library parameters are named on the log scale (`lka`, `lcl`, `lvc`); `addEta("cl")` maps to the right one.

## Nested-model comparison

- Likelihood-ratio test on `fit$objf` (−2LL): ΔOFV of 3.84 ≈ p 0.05 for one added parameter.
- `fit$objDf` also carries AIC / BIC for non-nested comparison.
- Only compare OFVs computed the same way. SAEM does not compute an OFV during the fit (`saemControl(logLik = FALSE)` is the default); `fit$objf` computes a Gaussian-quadrature likelihood on first access, `addCwres(fit)` adds the FOCEi objective as a second row of `fit$objDf`, and `setOfv(fit, "focei")` selects which one `fit$objf` reports. Put both candidates on the same footing before comparing.

## Standard errors and confidence intervals

| Approach | How | When |
|---|---|---|
| Asymptotic (default) | `fit$parFixed` SE / %RSE from the covariance step (`saemControl(covMethod=)`, FOCEi Hessian) | First look |
| Preconditioning | `nlmixr2extra::preconditionFit(fit)` | Covariance step failed or is ill-conditioned |
| Bootstrap | `nlmixr2extra::bootstrapFit(fit, nboot = 200, stratVar = "STUDY")`; then `fit$parFixed` shows bootstrap CIs, `bootplot(fit)` checks ΔOFV; `nlmixr2est::setCov(fit, "boot200")` (name is `boot` + `nboot`) switches the covariance used by downstream uncertainty sims | Reportable CIs; small or unbalanced data |
| Likelihood profiling | `nlmixr2extra::profileLlp(fit, which = c("tcl", "tv"))` returns OFV vs fixed parameter with the CI bound; `profileFixed()` for arbitrary fixed sets | Skewed or bounded parameters |

`bootstrapFit()` writes per-replicate files into `nlmixr2BootstrapCache_<fitName>_<md5>/` under the working directory and resumes from them (`restart = TRUE` starts over); run it inside a dedicated directory.

## Shrinkage and identifiability

- `fit$shrink` — ETA shrinkage > ~30% means individual ETAs (and EBE-based diagnostics) are unreliable for that parameter; consider removing it or note the caveat.
- BSV% near 0 or > 100%, or an OMEGA element whose SE dwarfs its estimate, signals an unsupported random effect.
- A THETA sitting at a bound (compare the estimate with the bounds given in `ini({})`) is not estimated; widen the bound only if physiologically plausible, otherwise restructure.

## Handling BLQ data

Add a `CENS` column (1 = below LLOQ, −1 = above ULOQ, with `DV` holding the limit) and optionally `LIMIT` (for M4); nlmixr2 applies the M3 / M4 likelihood automatically. See `vignettes/censoring.Rmd`.

## Multi-endpoint models

```r
model({
  # ...
  cp     <- center / v
  effect <- e0 - emax * cp / (ec50 + cp)
  cp     ~ prop(prop.sd)  | center     # bare name = CMT / DVID value in the data
  effect ~ add(eff.sd)    | effect
})
```

Bind each residual line to a compartment / endpoint name; the data's `CMT` or `DVID` column holds that name (or its integer index). Fit PK first, then fix PK and fit PD, then joint — unless the data are rich enough for a simultaneous fit.
