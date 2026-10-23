---
name: reporting
description: Use this skill when the user wants to evaluate or communicate the results of an nlmixr2 model fit — goodness-of-fit diagnostics (DV vs PRED/IPRED, residuals, ETA distributions, individual plots), visual predictive checks, augmented predictions, parameter-estimate tables, SAEM/FOCEi convergence traces, Word or PowerPoint reports via nlmixr2rpt / onbrand, R Markdown or Quarto write-ups, or interactive model review with shinyMixR. Triggers include `plot(fit)`, `vpcPlot()`, `augPred()`, `xpose_data_nlmixr2()`, `ggPMX` / `pmx_nlmixr()`, `report_fit()`, `fit$parFixed` "as a table", "make the GOF plots", "produce a report of this fit", "summarise the model for the team".
---

# Reporting — diagnostics, tables, and documents from an nlmixr2 fit

Reporting turns a fit into evidence: does the model describe the data, how precise are the parameters, and what does that look like in a document the team can read. The input is always an nlmixr2 fit object: from `nlmixr2()` directly, from babelmixr2 running NONMEM/Monolix, or from `babelmixr2::as.nlmixr2()` on an imported NONMEM/Monolix run (see the `interop` skill).

## Tool map

| Need | Use |
|---|---|
| Quick standard GOF set | `nlmixr2plot`: `plot(fit)` (list of ggplots), `nlmixr2plot::traceplot(fit)` |
| VPC | `nlmixr2plot::vpcPlot(fit, ...)`, `vpcPlotTad()`, `vpcCens()` for BLQ |
| Individual / population prediction overlays | `nlmixr2est::augPred(fit)` then `plot()` |
| Publication-style GOF with full control | `xpose.nlmixr2::xpose_data_nlmixr2(fit)` → xpose functions (`dv_vs_ipred()`, `res_vs_idv()`, `ind_plots()`, `eta_distrib()`, `prm_vs_iteration()`, ...) |
| Standardised GOF bundle + report template | `ggPMX::pmx_nlmixr(fit, conts=, cats=)` → `pmx_plot_*()`, `pmx_report()` |
| Parameter table | `fit$parFixed` (formatted) / `fit$parFixedDf` (numeric); `nlmixr2rpt::gen_pest_table()` for a flextable with labels |
| Word / PowerPoint report | `nlmixr2rpt::report_fit()` on an `onbrand` report object (`onbrand::read_template()` / `save_report()`; see `references/nlmixr2rpt.md`) |
| Interactive run management and review | `shinyMixR::run_shinymixr()` |

## Minimum viable example

```r
library(nlmixr2)
library(nlmixr2plot)                     # plot(fit), vpcPlot(), traceplot()

# fit <- nlmixr2(model, data, est = "saem", saemControl(print = 0))

print(fit)
fit$parFixed                              # estimates, SE, %RSE, back-transformed, BSV%, shrinkage
fit$objDf                                 # OFV, AIC, BIC (SAEM: NA until fit$objf has been accessed once)

plot(fit)                                 # standard GOF set: DV vs PRED/IPRED, residuals, individual fits
nlmixr2plot::traceplot(fit)               # SAEM / FOCEi parameter history (qualified: coda's traceplot() masks it)

vpcPlot(fit, n = 500, log_y = TRUE)       # VPC: 90% PI with 90% CIs on the percentiles (pi = ci = c(0.05, 0.95))
vpcPlot(fit, n = 500, pred_corr = TRUE, stratify = "DOSE")

ap <- augPred(fit)                        # smooth IPRED / PRED curves through the observations
plot(ap)
```

Every plot call above returns ggplot objects (or a list of them) that can be themed, faceted, and saved with `ggplot2::ggsave()`.

## Diagnostics checklist

Cover these before declaring a model adequate, and say which you looked at:

1. **Structure**: DV vs PRED and DV vs IPRED on linear and log scales; points around the identity line without a trend.
2. **Residuals**: CWRES (or NPDE) vs time and vs PRED; centred on zero, |CWRES| mostly < 3, no fan or trend. Add them with `addCwres(fit)` / `addNpde(fit)` if absent.
3. **Individuals**: individual plots for a sample of subjects, including the worst-fitting ones.
4. **Random effects**: ETA histograms / QQ plots and ETA-vs-covariate plots; report shrinkage (`fit$shrink`) and treat ETA-based conclusions as weak where shrinkage > ~30%.
5. **Predictive check**: VPC (prediction-corrected when doses or covariates vary) with binning appropriate to the sampling design; observed percentiles inside the simulated CIs.
6. **Convergence and precision**: `nlmixr2plot::traceplot(fit)` flat in the final phase; SEs present and %RSE reasonable; nothing on a bound.

## Publication-quality GOF with xpose

```r
library(xpose.nlmixr2)
xpdb <- xpose_data_nlmixr2(fit)           # adds CWRES if missing

dv_vs_ipred(xpdb); dv_vs_pred(xpdb)
res_vs_idv(xpdb, res = "CWRES"); res_vs_pred(xpdb, res = "CWRES"); absval_res_vs_pred(xpdb)
ind_plots(xpdb, page = 1)
eta_distrib(xpdb); eta_qq(xpdb)
prm_vs_iteration(xpdb)
```

xpose plots accept `type=` (points / lines / smooth), `facets=`, `log=`, `title=`, `subtitle=`, `caption=` and standard ggplot layering.

## Standardised bundle with ggPMX

```r
library(ggPMX)
ctr <- pmx_nlmixr(fit, conts = c("WT", "AGE"), cats = c("SEX"))
plot_names(ctr)                            # everything the controller can draw
ctr %>% pmx_plot_dv_ipred()
ctr %>% pmx_plot_eta_matrix()
ctr %>% pmx_plot_eta_conts()               # ETA vs continuous covariates
dir.create("reports", showWarnings = FALSE)  # save_dir must exist
pmx_report(ctr, name = "gof_report", save_dir = "reports", format = "word")
```

ggPMX 1.3.2 disables its VPC for nlmixr2 fits (`vpc = TRUE` warns and is ignored, `pmx_plot_vpc()` is not a VPC of the fit); use `nlmixr2plot::vpcPlot()` instead.

## Word and PowerPoint reports with nlmixr2rpt

```r
library(nlmixr2rpt); library(onbrand)
obnd <- read_template(
  template = system.file("templates", "nlmixr_obnd_template.docx", package = "nlmixr2rpt"),
  mapping  = system.file("templates", "nlmixr_obnd_template.yaml", package = "nlmixr2rpt"))
obnd <- report_fit(obnd = obnd, fit = fit)                  # default report_fit.yaml content
save_report(obnd, "fit_report.docx")
```

Swap the `.docx` template for `.pptx` to get slides from the same call. Report content (which figures / tables, captions, placeholders, covariates) is driven by a YAML file; copy `report_fit.yaml` from the package and pass it as `rptyaml=` to customise. Organisational templates plug in through `onbrand` mapping files. Full structure in `references/nlmixr2rpt.md`.

## Tables and text

- `fit$parFixedDf` → numeric data frame for `flextable` / `gt` / `knitr::kable`; `fit$parFixed` for a preformatted console table.
- `nlmixr2rpt::gen_pest_table(fit, obnd, rptdetails)` builds the parameter table with `label()` text, units, and CI columns as a flextable for Word/PowerPoint or R Markdown.
- Report estimates on the natural scale (back-transformed column) with %RSE, and BSV as %CV, noting shrinkage.
- In R Markdown / Quarto, `nlmixr2rpt::build_figures()` / `build_tables()` produce the same report elements as files for inclusion.

## Workflow

1. Confirm the fit passed the estimation acceptance checks (OFV finite, SEs present); reporting a broken fit wastes the reader's time.
2. Generate the diagnostics checklist, saving figures to files with consistent size and names.
3. Build the parameter table.
4. Assemble the document (nlmixr2rpt, ggPMX report, or R Markdown) and open / inspect the output file — confirm figures rendered and tables are populated.
5. Summarise in words: model structure, key estimates with precision, what the diagnostics show, and caveats.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `vpcPlot()` empty | no residual-error line in the model, or `dvid` mismatch with the data |
| VPC percentiles wildly off | wrong `idv` (use `vpcPlotTad()` for time after dose), varying doses without `pred_corr = TRUE`, too few `n` |
| `plot(fit)` lacks CWRES panels | run `addCwres(fit)` (SAEM fits don't compute it by default) |
| `xpose_data_nlmixr2()` warns about CWRES | expected — it adds them; pass a fit with `addCwres()` already applied to avoid the message |
| `report_fit()` build errors in figures | the YAML `cmd` must create `p_res`; libraries used by the command must be listed in the YAML preamble |
| `pmx_report()` fails with `please provide a valid save directory` | `save_dir` must already exist |
| Empty Word tables | `t_res` not populated, or parameter names in the YAML `parameters` block don't match the model |
| ggPMX controller missing covariate plots | pass `conts=` / `cats=` with the exact data column names |

## What NOT to do

- Don't report a single GOF plot and call the model adequate.
- Don't show VPCs without stating `n`, binning, and whether prediction-corrected.
- Don't hand-type parameter values into a document; generate the table from the fit.
- Don't skip opening the generated document to check it.

## References

- nlmixr2plot: `vpcPlot()`, `plot.nlmixr2FitData`, `traceplot()` help pages
- nlmixr2: `vignettes/xgxr-nlmixr-ggpmx.Rmd` (exploratory + GOF workflow), `vignettes/broom.Rmd`
- xpose.nlmixr2: package README; xpose: `vignettes/introduction.Rmd`, `customize_plots.Rmd`, `access_xpdb_data.Rmd`
- ggPMX: `vignettes/ggPMX-nlmixr.Rmd` (nlmixr2-specific), `vignettes/ggPMX-guide.Rmd`
- nlmixr2rpt: `vignettes/Reporting_nlmixr_Fit_Results.Rmd`, `Accessing_Figures_and_Tables.Rmd`; onbrand vignettes for custom templates
- shinyMixR: `vignettes/getting_started.Rmd`
