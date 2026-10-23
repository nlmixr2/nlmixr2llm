# nlmixr2llm 0.2.0

## Task-oriented content

* New `evals/` (source checkout only): a vitals evaluation of the agent and
  skill content. The same model answers each question without and with
  `system_prompt(references = TRUE)`. A grader model scores the answers
  against documented targets, and answers that must be code are executed, so
  the difference between the two conditions measures the skills' effect.
  Solver and grader are configurable by environment variable, so any
  provider ellmer supports can be used (for example, grading Claude answers
  with Gemini). vitals, ellmer, callr and tibble are added to Suggests.
* New `evals/stress.R`: a 17-question stress kit built from the nlmixr2-ecosystem
  findings and translation traps of the nlme-benchmark project (reserved
  `SS`/`II` columns, `sigdig = 3` ODE tolerances, the bare-`rxControl()`
  tolerance reset, `combined1` vs `combined2`, pinned objectives, conditional
  `etaSE`, scoring bias against the realised draw, and more). Three samples
  carry hidden checks that fail answers which run but are wrong. Select it
  with `NLMIXR2LLM_EVAL_SET=stress` (or `all`).
* New `estimation/references/structural-model.md`: base structural model
  exploration as the first model-building step, adapted from AgentODE
  (Yang et al. 2026). The agent reads the data's shape, proposes candidates
  from nlmixr2lib, fits them under an identical stochastic model, and gates
  and ranks them by OFV/AIC/BIC plus a VPC discrepancy. It then writes a
  structured diagnosis, keeps a `structure-log.csv` experience log, and as a
  fallback learns an unknown term with `nn()` and distills it into a closed
  form. `model-building.md`, the estimation skill and the agent now follow the
  order structure → stochastic model → covariates → evaluation. For single-endpoint
  PK within its search space, the reference starts from an automated
  nlmixr2auto search (with nlmixr2autoinit initial estimates) and continues
  the loop for what that search cannot express (absorption delays, PD, TMDD).
* New `estimation/references/neural-networks.md` covers models with embedded
  neural networks (nlmixr2nn `nn()`): universal differential equations,
  learned covariate relationships, no-BSV models, `nnControl()` and its
  regularizers, inspecting a network with `nnEval()`, hand-written augmented
  neural ODEs, and pitfalls. The estimation skill and the agent now steer any
  model containing `nn()` to a method with gradients on the inner step
  (`focei`, `laplace`/`agq`, `impmap`, `vae`/`emvi`/`fbvi`) rather than SAEM, and
  a model with no etas to a population estimator with gradients (`lbfgsb3c`,
  `nlminb`, `n1qn1`) rather than a derivative-free one.
  nlmixr2nn is added to the estimation task's packages.
* New `design` task skill for optimal design with PopED via babelmixr2
  (`est = "poped"`): evaluating a planned study's expected precision and
  shrinkage, optimizing sampling times and doses, comparing group sizes, Ds and ED
  criteria, prior information, and power (`references/poped-recipes.md`).
* New reference files carry the estimation-method, prior, uncertainty, and
  adaptive-dosing content: `estimation/references/estimation-methods.md`
  (mixed-effects vs pooled methods, variants, covariance tokens),
  `estimation/references/priors.md`,
  `simulation/references/uncertainty-and-priors.md`,
  `simulation/references/adaptive-dosing.md`, and
  `interop/references/babelmixr2-backends.md` (nlmer, saemix, FME).
* The agent now declares the `Skill` tool, so it can load the skills it
  routes to.
* Method choice is framed by the between-subject-variability structure:
  SAEM for many etas, FOCEi for few.
* Corrections: SAEM supports `ll()` likelihoods; `outerOpt` already defaults
  to `bobyqa`; `nlmixr2plot::traceplot()` is called explicitly because
  `coda::traceplot()` masks it after `library(nlmixr2)` (nlmixr2/nlmixr2#419);
  the useLinCmt (rxode2#1389) and tnpri (rxode2#1388) caveats are documented.
* The agent plus any two task skills fits Codex's 32 KiB `AGENTS.md` cap, and
  a test enforces it.
* Skills are now organized around **tasks** instead of individual packages:
  `simulation`, `estimation`, `reporting`, and `interop` (NONMEM / Monolix /
  PKNCA). The per-package skills (`rxode2`, `nlmixr2`, `babelmixr2`,
  `nonmem2rx`, `monolix2rx`) are gone; their content lives in the task skills.
* New `reporting` skill covers goodness-of-fit diagnostics, VPCs, parameter
  tables, and Word / PowerPoint reports (nlmixr2plot, xpose.nlmixr2, ggPMX,
  nlmixr2rpt, shinyMixR) -- content that had no home before.
* Skills may carry supporting `references/*.md` files for depth (e.g.
  `interop/references/nonmem.md`). `install_claude_code()` copies them with
  the skill; `system_prompt()` and the single-file installers include them
  when `references = TRUE`.
* The `nlmixr2verse` agent is now a compact orchestration layer (ecosystem map
  by task, routing, shared conventions, stage handoffs, self-check) at roughly
  a quarter of its previous size. The agent plus up to three skills fits under
  Codex's 32 KiB `AGENTS.md` cap.
* Event-table examples use `et(time = ...)` for sampling times; the unnamed
  form (`ev |> et(0:24)`) errors when piped in current rxode2.

## Verification

* Every fenced R code block in the agent and skills is now executed by an
  opt-in test (`tests/testthat/test-examples.R`) against a real SAEM fit, the
  bundled nonmem2rx / monolix2rx examples, and the nlmixr2rpt templates.
  Unexpected warnings fail the block (rxode2 only warns when a dose targets a
  compartment the model does not have). Run with
  `NLMIXR2LLM_RUN_EXAMPLES=true`; blocks that need NONMEM or Monolix are
  skipped. A dedicated GitHub Actions job (`skill-examples.yaml`) runs them
  weekly and on content changes against current CRAN releases.
* Content was reviewed against the installed packages and the upstream
  repositories. Fixes include the multi-endpoint residual syntax
  (`| endpoint`, a bare name, not `| dvid("name")`), the default nlmixr2rpt
  figure IDs, ggPMX's VPC being disabled for nlmixr2 fits, monolix2rx argument
  semantics and result-file layout, `nonmem2rx(save=)` writing `.qs`, and the
  behaviour of SAEM fits whose OFV is computed lazily. Upstream corrections
  from the per-package skills (bounded `logit(x, low, hi)`, `laplace` / `agq`
  methods, `boxCox()` / `dt()` / `ll()` residual forms, babelmixr2 importing
  engine output rather than re-translating, `babelmixr2::as.nlmixr2()`) are
  carried into the task skills.

## API changes (breaking)

* The `packages =` argument of `system_prompt()`, `install_claude_code()`,
  `install_codex()`, `install_agents_md()`, and `install_positron()` is
  replaced by `tasks =`. Passing a package name errors with the list of valid
  tasks.
* `get_skill()` takes a task name.
* New: `list_tasks()`, `list_skill_files()`, and a `references` argument on
  `system_prompt()` and the single-file installers.
* `list_packages()` now reports the packages the task skills cover and accepts
  `tasks =` to subset; `list_skills()` returns task names.
* Re-running `install_claude_code()` / `install_positron(style =
  "instructions")` after upgrading prunes the old per-package files
  automatically (manifest-tracked).

# nlmixr2llm 0.1.0

* Initial version.
* Ships a single combined `nlmixr2verse` agent spanning the nlmixr2
  pharmacometrics ecosystem (`rxode2`, `nlmixr2`, `nonmem2rx`, `monolix2rx`,
  `babelmixr2`), plus one skill per package.
* Accessor functions: `list_packages()`, `list_agents()`, `list_skills()`,
  `get_agent()`, `get_skill()`, and `system_prompt()` for use as a system
  prompt with any LLM client.
* Installer functions write the content into the locations expected by Claude
  Code (`install_claude_code()`), OpenAI Codex CLI (`install_codex()`),
  Positron Assistant (`install_positron()`), and any tool that reads
  `AGENTS.md` (`install_agents_md()`). Multi-file installers track what they
  write in a manifest and can prune content the package no longer ships.
* `nlmixr2llm_status()` reports whether the content installed into each target
  is up to date with the package.
