# List the tasks covered by this package

Content is organized around pharmacometric \*tasks\* rather than
individual packages. Each task ships a skill
(\`inst/skills/\<task\>/SKILL.md\`, plus optional supporting files under
\`inst/skills/\<task\>/references/\`), and a single combined agent,
\`nlmixr2verse\` (see \[list_agents()\]), orchestrates across them.

## Usage

``` r
list_tasks()
```

## Value

Character vector of task names.

## Details

The tasks are: \* \`"simulation"\` – author and simulate ODE PK/PD
models (rxode2, nlmixr2lib). \* \`"estimation"\` – fit population PK/PD
models (nlmixr2, nlmixr2extra). \* \`"reporting"\` – diagnostics, VPCs,
tables, and Word/PowerPoint reports (nlmixr2plot, xpose.nlmixr2, ggPMX,
nlmixr2rpt, shinyMixR). \* \`"interop"\` – work with proprietary
software: run models in NONMEM / Monolix / PKNCA and import finished
runs (babelmixr2, nonmem2rx, monolix2rx). \* \`"design"\` – optimal
design: evaluate a planned study and optimize its sampling times and
doses (babelmixr2, PopED).

## See also

\[list_packages()\] for the packages each task covers.

## Examples

``` r
list_tasks()
#> [1] "design"     "estimation" "interop"    "reporting"  "simulation"
```
