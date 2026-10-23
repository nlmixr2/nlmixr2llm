# babelmixr2 — in-R backends, and debugging read-back

Besides NONMEM, Monolix, and PKNCA, babelmixr2 registers backends that route the same nlmixr2 model function to other R packages. No external software is needed.

| `est=` | Model type | What babelmixr2 does |
|---|---|---|
| `"nlmer"` | mixed-effects | Fits with `lme4::nlmer` (Laplace), using analytic gradients from rxode2 sensitivities; mu-referenced or not. Raw fit in `fit$nlmer`; `nlmerControl(returnNlmer = TRUE)` returns it directly |
| `"saemix"` | mixed-effects | Fits with the `saemix` package's SAEM (`saemixControl()`); raw fit in `fit$saemix`. **Currently needs an ODE model with an eta on every structural theta**: `linCmt()` models and thetas without etas fail ([babelmixr2#212](https://github.com/nlmixr2/babelmixr2/issues/212)) |
| `"fmeMcmc"` | pooled (no etas) | MCMC with `FME::modMCMC()`; priors go in `fmeMcmcControl(prior = )`, not `ini()`. `coda::as.mcmc(fit)` gives the chain; set `seed=` for reproducibility |
| `"pseudoOptim"` | pooled (no etas) | Global pseudo-random search with `FME::pseudoOptim()` (`pseudoOptimControl()`). **Every** parameter needs finite bounds in `ini()`: `tcl <- c(-5, 1, 5)` |
| `"poped"` | mixed-effects | Not a fit: builds a PopED database for optimal design (see the `design` skill) |

A method run on the wrong model type errors clearly ("needs to be a mixed effect model" / "can only have population estimates, try 'focei'"). **No babelmixr2 method accepts `prior()` lines in `ini()`**; the fit is refused rather than run without them.

## Optimal design with PopED

`est = "poped"` builds a PopED database instead of fitting. Optimal design is its own task: see the `design` skill.

## `runCommand` and control details

- `runCommand` can be a function, called as `FUN(ctl, directory, ui)`; babelmixr2 waits for it to return. Use it for cluster submission, returning once the output files exist.
- `runCommand = NA` makes `nlmixr()` stop after writing the engine input, without running anything.
- Key `nonmemControl()` arguments: `est` (`"focei"`, `"imp"`, `"its"`, `"posthoc"`), `cov` (`"r,s"`, `"r"`, `"s"`, `""`), `sigdig`/`sigl` (`$EST` precision), `maxeval`, `advanOde` (`"advan13"`, `"advan8"`, `"advan6"`) with `tol`/`atol` (ODE solver tolerances), and `readRounding`.

## When a babelmixr2 fit looks wrong

babelmixr2 does **not** run the backward *model* translation after a run, because it already knows the original nlmixr2 model. It does use nonmem2rx's and monolix2rx's low-level readers (`nonmem2rx::nminfo()`, `nmext()`, `nmtab()`, `nmcov()`, and monolix2rx's project parser) to pull estimates, covariance, and tables off disk and attach them to the model it already has.

So suspect result reading or engine convergence rather than model translation. Load the same run with `nonmem2rx()` / `monolix2rx()` and call `babelmixr2::as.nlmixr2()` on the result, an independent path to the same run:

- **It converts and qualifies cleanly:** the fault is in babelmixr2's reading.
- **It fails to qualify as well:** the model uses a construct the rxode2 translation cannot reproduce. That is a limitation of the import path, *not* evidence that the engine output is bad.

Whether the engine run itself converged is a third question, answered by its listing or `summary.txt`, not by the qualification diff.
