# nlmixr2llm

<!-- badges: start -->
[![R-CMD-check](https://github.com/john-harrold/nlmixr2llm/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/john-harrold/nlmixr2llm/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/john-harrold/nlmixr2llm/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/john-harrold/nlmixr2llm/actions/workflows/pkgdown.yaml)
[![skill-examples](https://github.com/john-harrold/nlmixr2llm/actions/workflows/skill-examples.yaml/badge.svg)](https://github.com/john-harrold/nlmixr2llm/actions/workflows/skill-examples.yaml)
<!-- badges: end -->

LLM-facing documentation for the [nlmixr2](https://nlmixr2.org/) pharmacometric modeling ecosystem in R, distributed as an R package and as a Claude Code plugin.

The content is organized around the **tasks** a pharmacometrician performs rather than around individual packages: a single `nlmixr2verse` agent routes work across four task skills — `simulation`, `estimation`, `reporting`, and `interop` (NONMEM / Monolix / PKNCA). The same content is shipped two ways:

- **As an R package**, with accessor functions for use as a system prompt with any LLM client (`ellmer`, the Anthropic SDK, the OpenAI SDK, ...) and installers that write the files into the locations expected by Claude Code, OpenAI Codex CLI, Positron Assistant, and other tools that follow the [`AGENTS.md`](https://agents.md) convention.
- **As a Claude Code plugin** via the `.claude-plugin/` directory at the repo root, so users who already use the Claude Code plugin marketplace can install without touching R.

## Coverage

| Task | What it covers | Packages |
|---|---|---|
| `simulation` | Author and debug ODE PK/PD models, event tables, single-subject / population / clinical-trial simulation, parameter uncertainty, resampling fitted subjects, the model library | [`rxode2`](https://github.com/nlmixr2/rxode2), [`nlmixr2lib`](https://github.com/nlmixr2/nlmixr2lib) |
| `estimation` | Fit population PK/PD models (SAEM, FOCEi, nlme), model building, covariates, standard errors, bootstrap, likelihood profiling, model comparison, neural networks inside models | [`nlmixr2`](https://github.com/nlmixr2/nlmixr2), [`nlmixr2extra`](https://github.com/nlmixr2/nlmixr2extra), `nlmixr2lib`, [`nlmixr2nn`](https://github.com/nlmixr2/nlmixr2nn), [`nlmixr2auto`](https://github.com/ucl-pharmacometrics/nlmixr2auto) |
| `reporting` | Goodness-of-fit diagnostics, VPCs, augmented predictions, parameter tables, Word / PowerPoint / R Markdown reports, interactive review | [`nlmixr2plot`](https://github.com/nlmixr2/nlmixr2plot), [`xpose.nlmixr2`](https://github.com/nlmixr2/xpose.nlmixr2), [`ggPMX`](https://github.com/ggPMXdevelopment/ggPMX), [`nlmixr2rpt`](https://github.com/nlmixr2/nlmixr2rpt), [`shinyMixR`](https://github.com/RichardHooijmaijers/shinyMixR) |
| `interop` | Run an nlmixr2 model in NONMEM / Monolix / PKNCA; import finished NONMEM or Monolix runs into R and qualify the translation; cross-engine comparison | [`babelmixr2`](https://github.com/nlmixr2/babelmixr2), [`nonmem2rx`](https://github.com/nlmixr2/nonmem2rx), [`monolix2rx`](https://github.com/nlmixr2/monolix2rx) |
| `design` | Optimal design for a planned study: expected precision (RSE%) and shrinkage, optimizing sampling times and doses, comparing group sizes, Ds / ED criteria, prior information, power | [`babelmixr2`](https://github.com/nlmixr2/babelmixr2), [`PopED`](https://github.com/andrewhooker/PopED) |

Each skill is a directory: a compact `SKILL.md` (~7-10 KiB) plus `references/*.md` files with extra depth (engine-specific NONMEM / Monolix notes, babelmixr2's in-R backends and PopED, population-simulation patterns, uncertainty and priors, adaptive dosing, the full estimation-method list, priors in estimation, model-building and precision recipes, the nlmixr2rpt YAML structure). The `nlmixr2verse` agent (~10 KiB) holds the ecosystem map by task, routing rules, the shared model-language conventions, and how the stages hand off to one another (simulate ⇄ estimate → report; import → qualify → simulate).

## Install (R package)

```r
# install.packages("remotes")
remotes::install_github("john-harrold/nlmixr2llm")
```

## Usage

### Use as a system prompt with any LLM client

```r
library(nlmixr2llm)

prompt <- system_prompt(tasks = c("simulation", "estimation"))

# Example: with ellmer
chat <- ellmer::chat_anthropic(system_prompt = prompt)
chat$chat("Write a one-compartment PK model with first-order absorption and simulate 100 mg q12h for 5 days.")
```

Add `references = TRUE` to include each skill's supporting reference files.

### Install into Claude Code

```r
# User-level (~/.claude/agents/, ~/.claude/skills/)
install_claude_code(scope = "user")

# Or project-local (.claude/agents/, .claude/skills/) under the current project
install_claude_code(scope = "project")
```

### Install into OpenAI Codex CLI

```r
# Project AGENTS.md at the repo root
install_codex(scope = "project", tasks = c("simulation", "estimation"))

# Global ~/.codex/AGENTS.md
install_codex(scope = "user", include = "agents", mode = "append")
```

Codex enforces a default 32 KiB cap on combined `AGENTS.md` content. The agent plus all five skills is ~51 KiB; the agent alone is ~10 KiB and each skill ~7-10 KiB, so the agent plus any two skills fits (up to ~29 KiB, enforced by a package test). `install_codex()` warns when the written file exceeds the cap.

### Install into Positron Assistant

```r
# Project-root agents.md (also picked up by Codex, Cursor, Aider, Zed, ...)
install_positron(workspace = ".", style = "agents_md")

# Per-task .github/instructions/*.instructions.md with applyTo: "**/*.R"
install_positron(workspace = ".", style = "instructions")
```

### Install for any tool that reads `AGENTS.md`

```r
install_agents_md(path = ".", tasks = c("simulation", "estimation"))
```

Covered by the [`agents.md`](https://agents.md) cross-tool spec: Codex, Cursor, Aider, GitHub Copilot, Zed, Warp, Jules, Devin, and others.

### Keeping installs in sync

The installers write independent copies, so re-run them after upgrading the package (pass `overwrite = TRUE` / `mode = "write"` to refresh existing files). `install_claude_code()` and `install_positron(style = "instructions")` keep a manifest (`.nlmixr2llm-manifest`) and, by default (`prune = TRUE`), remove files they installed in an earlier version but no longer ship — so upgrading from the per-package layout of 0.1.0 to the task layout removes the old `rxode2`, `nlmixr2`, ... skills automatically. Only files nlmixr2llm created are ever removed.

To check whether your installed content is current without reinstalling, run `nlmixr2llm_status()` — it inspects every install target (Claude Code user/project, Codex / `AGENTS.md`, and both Positron styles), reports any files that are out of date, and prints the refresh command for each. The `nlmixr2verse` agent also runs this check itself once per session and tells you when a refresh is available.

When you load the package interactively (`library(nlmixr2llm)`), it runs this check automatically (read-only) and prints a one-line notice if any installed copy is out of date — staying silent otherwise. Disable it with `options(nlmixr2llm.startup_check = FALSE)`.

## Use as a Claude Code plugin (no R required)

The bundled plugin manifest lives in `.claude-plugin/` at the repo root (pointing at the same `inst/agents/` and `inst/skills/` content the R package uses) so the repo doubles as a plugin source:

```text
/plugin marketplace add john-harrold/nlmixr2llm
/plugin install nlmixr2llm@nlmixr2llm
```

## API

| Function | Purpose |
|---|---|
| `list_tasks()`, `list_skills()`, `list_agents()` | Discovery (skills are one per task) |
| `list_packages(tasks)` | Which nlmixr2-universe packages the selected tasks cover |
| `list_skill_files(task)` | `SKILL.md` plus the supporting reference files of a skill |
| `get_agent()`, `get_skill(task)` | Raw markdown (`get_agent()` returns the combined `nlmixr2verse` agent) |
| `system_prompt(tasks, include, references)` | Combined prompt for LLM clients |
| `install_claude_code(scope, tasks, ...)` | Claude Code skill/agent tree |
| `install_codex(scope, tasks, mode, include, references)` | Codex CLI `AGENTS.md` |
| `install_agents_md(path, tasks, ...)` | Project-root `AGENTS.md` for any `agents.md`-aware tool |
| `install_positron(workspace, style, tasks, ...)` | Positron Assistant instructions |
| `nlmixr2llm_status(path)` | Report whether installed files (Claude Code, Codex, Positron) are out of date vs the package |

## Layout

```
nlmixr2llm/
├── DESCRIPTION
├── NAMESPACE
├── LICENSE
├── R/
│   ├── content.R
│   ├── claude_code.R
│   ├── codex.R
│   ├── agents_md.R
│   ├── positron.R
│   ├── status.R
│   └── sync.R
├── man/
├── .claude-plugin/        # Claude Code plugin manifest (not shipped in R tarball)
└── inst/
    ├── agents/
    │   └── nlmixr2verse.md
    └── skills/
        ├── simulation/    # SKILL.md + references/population-simulation.md, uncertainty-and-priors.md, adaptive-dosing.md
        ├── estimation/    # SKILL.md + references/model-building.md, estimation-methods.md, priors.md
        ├── reporting/     # SKILL.md + references/nlmixr2rpt.md
        ├── interop/       # SKILL.md + references/nonmem.md, monolix.md, babelmixr2-backends.md
        └── design/        # SKILL.md + references/poped-recipes.md
```

## Contributing

The skill and agent files are plain Markdown with YAML frontmatter — edit them in `inst/agents/` and `inst/skills/`. Keep each `SKILL.md` compact and push depth into that skill's `references/`. Vignette references point at filenames in each package's source repo (`github.com/nlmixr2/<pkg>/tree/main/vignettes/`); please verify any new references against the live repo before merging.

Every fenced R block in the agent and skills is executed by an opt-in test against a real fit, so a snippet that stops working with a new release of an nlmixr2-universe package shows up as a test failure. It needs the modeling stack installed and takes several minutes:

```r
Sys.setenv(NLMIXR2LLM_RUN_EXAMPLES = "true")
testthat::test_local(filter = "examples")
```

The same tests run in CI in a dedicated job (`.github/workflows/skill-examples.yaml`) that installs the modeling stack via `extra-packages` and runs on content changes and on a weekly schedule, so upstream API drift is caught without the main `R-CMD-check` matrix having to carry those dependencies. Blocks that require NONMEM or Monolix, or that only show placeholder paths, are listed in `example_skips` in `tests/testthat/helper-examples.R`. Snippets should assume the fixture objects documented there (`fit`, `mod`, `ev`, `data`, `obnd`, ...) or define what they use.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
