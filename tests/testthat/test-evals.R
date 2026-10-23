# Offline checks of the vitals evaluation in evals/ (no model calls). The
# evals/ directory is excluded from the built package, so these run only from
# a source checkout.

evals_dir <- function() testthat::test_path("..", "..", "evals")

test_that("the eval dataset is well formed", {
  skip_if_not(dir.exists(evals_dir()), "evals/ is only in a source checkout")
  skip_if_not_installed("tibble")
  env <- new.env()
  sys.source(file.path(evals_dir(), "dataset.R"), envir = env)
  ds <- env$nlmixr2_eval_dataset()
  expect_true(all(c("id", "skill", "runs", "input", "target") %in% names(ds)))
  expect_false(anyDuplicated(ds$id) > 0)
  expect_true(all(ds$skill %in% list_tasks()), info = paste(setdiff(ds$skill, list_tasks()), collapse = ", "))
  expect_type(ds$runs, "logical")
  expect_true(all(nzchar(ds$input) & nzchar(ds$target)))
  # every task skill is exercised at least once
  expect_setequal(intersect(list_tasks(), ds$skill), list_tasks())
})

test_that("answer code is extracted from every fence style", {
  skip_if_not(dir.exists(evals_dir()), "evals/ is only in a source checkout")
  env <- new.env()
  sys.source(file.path(evals_dir(), "eval.R"), envir = env)
  text <- paste0("Prose.\n```r\nx <- 1\n```\nmore\n```{r, eval = TRUE}\ny <- 2\n",
                 "```\n```R\nz <- 3\n```\n```python\nprint(1)\n```\n")
  expect_identical(env$extract_r_code(text), c("x <- 1\n", "y <- 2\n", "z <- 3\n"))
  expect_identical(env$extract_r_code("no code here"), character())
  lv <- c("I", "P", "C")
  expect_identical(as.character(env$downgrade(factor(c("C", "P", "I"), lv, ordered = TRUE))),
                   c("P", "I", "I"))
})

test_that("the stress kit is well formed and combines with the core set", {
  skip_if_not(dir.exists(evals_dir()), "evals/ is only in a source checkout")
  skip_if_not_installed("tibble")
  env <- new.env()
  sys.source(file.path(evals_dir(), "stress.R"), envir = env)
  st <- env$nlmixr2_stress_dataset()
  expect_true(all(c("id", "skill", "source", "runs", "input", "target", "check") %in% names(st)))
  expect_true(all(st$skill %in% list_tasks()))
  expect_true(all(grepl("^(F|T)[0-9]{3}", st$source)), info = "every sample cites a benchmark finding or trap")
  # a hidden check only makes sense for executed answers, and must parse
  expect_true(all(is.na(st$check[!st$runs])))
  for (chk in st$check[st$runs]) expect_no_error(parse(text = chk))
  sys.source(file.path(evals_dir(), "dataset.R"), envir = env)
  ids <- c(env$nlmixr2_eval_dataset()$id, st$id)
  expect_false(anyDuplicated(ids) > 0)
})
