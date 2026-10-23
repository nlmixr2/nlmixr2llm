# Evaluating the nlmixr2llm skills

This directory holds a [vitals](https://vitals.tidyverse.org) evaluation of the agent and skill content. It asks one question: **does the content make a model better at nlmixr2 work?**

It is excluded from the built package (`.Rbuildignore`), so run it from a source checkout.

## Design

- **Dataset** (`dataset.R`): one row per question, with:
  - `id`, a stable sample identifier;
  - `skill`, the task skill the question exercises;
  - `input`, the prompt;
  - `target`, the grading guidance: what a correct answer must say, and the mistakes that make it wrong;
  - `runs`, whether the answer must contain executable R code.

  Targets state only facts the skills document and that were checked against the packages. Otherwise the eval measures the grader's knowledge, not the skills' effect.
- **Stress kit** (`stress.R`): 17 questions built from the nlmixr2-ecosystem findings and translation traps of the nlme-benchmark project (`registry/findings.csv`, `registry/translationTraps.csv`). Each sits where a plausible answer is wrong but still runs, converges, or looks like a fit. Each row cites its `source` (a finding `Fnnn` or trap `Tnnn`). Examples:
  - SS/II columns that NONMEM ignores, but rxode2 reads as steady-state dosing;
  - the `sigdig = 3` ODE tolerances;
  - a bare `rxControl()` that silently resets the state tolerances;
  - `combined1` vs the default `combined2`;
  - pinned-objective comparisons with NONMEM;
  - conditional `etaSE`;
  - bias against the realised draw.

  Three stress samples carry a hidden `check`: R code run after the answer's code, in the same session, that fails an answer which runs but is wrong. Examples: a fit whose data still has active `SS`/`II`, a simulation that silently lost its dose, or a residual model that is not `combined1`. Every target was re-verified against the installed nlmixr2est and rxode2. Upstream issues since closed (babelmixr2#211, rxode2#1410) are tested as verification habits, not as current bugs.
- **Conditions**: the same model answers every question twice:
  - **baseline**: no system prompt;
  - **skills**: `nlmixr2llm::system_prompt(references = TRUE)`, built from the working tree, so an edited skill is evaluated without reinstalling.
- **Scoring** (`eval.R`):
  1. A grader model scores each answer C / P / I against its target (`vitals::model_graded_qa(partial_credit = TRUE)`).
  2. For `runs = TRUE` samples, the answer's fenced R code is executed in a fresh R process with nlmixr2 loaded, followed by the sample's hidden `check`, if it has one. Code that is missing, fails, or fails the check lowers the grade by one level (C → P, P → I).
  3. Both outcomes are kept in each sample's `scorer_metadata`.
- **Summary**: mean score per condition and per sample, counting C = 1, P = 0.5 and I = 0. The skills' effect is the difference between the two conditions.

## Running

From the package root:

```sh
Rscript evals/eval.R
```

All settings are environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `NLMIXR2LLM_EVAL_SOLVER` | `anthropic/claude-opus-5-5` | model under test, as `"provider/model"` for `ellmer::chat()` |
| `NLMIXR2LLM_EVAL_GRADER` | `anthropic/claude-opus-5-5` | grading model |
| `NLMIXR2LLM_EVAL_SET` | `core` | `core` (`dataset.R`), `stress` (`stress.R`) or `all` |
| `NLMIXR2LLM_EVAL_IDS` | all | comma-separated sample ids |
| `NLMIXR2LLM_EVAL_EPOCHS` | `1` | repeats per sample; use 3 or more before reading anything into a difference |
| `NLMIXR2LLM_EVAL_CONDITIONS` | `baseline,skills` | subset of conditions |
| `NLMIXR2LLM_EVAL_CODE_TIMEOUT` | `300` | seconds an answer's code may run; a timeout counts as failing |

Any provider ellmer supports works, with its usual credentials (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, ...). A grader from a different model family than the solver reduces self-preference in grading. For example, grade Claude answers with Gemini:

```sh
NLMIXR2LLM_EVAL_SOLVER=anthropic/claude-opus-5-5 \
NLMIXR2LLM_EVAL_GRADER=google_gemini/gemini-3.5-flash \
Rscript evals/eval.R
```

A Gemini-only smoke test, two samples under both conditions:

```sh
NLMIXR2LLM_EVAL_SOLVER=google_gemini/gemini-3.5-flash \
NLMIXR2LLM_EVAL_GRADER=google_gemini/gemini-3.5-flash \
NLMIXR2LLM_EVAL_IDS=sim-population,nonmem2rx-qualify \
Rscript evals/eval.R
```

To run the stress kit:

```sh
NLMIXR2LLM_EVAL_SET=stress Rscript evals/eval.R
```

Report the core and stress scores separately. The core set measures whether the skills help with ordinary work. The stress set measures whether they prevent the failures the benchmark found. A low stress score in the skills condition points to content the skills do not yet carry.

Logs go to `evals/logs/`, which is git-ignored. Browse them with `vitals::vitals_view("evals/logs")`; each sample shows the answer, the grader's explanation, and the code-execution result.

Running the `runs = TRUE` samples needs the nlmixr2 stack installed, plus callr. The skills condition sends about 140k characters of system prompt with every question, so its cost per sample is dominated by input tokens.

## Adding a sample

1. Write the question as a user would ask it.
2. Write the target from the skill content: the required elements, and the wrong answers that should fail.
3. Set `runs = TRUE` only if the answer must be runnable code, and keep that code fast. It runs once per sample, condition and epoch.
   For a stress sample, add a `check` that fails the plausible wrong answer. Before relying on it, verify it on one correct and one wrong hand-written answer with `run_answer_code(answer, check = ...)` from `eval.R`.
4. Run `Rscript -e 'testthat::test_local(filter = "evals")'`. It checks the dataset offline.

## Next steps

- **Grow the dataset.** Twelve questions establish the pipeline, not a measurement. Aim for at least 5–10 per skill, drawn from real user requests.
- **Evaluate the installed agent**, not just the content as a system prompt. `vitals::claude_code()` and `vitals::codex()` run the real agent CLIs in a Docker sandbox. Giving that sandbox an image with R, the nlmixr2 stack and the installed skills (`install_claude_code()`, `install_codex()`) would measure what users actually run, including the agent's tool use.
- **Track over time.** Run on each content change and compare per-sample scores against the previous run's logs.
