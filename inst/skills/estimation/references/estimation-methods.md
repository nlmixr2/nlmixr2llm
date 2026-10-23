# Estimation methods — choosing `est=`

**The model decides the family.** A model with at least one eta (`eta.cl ~ 0.1`) is a *mixed-effects* model; a model with none is a *pooled* (fixed-effects-only) model. Each method accepts only one kind and errors otherwise ("needs to be a mixed effect model" / "can only have population estimates, try 'focei'").

**Quick pick — count the etas.** The structure of the between-subject variability matters more than the complexity of the structural model. `saem` does better with **many** etas; `focei` does better with **few**. Both support generalized `ll()` likelihoods. Use a pooled optimizer when there are no etas.

**Neural networks override the eta count.** A model with an `nn()` term (nlmixr2nn) needs a method with gradients on the inner step: `"focei"` (or `laplace`/`agq`, `impmap`, `vae`/`emvi`/`fbvi`) with etas; the default `bobyqa` outer optimizer is fine. Without etas, use a population estimator with gradients (`"lbfgsb3c"`, `"nlminb"`, `"n1qn1"`), not a derivative-free one. SAEM, `imp` (no MAP step), `qrpem` and `npag`/`npb` train the network poorly. See `neural-networks.md`.

List everything registered in the session, grouped by category:

```r
nlmixr2est::nlmixr2AllEstType()
```

## Mixed-effects methods (need >= 1 eta)

| Category | `est=` | Notes |
|---|---|---|
| Linearized | `"focei"` | Gradient-based; best with few etas; covariance `"r,s"`; sensitive to initial estimates and stiffness |
| | `"foce"`, `"focep"` | No interaction; `focep` (FOCE+) keeps the residual variance at the conditional eta |
| | `"fo"`, `"foi"` | First order (with interaction); legacy comparison |
| | `"nlme"` | Wraps `nlme` (Lindstrom–Bates); simple problems |
| Integral approximation | `"laplace"` | Laplace (= AGQ with one node) |
| | `"agq"` | Adaptive Gauss–Hermite quadrature (`nAGQ`); only for models with few etas |
| | `"imp"`, `"impmap"` | Importance-sampling EM (NONMEM `IMP`); `impmap` centers the proposal at the MAP; covariance `"imp"` |
| Stochastic EM | `"saem"` | Best when there are many etas. Reports SEs (`covMethod = "sa"`); the -2LL is computed by Gaussian quadrature on first access to `fit$objf` or calculated by focei when cwres items are added |
| | `"qrpem"` | Quasi-random parametric EM (Sobol samples + SIR M-step) |
| Nonparametric | `"npag"`, `"npb"` | Adaptive grid / nonparametric Bayes for multimodal eta distributions; support points in `fit$npagSupport` |
| Variational / ML | `"emvi"`, `"fbvi"` | Variational inference, EM-optimized or full-Bayes with flat priors; covariance `"vi"` |
| | `"vae"` | Variational autoencoder (LSTM encoder, ELBO) with simultaneous covariate selection (`vaeControl(covSelectMethod = )`) |
| Empirical Bayes | `"posthoc"` | Freezes THETA/OMEGA and computes ETAs (MAP) for the given data |

**Variant names.** The FOCEi-family (`foce*`, `laplace`, `agq`) and nonparametric names take an `m` prefix (mu-referenced closed-form regression, `muModel = "lin"`) or an `i` prefix (mu-referenced IRLS, `muModel = "irls"`). **The `i` means IRLS, not interaction.** An `f` suffix forces the analytic fast outer gradient (`foceiControl(fast = TRUE)`); `flaplace`/`fagq` also use the full conditional Hessian (Gaussian endpoints only). Examples: `mfocei`, `ifoceif`, `mlaplace`, `iagqf`, `mnpag`, `inpb`. Start with the base method and switch to a variant for speed.

**Outer optimizer.** `foceiControl(outerOpt = )` defaults to **`bobyqa`**. Under `fast = TRUE` (and every `*f` method) a defaulted `outerOpt` switches to the gradient-based `lbfgsb3c`; an explicit choice is kept. Alternatives include `nlminb`, `lbfgsb3c`, `L-BFGS-B`, `uobyqa`, and `newuoa`.

**Mixtures** via `mix()` are supported for `laplace`, `agq`, `focei`, `foce`, `foi`, `saem`, `imp`, `vae`, and `fo`.

Methods from other packages (load the package first):

| `est=` | Package | Notes |
|---|---|---|
| `"nlmer"`, `"saemix"`, `"nonmem"`, `"monolix"`, `"pknca"` | babelmixr2 | see the `interop` skill (`references/babelmixr2-backends.md`) |
| `"nuts"` (= `"stan"`), `"advi"`, `"pathfinder"` | nlmixr2bayes | Stan-based Bayesian fits; a model with no `prior()` lines is refused, and unset parameters get weak defaults (see `references/priors.md`) |

## Pooled methods (no etas)

`"focei"` still works on a model with no etas (population likelihood). So do the NLM-family optimizers, which use rxode2 sensitivities for exact gradients:

| `est=` | Notes |
|---|---|
| `"nlm"`, `"nlminb"`, `"n1qn1"`, `"trust"`, `"lbfgsb3c"` | Gradient optimizers |
| `"bobyqa"`, `"newuoa"`, `"uobyqa"` | Derivative-free (bounded / unbounded) |
| `"optim"` | `stats::optim`; shortcuts `"neldermead"`, `"bfgs"`, `"cg"`, `"lbfgsb"`, `"sann"`, `"brent"` |
| `"nls"` | Nonlinear least squares; simple models; its OFV is on a different scale from the others |
| `"fmeMcmc"`, `"pseudoOptim"` | babelmixr2: FME MCMC and global pseudo-random search (see the `interop` skill) |

```r
pooled <- function() {
  ini({
    tka <- log(1.57); tcl <- log(2.72); tv <- log(31.5)
    add.sd <- 0.7
  })
  model({
    ka <- exp(tka); cl <- exp(tcl); v <- exp(tv)
    linCmt() ~ add(add.sd)
  })
}
fitPooled <- nlmixr2(pooled, theo_sd, est = "nlminb", control = nlminbControl(print = 0))
fitPooled$parFixed
```

Pass the control that matches `est=` (`nlmControl()`, `nlminbControl()`, `bobyqaControl()`, `optimControl()`, ...). A control alone implies its method.

## Covariance step

`fit$cov` covers every estimated parameter: thetas, residual error, and omega (named `om.eta.cl`, `cov.eta.cl.eta.v`). `fix()`ed, IOV, and mixture-probability parameters are excluded. Choose the method with `covMethod =` in the control, or switch a finished fit without refitting (results are cached):

| Token | Covariance |
|---|---|
| `"r,s"` | sandwich; FOCEi-family default (`"r"` / `"s"` for either half) |
| `"analytic"` | exact observed information (NONMEM `MATRIX=R`, but exact) |
| `"sa"` | SAEM Louis stochastic approximation; SAEM default, usable on any mixed-effects fit |
| `"imp"` | importance-sampling observed information; imp/impmap/qrpem/npag/npb default |
| `"vi"`, `"nlme"`, `"linFim"`/`"fim"` | emvi/fbvi only; nlme only; saem only |
| `""` | skip |

`setCov(fit, "analytic")` recomputes and switches. A method that cannot be computed for a fit errors and leaves the current covariance in place. If two methods disagree on an SE, find out why before reporting it.
