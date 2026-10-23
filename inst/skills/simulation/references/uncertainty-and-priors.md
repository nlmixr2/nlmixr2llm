# Parameter uncertainty and priors in simulation

Uncertainty is simulated **per study**: each of `nStud` studies draws one set of thetas, omega, and sigma, then simulates `nSub` subjects from it. There are three ways to supply the uncertainty.

## 1. From a fit or an import (automatic)

An nlmixr2 fit, a `nonmem2rx()` import, and a `monolix2rx()` import all carry their covariance matrix plus the number of subjects and observations. Adding `nStud` is enough: thetas are drawn from the covariance, and omega / sigma from inverse Wishart distributions with `dfSub` / `dfObs` degrees of freedom.

```r
set.seed(42); rxode2::rxSetSeed(42)
s3 <- rxSolve(fit, ev, nStud = 20, nSub = 20)   # thetaMat = fit$cov, dfSub/dfObs from the data
length(s3$omegaList)                            # one omega draw per study (also $sigmaList)
confint(s3, "cp", level = 0.90) |> plot()
```

The nlmixr2 team recommends this inverse-Wishart route for omega and sigma rather than using their standard errors.

## 2. From priors written in `ini({})`

Priors sit next to the parameter they describe (needs `lotri` >= 1.0.5):

```r
modPrior <- function() {
  ini({
    tka <- 0.45; tcl <- 1; tv <- 3.45
    add.sd <- 0.7
    eta.ka ~ 0.6
    eta.cl + eta.v ~ c(0.3, 0.01, 0.1)
    prior(tka) ~ dnorm(0.45, 0.1)          # normal prior on a theta: dnorm(mean, SD)
    tcl + tv ~ c(0.02, 0.001, 0.03)        # joint normal on thetas (a $THETAPV block)
    prior(eta.cl, eta.v) ~ invWishart(20)  # inverse Wishart, df per OMEGA block (NWPRI)
    prior(eta.ka) ~ invWishart(4)
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    linCmt() ~ add(add.sd)
  })
}
rxUiPriors(modPrior())                        # what priors the model carries

set.seed(42); rxode2::rxSetSeed(42)
s1 <- rxSolve(modPrior, et(amt = 300) |> et(time = 0:24), nStud = 20, nSub = 20)
confint(s1, "sim", level = 0.90) |> plot()    # "sim" is the simulated observation
```

| Form | Means | Simulation role |
|---|---|---|
| `prior(tka) ~ dnorm(mean, sd)` | normal prior on a theta | row/column of the `thetaMat` |
| `tka ~ 0.01` (inside `ini({})` only) | shorthand: normal, variance 0.01, mean = estimate | same |
| `tcl + tv ~ c(var, cov, var)` (inside `ini({})` only) | joint normal on thetas (`multiNormal`). Same shape as an OMEGA block; the left-hand names decide: thetas make a prior, etas make an OMEGA block | block of the `thetaMat` |
| `prior(eta.cl, eta.v) ~ invWishart(df)` | inverse Wishart on a whole OMEGA block | that block's degrees of freedom |
| `om.eta.cl ~ 0.01` or `prior(om.eta.cl) ~ dnorm(0.3, 0.1)` | normal prior on the omega value (TNPRI) | omega drawn jointly with thetas |

- Pipe a prior on or replace one: `mod |> ini(prior(tka) ~ dnorm(0.45, 0.05))`. But `mod |> ini(tka ~ 0.01)` **changes the estimate**; it does not add a prior.
- An OMEGA block takes either degrees of freedom or normal priors on its values, never both.
- **A prior mean must equal the current estimate**, because draws are added to it. To put a prior on a fitted value, splice in the exact unrounded estimate: `v <- fit$theta[["tka"]]; eval(bquote(ini(fit, prior(tka) ~ dnorm(.(v), 0.1))))`.
- Only normal / `multiNormal`, `invWishart`, and `om.*` normal priors can be simulated from. Other distributions (`dcauchy()`, `dbeta()`, ...) are fine for estimation but need `usePrior = FALSE` (or an explicit `thetaMat`) to simulate.
- **A fit estimated with priors** carries them, but its estimates no longer equal the prior means; simulate it with `usePrior = FALSE`.
- Blocks without a prior stay at their estimates. Chunked or file-backed solves (`chunkSize=`, `file=`) cannot use priors and error rather than dropping them.

## 3. From explicit arguments

```r
s2 <- rxSolve(mod, ev, nStud = 20, nSub = 20,
              thetaMat = fit$cov,      # named covariance -> thetas ~ MVN
              dfSub = 12,              # omega ~ inverse Wishart(dfSub), usually the number of subjects
              dfObs = 120)             # sigma ~ inverse Wishart(dfObs), usually the number of observations
```

## Arguments

| Argument | Effect |
|---|---|
| `nStud` | number of between-study draws; `1` means no uncertainty |
| `usePrior` | `NA` (default) uses `ini()` priors when present; `TRUE` requires them; `FALSE` ignores them |
| `thetaMat` | theta covariance; passed at the call site it overrides the priors |
| `dfSub` / `dfObs` | inverse-Wishart degrees of freedom for omega / sigma |
| `omegaSeparation`, `sigmaSeparation` | `"auto"`/`"lkj"`/`"separation"` redraw the matrix from `dfSub`. `"tnpri"` draws omega/sigma entries **jointly** with the thetas from a full covariance whose columns name them (`om.eta.cl`/`cov.eta.cl.eta.v` in `fit$cov`; `eta1`/`omega.2.1` in a nonmem2rx `$thetaMat`), keeping theta–omega correlations. **Known issue** ([rxode2#1388](https://github.com/nlmixr2/rxode2/issues/1388)): when `dfSub` is also set (every fit and import sets it), the off-diagonals still come from the inverse-Wishart draw; pass `dfSub = 0` for a pure tnpri draw |
| `simVariability = FALSE` | typical-value thetas, no uncertainty |
| `priorPdRetry` | retries for a drawn covariance that is not positive definite (default 10) |
