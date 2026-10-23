# Execute the fenced R code blocks shipped in the agent and skill markdown.
# See helper-examples.R for the fixture and the opt-in switch.

test_that("every bundled markdown file has balanced code fences", {
  for (f in example_source_files()) {
    expect_no_error(extract_code_blocks(f), message = example_label(f))
  }
})

test_that("slow and per-block package lists only name blocks that exist", {
  blocks <- do.call(rbind, lapply(example_source_files(), extract_code_blocks))
  keys <- paste0(blocks$file, "#", blocks$index)
  named <- c(names(example_slow), names(example_block_packages))
  expect_true(all(named %in% keys), info = paste(setdiff(named, keys), collapse = ", "))
})

test_that("skip list only names blocks that exist", {
  blocks <- do.call(rbind, lapply(example_source_files(), extract_code_blocks))
  keys <- paste0(blocks$file, "#", blocks$index)
  expect_true(all(names(example_skips) %in% keys),
              info = paste(setdiff(names(example_skips), keys), collapse = ", "))
})

test_that("bash blocks in the agent run cleanly", {
  skip_on_cran()
  skip_on_os("windows")   # `bash` there is the WSL launcher, not a shell
  skip_if(Sys.which("bash") == "", "bash not on PATH")
  # R CMD check exports R_TESTS=startup.Rs (a path relative to the tests dir);
  # a child R process started from tests/testthat cannot find it and dies at
  # startup, so clear it for the subprocess.
  withr::local_envvar(R_TESTS = "")
  blocks <- do.call(rbind, lapply(example_source_files(), extract_code_blocks))
  bash <- blocks[blocks$lang == "bash", , drop = FALSE]
  expect_gt(nrow(bash), 0)
  # `R CMD check --as-cran` puts an instrumented `Rscript` on the PATH that
  # refuses to run without a full path. The snippet is written for a coding
  # agent's shell where bare `Rscript` is right, so substitute the full path
  # only for this smoke test.
  rscript <- shQuote(file.path(R.home("bin"), "Rscript"))
  for (i in seq_len(nrow(bash))) {
    cmd <- gsub("(^|[^[:alnum:]_/])Rscript\\b", paste0("\\1", rscript), bash$code[i],
                perl = TRUE)
    expect_match(cmd, R.home("bin"), fixed = TRUE)   # the substitution must have happened
    out <- suppressWarnings(system2("bash", c("-c", shQuote(cmd)),
                                    stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status") %||% 0L
    expect_identical(status, 0L,
                     info = sprintf("%s#%d\n%s", bash$file[i], bash$index[i],
                                    paste(out, collapse = "\n")))
  }
})

# One test per R block so failures are attributed to a specific snippet.
# The fixture (a real SAEM fit) is built once per file run, only when enabled.
examples_enabled <- isTRUE(as.logical(Sys.getenv("NLMIXR2LLM_RUN_EXAMPLES", "false"))) &&
  !identical(Sys.getenv("NOT_CRAN"), "false") &&
  all(vapply(example_packages, requireNamespace, logical(1), quietly = TRUE))

if (!examples_enabled) {
  test_that("skill code examples", {
    skip_unless_examples_enabled()
  })
} else {
  fixture <- example_fixture_env()
  overrides <- lapply(example_block_overrides(fixture), function(f) f())
  root_workdir <- tempfile("nlmixr2llm-examples-")
  dir.create(root_workdir)

  blocks <- do.call(rbind, lapply(example_source_files(), extract_code_blocks))
  blocks <- blocks[blocks$lang == "r", , drop = FALSE]

  for (i in seq_len(nrow(blocks))) {
    block <- blocks[i, ]
    key <- paste0(block$file, "#", block$index)
    test_that(sprintf("%s (line %d) runs", key, block$line), {
      if (key %in% names(example_skips)) {
        skip(example_skips[[key]])
      }
      for (p in example_block_packages[[key]]) skip_if_not_installed(p)
      slow <- key %in% names(example_slow)
      if (slow && slow_examples_mode() == "false") {
        skip(paste0("slow (", example_slow[[key]], "); set NLMIXR2LLM_SLOW_EXAMPLES=true"))
      }
      if (!slow && slow_examples_mode() == "only") skip("not a slow example")
      workdir <- file.path(root_workdir, gsub("[^A-Za-z0-9]+", "_", block$file))
      dir.create(workdir, showWarnings = FALSE, recursive = TRUE)
      result <- NULL
      expect_no_error(
        result <- run_example_block(block, fixture, workdir, overrides)
      )
      bad <- unexpected_warnings(attr(result, "warnings"), key)
      expect_length(bad, 0)
      if (length(bad)) cat("\nUnexpected warnings in ", key, ":\n  ",
                           paste(bad, collapse = "\n  "), "\n", sep = "")
    })
  }
}
