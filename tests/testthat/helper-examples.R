# Support for test-examples.R: run the fenced R code blocks in the bundled
# agent and skill markdown against a shared fixture, so that API drift in the
# nlmixr2 ecosystem shows up as a test failure rather than as an LLM writing
# broken code.
#
# These tests are opt-in because they fit real models and need the whole
# modeling stack installed. Enable with:
#   Sys.setenv(NLMIXR2LLM_RUN_EXAMPLES = "true"); testthat::test_local(filter = "examples")

# Packages a snippet may attach or call. All must be installed for the example
# tests to run; none are hard dependencies of nlmixr2llm itself.
example_packages <- c(
  "rxode2", "nlmixr2", "nlmixr2est", "nlmixr2data", "nlmixr2plot", "nlmixr2lib",
  "nlmixr2extra", "nlmixr2rpt", "onbrand", "xpose.nlmixr2", "xpose", "ggPMX",
  "nonmem2rx", "monolix2rx", "babelmixr2", "PopED", "dplyr", "tidyr", "withr"
)

skip_unless_examples_enabled <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(
    isTRUE(as.logical(Sys.getenv("NLMIXR2LLM_RUN_EXAMPLES", "false"))),
    "Set NLMIXR2LLM_RUN_EXAMPLES=true to run the skill code examples"
  )
  for (p in example_packages) testthat::skip_if_not_installed(p)
}

# Bundled markdown files whose code blocks are tested: the agent(s) and every
# file in every skill directory.
example_source_files <- function() {
  root <- system.file(package = "nlmixr2llm")
  c(
    list.files(file.path(root, "agents"), pattern = "\\.md$", full.names = TRUE),
    list.files(file.path(root, "skills"), pattern = "\\.md$",
               recursive = TRUE, full.names = TRUE)
  )
}

# Relative label for a file, e.g. "skills/simulation/SKILL.md".
example_label <- function(path) {
  sub(paste0("^", system.file(package = "nlmixr2llm"), "/"), "", path)
}

# Extract fenced code blocks. Returns a data.frame with one row per block:
# file (label), index (1-based within the file), lang (fence info string),
# line (line number of the opening fence), code (block body as one string).
extract_code_blocks <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  fences <- grep("^```", lines)
  if (length(fences) %% 2 != 0) {
    stop("Unbalanced code fences in ", path)
  }
  if (!length(fences)) {
    return(data.frame(file = character(), index = integer(), lang = character(),
                      line = integer(), code = character(), stringsAsFactors = FALSE))
  }
  opens <- fences[seq(1, length(fences), by = 2)]
  closes <- fences[seq(2, length(fences), by = 2)]
  data.frame(
    file = example_label(path),
    index = seq_along(opens),
    lang = trimws(sub("^```", "", lines[opens])),
    line = opens,
    code = vapply(seq_along(opens), function(i) {
      body <- lines[seq(opens[i] + 1L, closes[i] - 1L)]
      paste(body, collapse = "\n")
    }, character(1)),
    stringsAsFactors = FALSE
  )
}

# Blocks that cannot run here, keyed "file#index" -> reason. Everything else is
# expected to execute cleanly against the fixture.
example_skips <- c(
  "skills/interop/SKILL.md#1"                    = "runs NONMEM and Monolix",
  "skills/interop/SKILL.md#2"                    = "placeholder paths only",
  "skills/interop/references/nonmem.md#1"        = "runs NONMEM",
  "skills/interop/references/monolix.md#1"       = "runs Monolix",
  "skills/estimation/references/model-building.md#3" = "model({}) fragment, not a complete call",
  "skills/estimation/references/priors.md#2"         = "needs nlmixr2bayes and a Stan toolchain",
  "skills/design/SKILL.md#2"                     = "poped_optim() searches run for minutes",
  "skills/design/references/poped-recipes.md#2"  = "ED optimization runs for minutes",
  "skills/design/references/poped-recipes.md#3"  = "needs the adult and pediatric databases of ex.11",
  "skills/design/references/poped-recipes.md#4"  = "needs the weight-covariate model of ex.12",
  "skills/estimation/references/neural-networks.md#4" = "refits the UDE of block #1 for 400 rounds"
)

# Blocks that run but are too slow for every push / PR, keyed "file#index" ->
# reason. They are skipped unless NLMIXR2LLM_SLOW_EXAMPLES is "true" (run
# everything) or "only" (run just these); the weekly slow-examples.yaml
# workflow uses "only".
example_slow <- c(
  "skills/estimation/references/neural-networks.md#2" = "multi-eta focei fit training an nn() for 200 joint rounds",
  "skills/estimation/references/structural-model.md#3" = "nlmixr2auto stepwise search fits several SAEM models"
)

# "false" (default), "true", or "only".
slow_examples_mode <- function() {
  mode <- tolower(Sys.getenv("NLMIXR2LLM_SLOW_EXAMPLES", "false"))
  if (mode %in% c("true", "only")) mode else "false"
}

# Packages a single block needs beyond example_packages, keyed "file#index".
# The block is skipped (not failed) when one is missing, so an optional add-on
# such as nlmixr2nn (not on CRAN) does not disable the whole suite.
example_block_packages <- list(
  "skills/estimation/references/neural-networks.md#1" = "nlmixr2nn",
  "skills/estimation/references/neural-networks.md#2" = "nlmixr2nn",
  "skills/estimation/references/neural-networks.md#3" = c("nlmixr2nn", "lbfgsb3c"),
  "skills/estimation/references/neural-networks.md#5" = "nlmixr2nn",
  "skills/estimation/references/structural-model.md#2" = "nlmixr2autoinit",
  "skills/estimation/references/structural-model.md#3" = c("nlmixr2autoinit", "nlmixr2auto")
)

# Top-level statements that reference a placeholder path (a user's own files)
# are dropped before evaluation; the rest of the block still runs.
drop_placeholder_statements <- function(code) {
  exprs <- parse(text = code, keep.source = TRUE)
  keep <- !vapply(exprs, function(e) {
    grepl("path/to/", paste(deparse(e), collapse = "\n"), fixed = TRUE)
  }, logical(1))
  exprs[keep]
}

# Build the shared fixture environment once. The modeling packages are attached
# (as the snippets themselves do with library()) and called unqualified, so the
# package does not need to declare the whole nlmixr2 stack as a dependency for
# an opt-in developer test. Everything a snippet may assume
# to exist is defined here with a consistent, small one-compartment model:
#   data / theo_sd  NONMEM-style dataset (theo_sd plus DOSE, SEX, AGE covariates)
#   one.compartment the model function used in the estimation skill
#   fit             an nlmixr2 SAEM fit of that model
#   mod             the instantiated rxode2 UI of the same model (etas, cp, depot)
#   ev              a single-dose event table
#   nSub, dose      per-subject dosing helpers used by the simulation skill
#   model_fn        alias of one.compartment (interop snippets)
#   obnd, rptdetails  nlmixr2rpt report object (Word) and parsed default yaml
example_fixture_env <- function() {
  env <- new.env(parent = globalenv())
  for (p in c("rxode2", "nlmixr2", "nlmixr2plot", "nlmixr2lib", "nlmixr2rpt",
              "onbrand", "xpose.nlmixr2", "xpose", "ggPMX", "nonmem2rx",
              "monolix2rx")) {
    suppressPackageStartupMessages(library(p, character.only = TRUE))
  }

  # Everything below is evaluated *in* `env`, whose enclosure is the global
  # environment, so the attached packages resolve exactly as they do for the
  # snippets (and for a user at the console) -- not through the test file's
  # namespace chain.
  local(envir = env, {
    set.seed(1)
    data <- theo_sd                                   # from nlmixr2 / nlmixr2data
    dose_by_id <- tapply(data$AMT, data$ID, max)
    data$DOSE <- as.numeric(dose_by_id[as.character(data$ID)])
    ids <- sort(unique(data$ID))
    sex <- setNames(sample(c(0, 1), length(ids), replace = TRUE), ids)
    age <- setNames(round(runif(length(ids), 20, 60)), ids)
    data$SEX <- as.numeric(sex[as.character(data$ID)])
    data$AGE <- as.numeric(age[as.character(data$ID)])
    theo_sd <- data

    one.compartment <- function() {
      ini({
        tka <- log(1.57); label("Ka")
        tcl <- log(2.72); label("Cl")
        tv  <- log(31.5); label("V")
        eta.ka ~ 0.6
        eta.cl ~ 0.3
        eta.v  ~ 0.1
        add.sd <- 0.7
      })
      model({
        ka <- exp(tka + eta.ka)
        cl <- exp(tcl + eta.cl)
        v  <- exp(tv  + eta.v)
        d/dt(depot)  <- -ka * depot
        d/dt(center) <-  ka * depot - cl / v * center
        cp <- center / v
        cp ~ add(add.sd)
      })
    }
    model_fn <- one.compartment
    fit <- suppressMessages(nlmixr2(
      one.compartment, data, est = "saem",
      saemControl(print = 0, nBurn = 50, nEm = 50)
    ))
    mod <- one.compartment()
    ev <- et(amt = 320, cmt = "depot") |> et(time = 0:24)
    nSub <- 5L
    dose <- c(100, 150, 200, 250, 300)

    obnd <- read_template(
      template = system.file("templates", "nlmixr_obnd_template.docx", package = "nlmixr2rpt"),
      mapping  = system.file("templates", "nlmixr_obnd_template.yaml", package = "nlmixr2rpt")
    )
    rptdetails <- yaml_read_fit(
      obnd = obnd,
      rptyaml = system.file("templates", "report_fit.yaml", package = "nlmixr2rpt"),
      fit = fit
    )$rptdetails
    rm(dose_by_id, ids, sex, age)
  })
  env
}

# The warfarin model and design used by the design skill's recipes, built by
# evaluating the skill's own first example so the two cannot drift apart.
design_fixture <- function(fixture) {
  env <- new.env(parent = fixture)
  block <- extract_code_blocks(file.path(system.file(package = "nlmixr2llm"),
                                         "skills", "design", "SKILL.md"))[1, ]
  for (e in parse(text = block$code)) {
    if (!grepl("^(res|shrinkage|plot_model_prediction)", paste(deparse(e), collapse = ""))) {
      suppressMessages(eval(e, envir = env))
    }
  }
  list(warf = env$warf, e = env$e, db = env$db)
}

# Per-block fixture overrides, keyed "file#index": objects that replace the
# defaults for that block only (e.g. a nonmem2rx-converted model where the
# snippet reads slots only such an object has). Evaluated in a child of the
# fixture so attached packages resolve as for the snippets.
example_block_overrides <- function(fixture) {
  nm <- function() {
    eval(quote(suppressMessages(nonmem2rx(
      system.file("mods/cpt/runODE032.res", package = "nonmem2rx"),
      validate = TRUE, save = FALSE
    ))), envir = new.env(parent = fixture))
  }
  list(
    "skills/interop/references/nonmem.md#3" = function() list(mod = nm()),
    "skills/simulation/references/population-simulation.md#3" = function() list(mod = nm()),
    "skills/design/references/poped-recipes.md#1" = function() design_fixture(fixture)
  )
}

# Warnings that are expected noise from the modeling stack and do not indicate
# a broken snippet. Any other warning fails the block: rxode2, for example,
# only *warns* when a dose targets a compartment the model does not have, and
# the simulation then silently returns zeros.
example_warning_allowlist <- c(
  "in order to put confidence bands",      # confint() on a small simulation
  "multi-subject simulation without",      # rxode2 when ETAs are supplied via params=
  "Added CWRES",                           # xpose_data_nlmixr2() augmenting the fit
  "may not be available when loading",     # library() under pkgload during tests
  "was built under R version",
  "deprecated",                            # deprecation chatter from plotting packages
  "grouped output by",                     # dplyr summarise noise
  "Removed .* rows? containing",           # ggplot dropping NA rows in GOF plots
  "font family",                           # missing fonts when rendering to pdf
  "Orientation is not uniquely specified", # ggplot2 inside nlmixr2rpt figures
  "Continuous x aesthetic",
  "is.na\\(\\) applied to non-\\(list or vector\\)", # onbrand/nlmixr2rpt internals
  "id.vars and measure.vars are internally guessed",       # reshape2 melt in nlmixr2rpt tables
  "ATTENTION",                             # SAEM/FOCEi convergence advisories
  "covariance", "Hessian", "boundary",     # precision-step advisories on a tiny test fit
  "no C compiler",                         # rxode2 compiler probe
  "No software packages matched for filtering" # vpc::vpc() software filter on plain data frames
)

# Per-block allowances for warnings raised inside a package the snippet calls,
# keyed "file#index". Kept separate from the global list so a genuinely broken
# snippet elsewhere is not masked.
example_block_warning_allowlist <- list(
  "skills/interop/references/monolix.md#2" = "NAs introduced by coercion",  # monolix2rx parser
  # an eta passed into nn() is a network input, so it cannot be mu-referenced
  "skills/estimation/references/neural-networks.md#1" = "non-mu referenced",
  "skills/estimation/references/neural-networks.md#2" = "non-mu referenced"
)

# Evaluate one block in a fresh child of the fixture environment, in a working
# directory dedicated to its file so blocks that write and then read files
# (e.g. a copied yaml) still work. Plots are sent to a null device. Warnings are
# collected and returned (attribute "warnings") so the caller can fail on the
# unexpected ones.
run_example_block <- function(block, fixture, workdir, overrides = list()) {
  env <- new.env(parent = fixture)
  key <- paste0(block$file, "#", block$index)
  if (!is.null(overrides[[key]])) {
    for (nm in names(overrides[[key]])) assign(nm, overrides[[key]][[nm]], envir = env)
  }
  exprs <- drop_placeholder_statements(block$code)
  withr::local_dir(workdir)
  withr::local_pdf(file.path(workdir, "Rplots.pdf"))
  warnings_seen <- character()
  withCallingHandlers(
    for (e in exprs) {
      eval(e, envir = env)
    },
    warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    },
    message = function(m) invokeRestart("muffleMessage")
  )
  structure(invisible(env), warnings = warnings_seen)
}

# Warnings from a run that are not covered by the allowlist.
unexpected_warnings <- function(warnings_seen, key = NULL) {
  if (!length(warnings_seen)) return(character())
  allow <- c(example_warning_allowlist,
             if (!is.null(key)) example_block_warning_allowlist[[key]])
  ok <- vapply(warnings_seen, function(w) {
    any(vapply(allow, grepl, logical(1), x = w))
  }, logical(1))
  unique(warnings_seen[!ok])
}
