# Neural networks in models — nlmixr2nn

`nlmixr2nn` puts a small neural network inside an rxode2/nlmixr2 model as an ordinary term, `nn(...)`. The network can stand in for an unknown term of the ODE right-hand side (a **universal differential equation**, UDE, the pharmacometric form of a neural ODE) or learn a covariate relationship. Everything else stays standard: the model compiles and solves before it is fitted, `nlmixr2()` trains the weights along with THETA/OMEGA, and the fit works with `predict()`, `rxSolve()` and `saveRDS()`.

It is not on CRAN; install with `remotes::install_github("nlmixr2/nlmixr2nn")`. Attach it (`library(nlmixr2nn)`) before building or fitting a model that uses `nn()`. The package vignettes are `vignette("nlmixr2nn")` (how to use it) and `vignette("nlmixr2nn-node")` (how it relates to the neural-ODE literature).

## Estimate with a gradient-based method

**If the model contains `nn()`, fit it with a gradient-based estimator.** Weights are trained from exact forward sensitivities (`d(state)/d(weight)` integrated with the ODE). What matters is a gradient on the **inner** step, where the etas and the weight gradient are computed. The outer optimizer matters less: FOCEi's default `outerOpt = "bobyqa"` is fine and can do better than a gradient outer optimizer.

| Model | Use | Avoid |
|---|---|---|
| Has etas | `"focei"` first; `"laplace"`/`"agq"`, `"impmap"`, and the variational `"vae"`, `"emvi"`, `"fbvi"` also work | `"saem"`, `"imp"`, `"qrpem"`, `"npag"`/`"npb"` |
| No etas | a population estimator with gradients: `"lbfgsb3c"`, `"nlminb"`, `"n1qn1"`, `"nlm"` | derivative-free `"bobyqa"`, `"newuoa"`, `"uobyqa"` |

Why:

- The recommended methods all estimate each subject's etas with gradients, and that inner step is what the weight gradient rides on. FOCEi, `laplace`/`agq` and `impmap` use a MAP (conditional-mode) step; `vae`/`emvi`/`fbvi` optimize a variational objective by gradient. `impmap` centers its importance sampler on that MAP estimate; plain `imp` does not, so use `impmap`. nlmixr2nn runs both in joint mode; the preference is statistical, not a package restriction.
- With the FOCEi family, `impmap` and the variational methods (including `vae`), nlmixr2nn interleaves network training with the population fit (`nnControl(mode = "joint")`), because their outer iteration resumes from where it stopped. FOCEi's inner step already needs `d(pred)/d(eta)`, a forward solve that uses the same model Jacobian the weight gradient does.
- SAEM, `qrpem` and the nonparametric methods cannot resume a partial fit: SAEM restarts its stochastic-approximation gain sequence on every call. So nlmixr2nn alternates full inner fits with weight updates (`mode = "iter"`), which is slower and converges less well. On the nlmixr2nn vignette's UDE example, FOCEi reached an objective of −77.5 and recovered the latent eta (|r| = 0.998). SAEM on the same model and data ended at +15471.
- With no etas there is no inner step, so the population estimator itself must use the gradient, which it gets from the analytic weight sensitivities. On the vignette's no-BSV example, `lbfgsb3c` reached an objective of −176.1 in 2 s and `nlminb` −175.8 in 8 s. The derivative-free `bobyqa` stopped at −169.0 after 8 s.

Pass a population-only optimizer to a model **with** an eta and the fit errors rather than training the weights and the OMEGA against two different objectives.

## A UDE: learn a term you do not know

Keep the trusted mechanism and let a small network absorb the unknown part. Here elimination is known only to be a bounded rate that depends on the amount and varies between subjects; the latent eta enters the network as an input.

```r
library(nlmixr2)
library(nlmixr2nn)

rxode2::rxSetSeed(1)   # pins the network's initial weights
set.seed(1)            # pins the simulated data
truth <- rxode2::rxode2("d/dt(centr) = -(2*exp(eV))*centr/(3+centr)")
etaTrue <- rnorm(8, 0, sqrt(0.15))
d <- do.call(rbind, lapply(1:8, function(id) {
  s <- rxode2::rxSolve(truth,
         data.frame(id = id, time = c(0, .5, 1, 2, 4, 6, 8, 10),
                    evid = c(1, rep(0, 7)), cmt = 1, amt = c(10, rep(0, 7))),
         params = c(eV = etaTrue[id]), returnType = "data.frame")
  s <- s[s$time > 0, ]
  data.frame(id = id, time = c(0, s$time), evid = c(1, rep(0, nrow(s))), cmt = 1,
             amt = c(10, rep(0, nrow(s))), dv = c(NA, s$centr + rnorm(nrow(s), 0, .1)))
}))

ude <- function() {
  ini({ add.sd <- 0.3; eta.nn ~ 0.2 })
  model({
    g <- nn(centr, eta.nn, nHidden = 3, act = "tanh")
    d/dt(centr) <- -(1 / (1 + exp(-g))) * centr    # a bounded learned rate
    centr ~ add(add.sd)
  })
}

fitUde <- nlmixr2(ude, d, est = "focei", foceiControl(print = 0))
fitUde$objf
cor(fitUde$eta$eta.nn[order(fitUde$eta$ID)], etaTrue)   # sign is arbitrary; |r| matters
nnEval(fitUde, centr = seq(0.5, 10, length.out = 5), eta.nn = 0)
```

No setup step: `nlmixr2()` detects the `nn()` term and trains it. rxode2 warns that `eta.nn` is "non-mu referenced". That is expected for an eta used as a network input; leave the model as it is. The data is not touched. With the seed set, the fit above takes about 1.5 minutes.

## A learned covariate relationship

The same pattern with covariates as inputs. The network learns how they drive a parameter, and the latent eta carries what they do not explain:

```r
library(nlmixr2nn)

rxode2::rxSetSeed(42)
nnCl <- function() {
  ini({
    tka <- log(1.57); label("Ka")
    tcl <- log(2.72); label("Cl")
    tv  <- log(31.5); label("V")
    eta.ka ~ 0.6
    eta.v  ~ 0.1
    eta.nn ~ 0.1
    add.sd <- 0.7
  })
  model({
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + nn(WT, eta.nn, nHidden = 3))  # learned WT effect + latent BSV on cl
    v  <- exp(tv  + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
fitCov <- nlmixr2(nnCl, data, est = "focei", foceiControl(print = 0))
nnEval(fitCov, WT = seq(50, 90, by = 10), eta.nn = 0)   # the learned log-scale WT effect
```

More covariates are more inputs: `nn(WT, EGFR, eta.nn)`.

The network has its own output bias, so a THETA added to it (`tcl` here) is only weakly identified. The two trade off, and `tcl` can drift a long way from its initial value while `cl` stays the same. Interpret `cl` (or `nnEval()`), not `tcl`.

## A model with no between-subject variability

Systems-pharmacology models are often one mechanistic system with no etas. Fit them with a population estimator that uses gradients. These currently support only an untransformed `add()` / `prop()` endpoint. For `lnorm()`, `pois()` or `binom()` on a no-eta model, use `"focei"`, which fits a no-eta model as a population fit:

```r
library(nlmixr2nn)

rxode2::rxSetSeed(1)
set.seed(1)
qspTruth <- rxode2::rxode2("d/dt(centr) = -(2)*centr/(3+centr)")
qd <- do.call(rbind, lapply(1:6, function(id) {
  s <- rxode2::rxSolve(qspTruth,
         data.frame(id = id, time = c(0, .5, 1, 2, 4, 6, 8, 10),
                    evid = c(1, rep(0, 7)), cmt = 1, amt = c(10, rep(0, 7))),
         returnType = "data.frame")
  s <- s[s$time > 0, ]
  data.frame(id = id, time = c(0, s$time), evid = c(1, rep(0, nrow(s))), cmt = 1,
             amt = c(10, rep(0, nrow(s))), dv = c(NA, s$centr + rnorm(nrow(s), 0, .1)))
}))

qsp <- function() {
  ini({ add.sd <- 0.3 })                     # residual error only -- no eta
  model({
    g <- nn(centr, nHidden = 3, act = "tanh")
    d/dt(centr) <- -(1 / (1 + exp(-g))) * centr
    centr ~ add(add.sd)
  })
}

qspFit <- nlmixr2(qsp, qd, est = "lbfgsb3c")
qspFit$objf

## the fitted model reproduces dynamics it was never told about
nd <- data.frame(time = c(0, .5, 1, 2, 4, 6, 8, 10), evid = c(1, rep(0, 7)),
                 cmt = 1, amt = c(10, rep(0, 7)))
fitted <- rxode2::rxSolve(qspFit$finalUi, nd, returnType = "data.frame")
true   <- rxode2::rxSolve(qspTruth, nd, returnType = "data.frame")
data.frame(time = fitted$time, fitted = fitted$centr, true = true$centr)
```

## Before and after fitting

- **Simulate first.** The weights are drawn when the model is parsed, with rxode2's threefry generator. `rxode2::rxSetSeed()` therefore reproduces a network exactly, and an unfitted model solves straight away: `rxode2::rxSolve(rxode2::rxode2(ude), ev)`. Use this to check that the model behaves before fitting it.
- **Inspect what the network learned.** `nnEval(fit, <input> = grid, ...)` evaluates the network at chosen inputs. `plot()` draws the result, and `plot(e, true = f)` overlays a reference curve. `nnWeights(fit$finalUi)` returns the weight vector. Fits can converge with an objective that looks fine while the learned shape is implausible, so always look at the shape.
- **Save and warm-start.** The trained weights are carried on the fit, so a saved fit reloads and re-solves in a fresh session (`rxSolve(fit$finalUi, ...)`). Passing a fit back to `nlmixr2()` resumes from its trained weights: `nlmixr2(fitUde, moreData, "focei")`.
- **Check that THETA and OMEGA moved.** In the default joint mode, the current nlmixr2nn can return a fit whose THETAs and OMEGA are exactly their initial values: the weights trained, the population parameters did not. Compare `fit$theta` / `fit$omega` with the `ini({})` values. If they are identical, refit with `nn = nnControl(mode = "iter")`, which re-estimates them each round.
- **OFV stays comparable.** `fit$objf`, AIC and BIC are the unpenalized −2LL, even with regularization on. A network model can be compared directly with one using an analytic covariate or elimination term.

## Steering the training — `nnControl()`

The training schedule is inferred from the estimator, the random effects and the residual model. `nnControl()` overrides only what you set, and is passed as `nn =` next to the usual control:

```r
fitUde2 <- nlmixr2(ude, d, est = "focei", foceiControl(print = 0),
                   nn = nnControl(rounds = 400, lr = 0.01))
```

| Setting | Inferred as | Override when |
|---|---|---|
| `mode` | `"joint"` for estimators that resume (focei, laplace/agq, impmap, vae/emvi/fbvi), else `"iter"` | you want fully converged inner fits each round |
| `rounds` | 200 joint, 30 iterative, 60 for a no-eta model under `focei`; for `lbfgsb3c`/`nlminb`/... an iteration cap of 5 × #weights (50–500) | the message says training stopped at the round limit while the weights were still moving |
| `lr`, `optimizer` | 0.03 (0.01 on a refit), Adam | the objective oscillates or moves too slowly |
| `warmStart` | an `lbfgsb3c` population (eta = 0) pre-fit, skipped when the model already carries trained weights | you want a longer or shorter pre-fit |
| `l2`, `smooth` | 0 | a learned curve looks wigglier than the data can justify |
| `kinetic` | 0 | the learned term is stiff, or the augmented solve is slow |

The regularizers are fractions of the objective, so one value means roughly the same thing on any dataset. `l2` is ridge / weight decay and prefers a small network. `smooth` penalizes curvature along each input, so a monotone slope costs nothing. `kinetic` penalizes how hard the network pushes along the solved trajectory, which also makes the ODE easier to integrate. Start around 0.05 and check `nnEval()` afterwards: a penalty strong enough to remove invented structure also shrinks real effects. Biases and a latent eta's input weights are never penalized.

## What is supported

- **Inputs:** 1 to 4 per network, given positionally: states, covariates, or a latent eta.
- **Activations:** `act = "softplus"` (default; smooth, with a nonzero second derivative, which matters because the FOCEi sensitivities are chained through it), `"tanh"`, `"relu"`, `"gelu"`, `"silu"`.
- **Depth:** one hidden layer. `nHidden` (default 5) is a single width, and a vector is refused. Keep networks small: sensitivity cost grows as states × weights, and sparse clinical data cannot support a 32-wide network.
- **Networks per model:** several; they are trained together, and `nnEval(net = )` selects one.
- **Endpoints:** one. Any normal residual model (`add()`, `prop()`, both, `lnorm()`), or the counts `pois()` and `binom()`. The population estimators (no etas) accept only untransformed `add()`/`prop()`. For a count endpoint the parameter must be positive by construction (`lam <- exp(nn(...))`). For `binom(n, p)`, take `n` from a data column (`n <- ntrials`), because the compiler folds away a bare constant. Other distributions are refused with a reason.

## Augmented neural ODEs (by hand)

A one-state UDE such as `d/dt(centr) <- -f(nn(centr))` cannot represent crossing trajectories, whatever the fit. That is the neural-ODE non-crossing limit. Passing a latent eta or covariates into `nn()` separates subjects but adds no dynamic dimension. For a real augmented dimension, write an extra compartment yourself, and make it **relax** (`- a1`), or it runs away:

```r
library(nlmixr2nn)

aug <- function() {
  ini({ add.sd <- 0.3 })
  model({
    cmt(centr)                            # keep the dosed compartment as cmt = 1
    g           <- nn(centr, a1)
    d/dt(a1)    <- nn(centr, a1) - a1     # the augmented dimension, relaxing toward nn()
    d/dt(centr) <- -(1 / (1 + exp(-g))) * centr
    centr ~ add(add.sd)
  })
}
rxode2::rxode2(aug)$state                 # "centr" "a1"
```

rxode2 numbers compartments by first appearance. Without the `cmt(centr)` line, `a1` would become compartment 1, and `cmt = 1` in the data would dose the latent state instead of `centr`.

## Pitfalls

| Symptom | Cause / fix |
|---|---|
| SAEM fit of an `nn()` model has a huge OFV or never settles | Wrong family: refit with `"focei"` |
| "training stopped at the round limit ... raise nnControl(rounds=)" | Training had not converged; raise `rounds` and refit from the fit (warm start) |
| THETA next to `nn()` drifts far from its initial value | Confounded with the network bias; interpret the parameter or `nnEval()`, not that THETA |
| `fit$theta` / `fit$omega` equal the `ini({})` values exactly | Joint training updated only the weights; refit with `nnControl(mode = "iter")` |
| Latent eta correlates *negatively* with the true effect | The network's sign is arbitrary; only the magnitude of the correlation matters |
| Every prediction is 0 after adding a latent compartment | The augmented `d/dt()` took `cmt = 1`; declare the dosed compartments first with `cmt(name)` |
| `pois()` fit aborts | Rate went negative; use `lam <- exp(nn(...))` |
| Learned curve is wiggly | Over-capacity: shrink `nHidden`, or use `nnControl(smooth = 0.05)` / `l2 = 0.05` |
