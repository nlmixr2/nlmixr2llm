# PopED recipes via babelmixr2

Each recipe starts from a babelmixr2 PopED database `db` built as in `SKILL.md`. The complete, runnable versions are the ported PopED examples in `system.file("poped", package = "babelmixr2")`; the file for each recipe is named below.

## Ds-optimal: care about a subset of parameters (`ex.2.e.warfarin.Ds`)

Declare the parameters that matter; the rest become nuisance parameters in the criterion:

```r
db_ds <- nlmixr2(warf, e, "poped",
                 popedControl(groupsize = 32, minxt = 0, maxxt = 120, a = c(DOSE = 70),
                              important = c("tCl", "tV", "tKA")))   # or unimportant = c(...)
```

`evaluate_design()` still reports every RSE, but its `$ofv` becomes the Ds criterion (not comparable to a D-optimal `$ofv`), and that is what `poped_optim()` maximizes.

## ED-optimal: robust to uncertainty in the assumed values (`ex.2.d.warfarin.ED`)

Give the fixed effects a distribution instead of a point value, then evaluate or optimize the expected criterion:

```r
bpop <- db$parameters$bpop                      # rows = parameters; columns = distribution, value, variance
for (n in c("tCl", "tV", "tKA")) {
  bpop[n, ] <- c(4, bpop[n, 2], (bpop[n, 2] * 0.1)^2)   # 4 = log-normal (1 = normal), 10% SD
}
db_ed <- babel.poped.database(db, bpop = bpop, ED_samp_size = 20)

evaluate_design(db_ed, d_switch = FALSE, ED_samp_size = 20)   # Monte Carlo E(ln det FIM); noisy
evaluate_design(db_ed, d_switch = FALSE, use_laplace = TRUE)  # Laplace approximation; deterministic
poped_optim(db_ed, opt_xt = TRUE, method = "LS", d_switch = FALSE, use_laplace = TRUE)
```

Increase `ED_samp_size` for a more accurate Monte Carlo estimate.

## Prior information and power (`ex.11.PK.prior`)

Use a previous study's FIM as prior information for a new one, such as adults informing a pediatric design:

```r
outAdult <- evaluate_design(db_adult)                          # FIM of the earlier design
db_all   <- babel.poped.database(db_ped, prior_fim = outAdult$fim)
out_all  <- evaluate_design(db_all)

# power to show a covariate effect differs from 1, and the sample size needed
evaluate_power(db_all, bpop_idx = babelBpopIdx(db_all, "pedCL"), h0 = 1, out = out_all)
```

Both databases must define the shared parameters (here `pedCL`). `evaluate_power()` reports the predicted power, the RSE needed for the requested power, and the minimum total N.

## Covariate distributions (`ex.12.covariate.distributions`)

A single `a = c(WT = 70)` treats everyone as 70 kg, which can make covariate effects look unestimable (RSE 0). Instead, give each individual their own covariate value as a one-subject group:

```r
db_wt <- nlmixr2(f_wt, e, "poped",
                 popedControl(groupsize = 1, m = 50, minxt = 0, maxxt = 24, bUseGrouped_xt = TRUE,
                              a = lapply(rnorm(50, mean = 70, sd = 10), function(x) c(WT = x))))
evaluate_design(db_wt)$rse
```

Repeat this over several random draws and summarize the RSE quantiles, since one draw of 50 weights is itself random.

## Multiple groups and multiple responses (`ex.3`, `ex.10`)

- **Groups:** keep a single `id` in the design table and give one `a` entry per group, `popedControl(groupsize = 32, a = list(c(DOSE = 20), c(DOSE = 40)))`. `m` is inferred from `a`, and the scalar `groupsize` applies to each group.
- **Responses:** stack a design table per endpoint with an integer `dvid` (1 = PK, 2 = PD); babelmixr2 passes it to PopED as `model_switch`.

## Shrinkage (`ex.13.shrinkage`)

`shrinkage(db)` returns the expected eta shrinkage per group on the variance scale (`shrink_var`), the SD scale (`shrink_sd`), and the expected SE of the ETAs. High expected shrinkage means individual ETAs, and ETA-based diagnostics, will be unreliable under that design.
