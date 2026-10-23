# Priors in estimation — penalized (MAP) and Bayesian fits

Priors go in `ini({})` next to the parameter, with the same syntax rxode2 uses for uncertainty simulation (every form is listed in the `simulation` skill, `references/uncertainty-and-priors.md`). `dnorm(mean, sd)` takes an SD; `lotri::lotriPriorDists()` lists every distribution.

```r
one.cmt.prior <- function() {
  ini({
    tka <- 0.45; tcl <- log(c(0, 2.7, 100)); tv <- 3.45
    add.sd <- c(0, 0.7)
    eta.ka ~ 0.6; eta.cl ~ 0.3; eta.v ~ 0.1
    prior(tka) ~ dnorm(0.45, 1)
    prior(tcl) ~ dnorm(1, 1)
    prior(tv) ~ dnorm(3.45, 1)
    prior(add.sd) ~ dcauchy(0, 2.5)
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    linCmt() ~ add(add.sd)
  })
}
fitMap <- nlmixr2(one.cmt.prior, theo_sd, "focei", foceiControl(print = 0))  # -2 log p(theta, omega) added to the objective
fitMap$parFixed

# simulating uncertainty from this fit needs usePrior = FALSE (see below)
rxSolve(fitMap, et(amt = 320) |> et(time = 0:24), nStud = 10, nSub = 20, usePrior = FALSE)
```

A full Bayesian fit through Stan uses the same model:

```r
library(nlmixr2bayes)
fitNuts <- nlmixr2(one.cmt.prior, theo_sd, "nuts", nutsControl(seed = 42, chains = 2, iter = 1000))
# also est = "advi" (adviControl()) and est = "pathfinder" (pathfinderControl())
```

## Which methods use priors

- **A prior is never silently ignored.** The FOCEi family (all variants, including `fo`/`foi`), `laplace`/`agq`, and `imp`/`impmap`/`qrpem` use them as a penalty. `nuts`/`advi`/`pathfinder` use them as the Bayesian prior, and `posthoc` evaluates them.
- Every other method (`saem`, `nlme`, `npag`, `vae`, the pooled optimizers, and every babelmixr2 backend) refuses a model with priors, naming the parameters. Remove the priors or pick a method that uses them.
- The prior convention (`"general"`, NONMEM `"nwpri"`, `"tnpri"`) is auto-detected from what the model wrote; force it with `foceiControl(priorMethod = )`.
- **nlmixr2bayes refuses a model that declares no priors at all**, and prints suggested `prior()` lines to paste into `ini({})`. Any single prior (on a theta, an omega block, or a residual parameter) is enough to pass that check. Thetas without a prior then get weak defaults centred on their `ini()` estimates, and OMEGA blocks without one get an announced LKJ(2) + half-Cauchy default. Set priors deliberately on the parameters that matter rather than relying on these defaults.
- `covMethod = "analytic"` in the control is downgraded to a finite-difference covariance (`"r,s"`) on a prior-penalized fit; `setCov(fit, "analytic")` can still install the analytic one afterwards.

## Simulating from a fit that carries priors

The fit keeps its priors, but its estimates have moved off the prior means, and rxode2's prior simulation needs the mean to equal the estimate. Simulate uncertainty from the fit's covariance instead, by passing `usePrior = FALSE` (as at the end of the first example).
