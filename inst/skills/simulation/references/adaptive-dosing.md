# Adaptive dosing — dose rules evaluated during the solve

When the dose depends on the simulated trajectory (titration, dose holds and reductions, rescue, TDM), it cannot be written into `et()`. Put the rule in `model({})` and push the event while solving (rxode2 >= 5.1.1; 5.1.7 or later recommended, which unified and fixed the event push):

| Helper | evid | Pushes |
|---|---|---|
| `bolus(amt, cmt, ii, addl, ss)` | 1 | a bolus |
| `infuse(amt, rate, cmt, ...)` / `infuseDur(amt, dur, cmt, ...)` | 1 | fixed-rate / fixed-duration infusion |
| `reset()` / `replace(amt, cmt)` / `multiply(f, cmt)` | 3 / 5 / 6 | reset all states / set / scale a compartment |
| `phantom(amt, cmt)` | 7 | transit bookkeeping (`tad()`, `podo()`) without mass |
| `obs(dt1, dt2, ...)` | 0 | extra observation rows |
| `evid_(...)` | any | low-level interface |

## Pipe the protocol onto the model or fit

Add the rule by piping instead of rewriting the PK/PD. The model that was fit, qualified, or published stays exactly as it was:

```r
tdm <- fit |>                                 # an nlmixr2 fit or any rxode2 model
  model({
    rescueAmt <- rescue                       # the dose amount must be a plain symbol assigned in model()
    if (t > 0 && t %% 24 == 0 && cp < target) {
      bolus(rescueAmt, cmt = depot)
    }
  }, append = TRUE, auto = FALSE) |>          # append after the residual line; don't auto-classify new symbols
  ini(target <- 3, rescue <- 160)             # protocol-only parameters

all.equal(tdm$theta[names(fit$theta)], fit$theta)   # TRUE: estimates untouched

set.seed(42); rxode2::rxSetSeed(42)
sim <- rxSolve(tdm, et(amt = 320, cmt = "depot") |> et(time = seq(0, 96, by = 1)),
               nSub = 50, maxExtra = 500)
```

Compare protocols by piping different rules onto the same base model, or vary a rule's thresholds with `params = c(target = 2)`.

## Protocol memory: sticky variables

For multi-rule protocols (dose levels, holds, reassessment), keep the protocol's memory in **sticky** variables. These are LHS variables that start `NA` for each subject and keep their last value between records:

```
if (is.na(level)) {        # first record of each subject
  level   <- 1
  nextDue <- 21*24
}
if (t > 0 && t %% 168 == 0 && t >= nextDue) {
  if (anc >= 1.5) {
    infuseDur(doseMg, 1, central)
    nextDue <- t + 21*24
  } else {
    nextDue <- t + 7*24    # hold a week and reassess
  }
}
```

## Rules that bite

- **Decisions only run at times the solver visits.** Put assessment times in the event table, or pin them with `mtime(check48) <- 48`. `mtime(48)` does not parse.
- **Anchor standing conditions.** `cp < target` is true for many rows, so tie it to a visit (`t %% 24 == 0`) and skip `t == 0`, or it fires every row.
- **Dose amounts must be symbols**: `doseMg <- mgm2*bsa`, then `infuseDur(doseMg, ...)`.
- **Set `maxExtra`** so a runaway rule errors instead of pushing thousands of events. An event pushed at the last output time never happens, but sticky assignments on that row still do.
- The event table can hold only observations when the model pushes every dose (including the first at `t == 0`).
- `linCmt()` models work too, and `odeToLin()` converts a linear ODE model while keeping its adaptive calls.

## References (rxode2 repo)

- `vignettes/articles/adaptive-dosing.Rmd` — every helper, `mtime()`, `obs()`, `evid_()`
- `vignettes/articles/rxode2-sticky.Rmd` — sticky variables (protocol memory, running Cmax/Tmax)
