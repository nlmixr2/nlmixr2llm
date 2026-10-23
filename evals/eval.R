# Evaluate the nlmixr2llm agent and skills with vitals.
#
# The question is whether the bundled content makes a model better at
# nlmixr2 work. Each sample in evals/dataset.R is answered under two
# conditions with the same model:
#
#   baseline  no system prompt
#   skills    nlmixr2llm::system_prompt(references = TRUE): the agent, every
#             skill and every reference file
#
# Answers are graded by a model against the sample's target (C / P / I).
# Samples with `runs = TRUE` must contain R code, and the code is executed in
# a fresh R process: an answer whose code does not run is marked down one
# grade (C -> P, P -> I) however good its prose is.
#
# Run from the package root:
#
#   Rscript evals/eval.R
#
# Configuration (environment variables, all optional):
#
#   NLMIXR2LLM_EVAL_SOLVER   model under test, as "provider/model" for
#                            ellmer::chat(); default "anthropic/claude-opus-5-5"
#   NLMIXR2LLM_EVAL_GRADER   grading model; default "anthropic/claude-opus-5-5".
#                            A different model family from the solver, e.g.
#                            "google_gemini/gemini-3.5-flash", reduces
#                            self-preference in grading.
#   NLMIXR2LLM_EVAL_SET      "core" (evals/dataset.R), "stress" (evals/stress.R,
#                            questions built from the nlme-benchmark findings),
#                            or "all" (default "core")
#   NLMIXR2LLM_EVAL_IDS      comma-separated sample ids to run (default: all)
#   NLMIXR2LLM_EVAL_EPOCHS   repeats per sample (default 1; use 3+ to see variance)
#   NLMIXR2LLM_EVAL_CONDITIONS  comma-separated subset of "baseline,skills"
#   NLMIXR2LLM_EVAL_CODE_TIMEOUT  seconds an answer's code may run (default 300);
#                            code that times out counts as failing
#
# Provider credentials come from the usual variables (ANTHROPIC_API_KEY,
# GEMINI_API_KEY, OPENAI_API_KEY, ...). Logs are written to evals/logs/ and
# can be browsed with vitals::vitals_view("evals/logs").

eval_root <- function() {
  root <- getwd()
  if (!file.exists(file.path(root, "evals", "dataset.R"))) {
    stop("Run from the nlmixr2llm package root (evals/dataset.R not found).", call. = FALSE)
  }
  root
}

eval_setting <- function(name, default) {
  value <- Sys.getenv(name, "")
  if (nzchar(value)) value else default
}

# The content under test is the working tree, not an installed copy, so an
# edit to a skill is evaluated without reinstalling the package.
eval_system_prompt <- function(root = eval_root()) {
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(root, quiet = TRUE, export_all = FALSE)
  }
  nlmixr2llm::system_prompt(references = TRUE)
}

eval_conditions <- function(root = eval_root()) {
  all <- list(baseline = NULL, skills = eval_system_prompt(root))
  keep <- strsplit(eval_setting("NLMIXR2LLM_EVAL_CONDITIONS", "baseline,skills"), ",")[[1]]
  all[intersect(trimws(keep), names(all))]
}

eval_chat <- function(spec, system_prompt = NULL) {
  ellmer::chat(spec, system_prompt = system_prompt)
}

# ---------------------------------------------------------------------------
# Executing answer code

# Fenced R blocks (```r, ```R, ```{r ...}) from a model answer, in order.
extract_r_code <- function(text) {
  m <- regmatches(text, gregexpr("(?s)```[ \t]*(\\{[rR][^}]*\\}|[rR])[ \t]*\n(.*?)```", text,
                                 perl = TRUE))[[1]]
  if (!length(m)) return(character())
  sub("^```[^\n]*\n", "", sub("```$", "", m))
}

# Run an answer's R code in a fresh R process with the nlmixr2 stack on the
# search path, then the sample's hidden `check` code (if any) in the same
# environment. Returns list(ok, stage, error, seconds), where stage is
# "answer" or "check" for a failure.
run_answer_code <- function(text, check = NA_character_,
                            timeout = as.numeric(eval_setting("NLMIXR2LLM_EVAL_CODE_TIMEOUT", "300"))) {
  code <- extract_r_code(text)
  if (!length(code)) {
    return(list(ok = FALSE, stage = "answer", error = "answer contains no fenced R code",
                seconds = 0))
  }
  dir <- tempfile("nlmixr2llm-eval-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "answer.R")
  writeLines(c("suppressPackageStartupMessages(library(nlmixr2))", code), file)
  start <- Sys.time()
  res <- tryCatch({
    out <- callr::r(function(f, chk) {
      grDevices::pdf(NULL)              # plots go nowhere
      source(f, echo = FALSE, local = globalenv())
      if (is.na(chk) || !nzchar(chk)) return(NA_character_)
      tryCatch({ eval(parse(text = chk), envir = globalenv()); NA_character_ },
               error = function(e) conditionMessage(e))
    }, args = list(f = file, chk = check), wd = dir, timeout = timeout,
    stdout = NULL, stderr = NULL)
    if (is.na(out)) list(ok = TRUE, stage = NA_character_, error = NA_character_)
    else list(ok = FALSE, stage = "check", error = out)
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (!is.null(e$parent)) msg <- conditionMessage(e$parent)
    list(ok = FALSE, stage = "answer", error = msg)
  })
  res$seconds <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  res
}

# ---------------------------------------------------------------------------
# Scoring

grade_levels <- c("I", "P", "C")

# vitals returns its grades as an ordered factor only when every grade parsed
# and at least one is I or C; otherwise it returns a character vector. Always
# work with the factor so metrics and downgrading behave the same either way.
as_grade <- function(score) factor(as.character(score), levels = grade_levels, ordered = TRUE)

# One level lower (C -> P, P -> I, I stays I); a missing grade stays missing.
downgrade <- function(score) {
  idx <- match(as.character(score), grade_levels)
  as_grade(grade_levels[pmax(idx - 1L, 1L)])
}

# Model-graded against the target (with partial credit), then capped when
# required code does not run or fails the sample's hidden check. Both outcomes
# are kept in scorer_metadata.
nlmixr2_scorer <- function(grader_chat) {
  graded_qa <- vitals::model_graded_qa(partial_credit = TRUE, scorer_chat = grader_chat)
  function(samples, ...) {
    graded <- graded_qa(samples)
    score <- as_grade(graded$score)
    runs <- if ("runs" %in% names(samples)) as.logical(samples$runs) else rep(FALSE, nrow(samples))
    checks <- if ("check" %in% names(samples)) samples$check else rep(NA_character_, nrow(samples))
    execution <- vector("list", nrow(samples))
    for (i in seq_len(nrow(samples))) {
      if (isTRUE(runs[i])) {
        execution[[i]] <- run_answer_code(samples$result[i], check = checks[i])
        if (!execution[[i]]$ok) score[i] <- downgrade(score[i])
      }
    }
    metadata <- Map(function(m, ex) c(m, list(model_grade = NULL, execution = ex)),
                    graded$scorer_metadata, execution)
    for (i in seq_along(metadata)) metadata[[i]]$model_grade <- as.character(graded$score[i])
    list(score = score, scorer_chat = graded$scorer_chat, scorer_metadata = metadata)
  }
}

# Numeric summary: C = 1, P = 0.5, I = 0.
score_value <- function(score) c(I = 0, P = 0.5, C = 1)[as.character(score)]

# ---------------------------------------------------------------------------
# Running

# The samples of one set, with the columns every set shares. Stress samples
# keep their `source` (benchmark finding) and `check` columns; core samples
# get empty ones so the two can be combined.
eval_dataset <- function(set = "core", root = eval_root()) {
  set <- match.arg(set, c("core", "stress", "all"))
  env <- new.env()
  sys.source(file.path(root, "evals", "dataset.R"), envir = env)
  sys.source(file.path(root, "evals", "stress.R"), envir = env)
  core <- env$nlmixr2_eval_dataset()
  core$source <- NA_character_
  core$check  <- NA_character_
  core$set    <- "core"
  stress <- env$nlmixr2_stress_dataset()
  stress$set <- "stress"
  cols <- c("id", "set", "skill", "source", "runs", "input", "target", "check")
  switch(set,
         core   = core[, cols],
         stress = stress[, cols],
         all    = rbind(core[, cols], stress[, cols]))
}

run_nlmixr2_eval <- function(solver = eval_setting("NLMIXR2LLM_EVAL_SOLVER", "anthropic/claude-opus-5-5"),
                             grader = eval_setting("NLMIXR2LLM_EVAL_GRADER", "anthropic/claude-opus-5-5"),
                             set = eval_setting("NLMIXR2LLM_EVAL_SET", "core"),
                             ids = eval_setting("NLMIXR2LLM_EVAL_IDS", ""),
                             epochs = as.integer(eval_setting("NLMIXR2LLM_EVAL_EPOCHS", "1")),
                             log_dir = file.path(eval_root(), "evals", "logs")) {
  root <- eval_root()
  dataset <- eval_dataset(set, root)
  if (nzchar(ids)) {
    want <- trimws(strsplit(ids, ",")[[1]])
    unknown <- setdiff(want, dataset$id)
    if (length(unknown)) stop("Unknown sample ids: ", paste(unknown, collapse = ", "), call. = FALSE)
    dataset <- dataset[dataset$id %in% want, ]
  }
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  scorer <- nlmixr2_scorer(eval_chat(grader))

  tasks <- list()
  for (cond in names(conditions <- eval_conditions(root))) {
    message(sprintf("== %s / %s: %d samples x %d epoch(s), solver %s, grader %s",
                    set, cond, nrow(dataset), epochs, solver, grader))
    tsk <- vitals::Task$new(
      dataset = dataset,
      solver  = vitals::generate(eval_chat(solver, conditions[[cond]])),
      scorer  = scorer,
      name    = paste0("nlmixr2llm-", set, "-", cond),
      dir     = log_dir
    )
    tsk$eval(epochs = epochs, view = FALSE)
    tasks[[cond]] <- tsk
  }

  samples <- do.call(rbind, lapply(names(tasks), function(cond) {
    s <- tasks[[cond]]$get_samples()
    data.frame(condition = cond, id = s$id, set = s$set, skill = s$skill,
               score = as.character(s$score), value = score_value(s$score),
               row.names = NULL)
  }))
  summary <- stats::aggregate(value ~ condition, data = samples, FUN = mean)
  names(summary)[2] <- "mean_score"
  by_id <- stats::reshape(
    stats::aggregate(value ~ condition + id, data = samples, FUN = mean),
    idvar = "id", timevar = "condition", direction = "wide"
  )
  list(summary = summary, by_id = by_id, samples = samples, tasks = tasks)
}

if (sys.nframe() == 0L) {
  res <- run_nlmixr2_eval()
  cat("\nMean score by condition (C = 1, P = 0.5, I = 0):\n")
  print(res$summary, row.names = FALSE)
  cat("\nMean score by sample:\n")
  print(res$by_id, row.names = FALSE)
  cat("\nLogs: evals/logs (vitals::vitals_view(\"evals/logs\"))\n")
}
