# Base structural model exploration

Model building runs in five steps:

1. Explore the data.
2. **Choose the base structural model** (this file).
3. Build the stochastic model: which parameters get etas, OMEGA blocks, residual error.
4. Build the covariate model.
5. Evaluate the final model.

Steps 3–5 are in `model-building.md`.

The structure is the compartments, absorption, elimination, and for PD the link to drug exposure. Settle it before anything else: covariates and OMEGA blocks fitted on the wrong structure end up absorbing its misfit.

The procedure is an iterative propose–fit–diagnose loop, adapted from AgentODE (Yang et al. 2026, arXiv:2607.00733). You propose structures, a deterministic fit and score judge them, a structured diagnosis decides the next change, and a log stops you repeating failures. Unlike AgentODE, the parameters come from a real NLME fit, not from LLM reasoning, so each candidate is scored at its maximum likelihood.

## 1. Read the shape of the data

Summarize before proposing anything, and write down what each feature implies:

```r
library(ggplot2)
obs <- data[data$EVID == 0, ]
obs$bin <- cut(obs$TIME, unique(quantile(obs$TIME, seq(0, 1, 0.125))), include.lowest = TRUE)
summ <- do.call(rbind, lapply(split(obs, obs$bin), function(d) {
  m <- mean(d$DV); se <- sd(d$DV) / sqrt(nrow(d))
  data.frame(time = median(d$TIME), mean = m, lo = m - 1.96 * se, hi = m + 1.96 * se, n = nrow(d))
}))
summ
ggplot(obs, aes(TIME, DV, group = ID)) + geom_line(alpha = 0.4) +
  scale_y_log10() + labs(title = "Individual profiles, log scale")
```

| Feature in the data | Structural hypothesis |
|---|---|
| Log-scale decline bends: fast, then slow | add a peripheral compartment (2-cmt; 3-cmt if it bends twice) |
| Concentration still ~0 at the first samples after an oral dose; late or flat-topped peak | absorption delay: `addLag()`, transit chain `addTransit(n)`, or zero-order input |
| Double peaks | two absorption processes (`addSecondAbsorption()`) or enterohepatic recycling |
| Dose-normalized profiles do not overlay; half-life grows with dose | saturable elimination (`convertMM()`), or target-mediated disposition (`PK_*_tmdd_*`) |
| Effect lags concentration (hysteresis loop in effect vs. concentration) | effect compartment (`addEffectCmtLin()`) or indirect response (`addIndirect()`) |
| Effect saturates with exposure | Emax / Hill (`convertEmax()`, `convertEmaxHill()`) |
| Baseline drifts without drug | baseline model (`addBaselineLin()`, `addBaselineExp()`) |

## 2. Propose candidates

Propose **several** candidates per round: the incumbent, one change for each hypothesis above, and at least one candidate from a different structural family, so the search does not lock onto one branch. (AgentODE gets that diversity from separate search "islands"; one candidate from outside the leading family is the single-analyst equivalent.) Build them from nlmixr2lib starting models and edit functions where possible. Write an `ini()`/`model()` function only when the library cannot express the hypothesis.

### Automated search first, when the problem fits: nlmixr2auto

For single-endpoint PK with IV bolus or first-order oral dosing, run **nlmixr2auto** (Huang et al., UCL Pharmacometrics) before hand-proposing anything. It searches 1–3 compartments and linear vs. Michaelis–Menten elimination automatically:
- stepwise with `sf.operator()`;
- genetic algorithm with `ga.operator()`;
- ant colony with `aco.operator()`;
- tabu search with `tabu.operator()`.

Its companion **nlmixr2autoinit** derives initial estimates from the data, using naive-pooled NCA, graphical methods and parameter sweeps.

Initial estimates for hand-built candidates come from `getPPKinits()` (about 30 s on `theo_sd`):

```r
library(nlmixr2)
library(nlmixr2autoinit)
inits <- getPPKinits(data, verbose = FALSE)
est   <- inits$Recommended_initial_estimates           # Ka, CL, Vd, Vmax/Km, 2-/3-cmt volumes and Q, sigmas
v     <- setNames(as.numeric(est$Values), est$Parameters)   # Values is formatted text
cand  <- nlmixr2lib::readModelDb("PK_1cmt_des") |>
  ini(lka = log(v[["Ka"]]), lcl = log(v[["CL"]]), lvc = log(v[["Vd"]]))
```

The stepwise structural search limits itself to compartments and elimination with `steps = 12`. Steps 3–7 select IIV, correlations and residual error, which belong to the next model-building stage:

```r
library(nlmixr2auto)
auto <- sf.operator(dat = data, search.space = "oralbase", steps = 12,
                    foldername = "auto_sf", filename = "auto_sf",
                    saem.control = saemControl(seed = 1234, nBurn = 200, nEm = 300,
                                               logLik = TRUE, print = 0))
auto                                   # best model name and the stepwise history
auto[["Model Run History"]][, c("model.num", "AIC", "BIC", "OBJFV", "npar")]
```

On `theo_sd` this takes about 1.5 minutes and selects `oral_1cmpt_FO_abs_..._FOelim`, the 1-compartment linear model.

How to use the result:

- **Treat it as the incumbent, not the answer.** Its oral search space has first-order absorption only: no lag, transit, zero-order or dual absorption, no PD, no TMDD. On `theo_sd` the lag and transit structures in section 3 fit far better than anything it can propose. Continue the loop from its winner for everything outside its space.
- **Its OFVs are not comparable with the loop's.** It fits with SAEM and the eta structure of each step, so refit its winner under section 3's fixed stochastic model before ranking it against the other candidates.
- **Read its `fitness` column with care.** Fitness is BIC plus penalties from `penaltyControl()`: 10000 per parameter outside its bounds or per failed covariance step, and a two-level 10 / 10000 penalty for moderate / critical RSE, shrinkage, BSV and sigma deviations. A fitness in the tens of thousands means constraints were hit, not that the fit is bad.
- **Zero concentrations are dropped for initial estimates only.** `getPPKinits()`, and so the operators' automatic initial-estimate step, converts `DV = 0` observations to `EVID = 2` (excluded) and says so in a note. The operators' SAEM fits use the data as given. Decide how BLQ or zero records are handled (a `CENS` column) before running either.
- **Log its runs.** Add the run history (`auto[["Model Run History"]]`, also written to `<foldername>/<filename>.csv`) to `structure-log.csv` so the loop does not re-propose what it already tried. Its model files are left in `foldername` and can be read back for refitting.

## 3. Fit them identically, score, and log

A structural comparison is only fair when **everything except the structure is held fixed**:

- the same data;
- etas on the same core parameters;
- the same residual model;
- the same estimation method, so the OFVs are computed the same way.

Refining any of these belongs to step 3, after the structure is chosen.

The block below is a complete round on `theo_sd`. nlmixr2lib models dose into `depot` and observe in `central`, and adding compartments renumbers them. So name `CMT` in the data instead of relying on numbers: a numeric `CMT = 2` would point at `transit1` in the transit model.

```r
library(nlmixr2)
library(nlmixr2lib)

d <- data
d$CMT <- ifelse(d$EVID == 0, "central", "depot")    # name compartments; structures renumber them

base <- readModelDb("PK_1cmt_des")
cands <- list(
  oneCmt    = base,
  oneCmtLag = base |> addLag("depot"),
  oneCmtTr3 = base |> addTransit(3),
  twoCmt    = readModelDb("PK_2cmt_des")
)
## identical stochastic model for every candidate
cands <- lapply(cands, function(m) m |> addEta(c("ka", "cl", "vc")) |> addResErr("addSd"))
fits  <- lapply(cands, function(m) nlmixr2(m, d, est = "focei", foceiControl(print = 0)))

## MNSD-style discrepancy: AgentODE's normalized absolute discrepancy |s_obs - s_sim| / IQR_obs,
## applied here to VPC quantiles per time bin; bins with IQR < 0.01 are dropped, as AgentODE does
vpcDiscrepancy <- function(fit, n = 200, nBins = 8, probs = c(0.05, 0.5, 0.95), seed = 42) {
  obs <- as.data.frame(fit)[, c("TIME", "DV")]
  sim <- vpcSim(fit, n = n, seed = seed)
  breaks <- unique(quantile(obs$TIME, seq(0, 1, length.out = nBins + 1)))
  obs$bin <- cut(obs$TIME, breaks, include.lowest = TRUE)
  sim$bin <- cut(sim$time, breaks, include.lowest = TRUE)
  do.call(rbind, lapply(levels(obs$bin), function(b) {
    o  <- obs$DV[obs$bin == b]
    s  <- sim[sim$bin == b, ]
    qo <- quantile(o, probs, names = FALSE)
    qs <- apply(vapply(split(s$sim, s$sim.id), quantile, numeric(length(probs)), probs = probs),
                1, median)
    data.frame(bin = b, prob = probs, obs = qo, sim = qs,
               z = if (IQR(o) < 0.01) NA_real_ else abs(qo - qs) / IQR(o))
  }))
}

scoreStructure <- function(fit, name, change = "") {
  p    <- fit$parFixedDf
  free <- fit$iniDf[!fit$iniDf$fix, ]
  dz   <- vpcDiscrepancy(fit)
  w    <- if (all(is.na(dz$z))) NULL else dz[which.max(dz$z), ]   # which.max() skips NA
  data.frame(model = name, change = change, nPar = nrow(free),
             OFV = fit$objf, AIC = AIC(fit), BIC = BIC(fit),
             covOk = !anyNA(p$SE), maxRSE = if (all(is.na(p$SE))) NA_real_ else round(max(p$`%RSE`, na.rm = TRUE)),
             onBound = any(abs(free$est - free$lower) < 1e-4 | abs(free$est - free$upper) < 1e-4),
             vpcScore = round(mean(dz$z, na.rm = TRUE), 3),
             worst = if (is.null(w)) NA_character_ else sprintf("%s q%.0f", w$bin, 100 * w$prob))
}

changes <- c(oneCmt = "base", oneCmtLag = "+ lag on depot",
             oneCmtTr3 = "+ 3 transit cmts", twoCmt = "+ peripheral cmt")
round1 <- do.call(rbind, Map(scoreStructure, fits, names(fits), changes))
round1$round <- 1
round1[order(round1$AIC), ]

## the experience log: append every round, read it before proposing the next one
logFile <- "structure-log.csv"
write.table(round1, logFile, sep = ",", row.names = FALSE,
            col.names = !file.exists(logFile), append = file.exists(logFile))
```

On `theo_sd` this ranks the lag and transit structures first (OFV ≈ 74 against ≈ 117 for the base), with lower `vpcScore`. `twoCmt` does not improve the OFV, and its `maxRSE` in the thousands shows the peripheral compartment is unsupported.

**Ranking rules:**

- **Gates first.** A candidate with a non-finite OFV, a failed covariance step (`covOk = FALSE`), an estimate on a bound, or a `maxRSE` in the hundreds for a structural parameter is not a contender, however low its OFV.
- **Then the information criteria.** For nested structures (a lag added to the base), ΔOFV > 3.84 for one added parameter is significant at p = 0.05 (5.99 for two, 7.81 for three; χ² with df = the number added). A lag or transit nests the base only at a boundary (lag → 0), where the test is conservative, so AIC is the safer comparison there too. Compare non-nested structures (lag against transit) by AIC/BIC; differences under ~2 do not separate them.
- **`vpcScore` is a check on the ranking.** A lower OFV with a worse `vpcScore` means the likelihood improved somewhere the predictive distribution does not. Diagnose before accepting it. `worst` names the time bin and quantile that fits worst.
- **Prefer the simpler structure** when candidates tie, and the mechanistically plausible one over the flexible one.

## 4. Diagnose before the next round

Before proposing again, write a short structured report for the best candidate. Proposals that cite no evidence are guesses.

```text
Failure mode: under-predicted Cmax and early concentrations (0-1 h)
Severity:     vpcScore 0.24; worst bin [0,0.26] q5; CWRES trend < 0 before 1 h
Affected:     absorption phase only; elimination phase unbiased
Evidence:     CWRES vs TAD, VPC, augPred for IDs 1, 5, 9
Hypothesis:   input is delayed and then faster than first-order
Next change:  transit chain, n = 2, 3, 5 (vs. lag); keep everything else fixed
```

Use these diagnostics. FOCEi fits carry `CWRES`; for a SAEM fit, run `fit <- addCwres(fit)` first:

```r
library(ggplot2)
library(nlmixr2plot)
if (!"CWRES" %in% names(as.data.frame(fit))) fit <- addCwres(fit)   # SAEM fits lack CWRES
dg <- as.data.frame(fit)
ggplot(dg, aes(tad, CWRES)) + geom_point() + geom_smooth(se = FALSE) +
  geom_hline(yintercept = 0) + labs(title = "CWRES vs time after dose")
vpcPlot(fit, n = 200, show = list(obs_dv = TRUE))
plot(augPred(fit))
```

| Residual pattern | Structural change to try |
|---|---|
| CWRES biased early after an oral dose | lag, transit, or zero-order absorption |
| CWRES biased in the terminal phase | add a peripheral compartment |
| Bias grows with dose or exposure | nonlinear elimination (MM, TMDD) |
| PD residuals trend with time, not concentration | delay: effect compartment or indirect response |

## 5. Loop control

- **One structural change per candidate**, so each ΔOFV has a single cause.
- **Read the log before proposing.** Do not re-propose a change that already failed. Re-propose top-ranked structures with a further change, but always include one candidate from outside the leading family.
- **Budget**, borrowed from AgentODE's per-structure inner loop (its outer structure search is a budgeted evolutionary run of ~500 sampled structures): stop after 10 rounds, 20 while the best AIC is still improving, or after 5 consecutive rounds without improving the best gated candidate.
- **Hand off** the best gated structure to step 3, together with the log (`structure-log.csv`) as the record of what was tried and why it was rejected.

## 6. When no candidate fits: learn the term, then name it

If every library structure leaves the same systematic misfit, replace the suspect term with a neural network, fit it, look at what it learned, and translate that into a mechanistic expression. This is the NODE → distill workflow (Braem et al. 2026; `readModelDb("Bram_2026_warfarin_node")` is a fitted example, written out with explicit THETA weights rather than `nn()`, so `nnEval()` does not apply to it).

1. **Learn the term.** Write the UDE as in `neural-networks.md`: keep the trusted mechanism and let `nn()` of a **state** (plus a latent eta for BSV) stand in for the suspect term. Fit with FOCEi, not SAEM. Inputs that are functions of time did not train in our tests: `tad()` never moved the weights (nlmixr2nn issue #10), and `t` gave an OFV worse than the base model. Express a delay as an extra state instead (the augmented-compartment pattern in `neural-networks.md`).
2. **Read the shape.** Plot `nnEval(fit, <state> = grid, eta.nn = 0)` over the observed range. A per-amount rate that falls as the state rises means saturation (Michaelis–Menten); one that rises means cooperativity (Hill); a flat one means the linear term was right after all.
3. **Name it.** Fit the closed forms that match the shape under the same rules as section 3, and log them with `change = "distilled from UDE"`.
4. **Compare with the UDE's OFV.** A closed form within a few points of it has captured what the network found, with far fewer parameters. A closed form much *better* than the UDE means the network was under-trained. Check the UDE's `fit$theta` against its `ini()` values: the default joint mode can leave THETA/OMEGA unchanged (nlmixr2nn issue #9), so refit it with `nnControl(mode = "iter")`. A closed form much *worse* means the shape is not captured yet.

The UDE example in `neural-networks.md` learns a bounded elimination rate whose `nnEval()` value falls as `centr` rises, which is saturation. Naming it:

```r
library(nlmixr2)

## the same simulated data as the UDE example in neural-networks.md
set.seed(1)
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

mm <- function() {                              # the distilled shape: saturable elimination
  ini({ lvmax <- log(1); lkm <- log(1); add.sd <- 0.3; eta.vmax ~ 0.2 })
  model({
    vmax <- exp(lvmax + eta.vmax)
    km   <- exp(lkm)
    d/dt(centr) <- -vmax * centr / (km + centr)
    centr ~ add(add.sd)
  })
}
lin <- function() {                             # the structure the UDE replaced
  ini({ lk <- log(0.3); add.sd <- 0.3; eta.k ~ 0.2 })
  model({
    k <- exp(lk + eta.k)
    d/dt(centr) <- -k * centr
    centr ~ add(add.sd)
  })
}
fitMm  <- nlmixr2(mm,  d, est = "focei", foceiControl(print = 0))
fitLin <- nlmixr2(lin, d, est = "focei", foceiControl(print = 0))
c(mm = fitMm$objf, linear = fitLin$objf)
exp(fitMm$theta[c("lvmax", "lkm")])           # truth: vmax 2, km 3
```

Here Michaelis–Menten reaches OFV ≈ −175 and recovers the simulated Vmax ≈ 2 and Km ≈ 2.6 (true 3). Linear elimination reaches ≈ +18, and the default-mode UDE ≈ −78. The closed form beats the network because that UDE's residual SD stayed at its initial 0.3 (issue #9), which is exactly the check in step 4. Either way, the network is a diagnostic here, not the deliverable: report the distilled mechanistic structure.

## Scope

This procedure needs individual-level data. AgentODE's LLM never sees individual trajectories: its structure search and parameter inference work from precomputed population summary statistics (some computed per trajectory, then summarized), with a synthetic likelihood. That setting (for example, published means and CIs only) is not available in nlmixr2 yet.
