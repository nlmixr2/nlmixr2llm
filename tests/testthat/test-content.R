test_that("list_tasks returns the four task skills", {
  expect_setequal(
    list_tasks(),
    c("design", "estimation", "interop", "reporting", "simulation")
  )
  expect_identical(list_skills(), list_tasks())
})

test_that("list_packages maps tasks to the packages they cover", {
  all <- list_packages()
  expect_true(all(c("rxode2", "nlmixr2", "babelmixr2", "nonmem2rx",
                    "monolix2rx", "nlmixr2rpt") %in% all))
  expect_setequal(list_packages(tasks = "interop"),
                  c("babelmixr2", "nonmem2rx", "monolix2rx"))
  expect_error(list_packages(tasks = "nonsense"), "No matching tasks")
})

test_that("list_agents returns the single combined ecosystem agent", {
  expect_setequal(list_agents(), "nlmixr2verse")
})

test_that("every skill has frontmatter with name matching its directory", {
  for (t in list_tasks()) {
    txt <- get_skill(t)
    lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
    expect_identical(lines[1], "---", info = t)
    expect_true(any(grepl(sprintf("^name: %s$", t), lines)), info = t)
    expect_true(any(grepl("^description: .+", lines)), info = t)
    expect_true(nzchar(skill_description(t)), info = t)
  }
})

test_that("list_skill_files puts SKILL.md first and finds references", {
  files <- list_skill_files("interop")
  expect_identical(files[1], "SKILL.md")
  expect_true(any(grepl("^references/", files)))
  expect_error(list_skill_files("rxode2"))
})

cc_project <- function(df) df[df$target == "Claude Code (project)", ]

test_that("nlmixr2llm_status reports not-installed, current, then outdated", {
  tmp <- withr::local_tempdir()

  # Nothing installed yet -> Claude Code project files all absent.
  before <- cc_project(nlmixr2llm_status(path = tmp, quiet = TRUE))
  expect_true(all(before$status == "not installed"))

  # After install, everything is current.
  install_claude_code(scope = "project", path = tmp)
  after <- cc_project(nlmixr2llm_status(path = tmp, quiet = TRUE))
  expect_true(all(after$status == "current"))

  # Make one file stale -> reported as outdated.
  writeLines("stale", file.path(tmp, ".claude", "agents", "nlmixr2verse.md"))
  drift <- cc_project(nlmixr2llm_status(path = tmp, quiet = TRUE))
  expect_identical(drift$status[drift$item == "agents/nlmixr2verse.md"], "outdated")
})

test_that("nlmixr2llm_status messages an out-of-date summary", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  writeLines("stale", file.path(tmp, ".claude", "skills", "simulation", "SKILL.md"))
  expect_message(
    nlmixr2llm_status(path = tmp),
    "out of date.*overwrite = TRUE"
  )
})

test_that("nlmixr2llm_status covers Codex and Positron targets", {
  # Separate dirs so AGENTS.md / agents.md don't collide on case-insensitive
  # filesystems (macOS/Windows). Subset to stay under the Codex 32 KiB cap.
  d1 <- withr::local_tempdir()
  install_codex(scope = "project", path = d1,
                include = "skills", tasks = "simulation")
  s1 <- nlmixr2llm_status(path = d1, quiet = TRUE)
  expect_identical(
    s1$status[s1$target == "Codex / AGENTS.md (project)"], "current"
  )

  d2 <- withr::local_tempdir()
  install_positron(workspace = d2, style = "instructions", tasks = "simulation")
  inst <- nlmixr2llm_status(path = d2, quiet = TRUE)
  inst <- inst[inst$target == "Positron instructions (project)", ]
  expect_true(nrow(inst) >= 1 && all(inst$status == "current"))

  # Positron agents.md may be reported under the Codex label on a
  # case-insensitive filesystem (same file), so assert on the file's row.
  d3 <- withr::local_tempdir()
  install_positron(workspace = d3, style = "agents_md", tasks = "simulation")
  s3 <- nlmixr2llm_status(path = d3, quiet = TRUE)
  ag <- s3[tolower(s3$item) == "agents.md" & s3$status != "not installed", ]
  expect_true(nrow(ag) >= 1 && all(ag$status == "current"))
})

test_that("nlmixr2llm_status flags an out-of-date Codex AGENTS.md by version", {
  tmp <- withr::local_tempdir()
  install_codex(scope = "project", path = tmp,
                include = "skills", tasks = "simulation")
  f <- file.path(tmp, "AGENTS.md")
  writeLines(sub("version=[^[:space:]]+", "version=0.0.0", readLines(f)), f)

  df <- nlmixr2llm_status(path = tmp, quiet = TRUE)
  expect_identical(
    df$status[df$target == "Codex / AGENTS.md (project)"], "outdated"
  )
})

test_that("user-scope Claude Code install honors nlmixr2llm.home override", {
  tmp <- withr::local_tempdir()
  withr::local_options(nlmixr2llm.home = tmp)
  withr::local_envvar(CLAUDE_CONFIG_DIR = NA)   # force the option path

  files <- install_claude_code(scope = "user")
  # Everything must land under the redirected home, never the real ~.
  expect_true(all(startsWith(normalizePath(files),
                             normalizePath(file.path(tmp, ".claude")))))
  expect_true(file.exists(file.path(tmp, ".claude", "agents", "nlmixr2verse.md")))
})

test_that("user-scope Codex install honors nlmixr2llm.home override", {
  tmp <- withr::local_tempdir()
  withr::local_options(nlmixr2llm.home = tmp)
  withr::local_envvar(CODEX_HOME = NA)

  p <- install_codex(scope = "user", include = "skills", tasks = "simulation")
  expect_true(startsWith(normalizePath(p), normalizePath(file.path(tmp, ".codex"))))
})

test_that("user-scope install aborts when confirmation is declined", {
  tmp <- withr::local_tempdir()
  withr::local_options(nlmixr2llm.home = tmp)
  withr::local_envvar(CLAUDE_CONFIG_DIR = NA)
  testthat::local_mocked_bindings(confirm_home_write = function(root) FALSE)

  out <- install_claude_code(scope = "user")
  expect_length(out, 0)
  expect_false(dir.exists(file.path(tmp, ".claude", "agents")))
})

test_that("nlmixr2llm.consent option pre-approves the home write", {
  tmp <- withr::local_tempdir()
  withr::local_options(nlmixr2llm.home = tmp, nlmixr2llm.consent = TRUE)
  withr::local_envvar(CLAUDE_CONFIG_DIR = NA)
  # confirm_home_write should return TRUE without prompting even if interactive.
  expect_true(confirm_home_write(file.path(tmp, ".claude")))
})

test_that("startup_drift_message reports outdated targets, silent otherwise", {
  cur <- data.frame(
    target = c("Claude Code (user)", "Codex (user)"),
    status = c("current", "not installed"),
    stringsAsFactors = FALSE
  )
  expect_null(startup_drift_message(cur))

  mixed <- data.frame(
    target = c("Claude Code (user)", "Codex / AGENTS.md (project)"),
    status = c("outdated", "current"),
    stringsAsFactors = FALSE
  )
  msg <- startup_drift_message(mixed)
  expect_type(msg, "character")
  expect_match(msg, "out of date")
  expect_match(msg, "Claude Code")
})

test_that("get_agent and get_skill return non-empty markdown", {
  txt <- get_agent()
  expect_type(txt, "character")
  expect_gt(nchar(txt), 100)

  skill <- get_skill("simulation")
  expect_type(skill, "character")
  expect_gt(nchar(skill), 100)
  expect_error(get_skill("rxode2"))
})

test_that("system_prompt strips frontmatter and assembles content", {
  prompt <- system_prompt(tasks = "simulation")
  expect_false(grepl("^---", prompt))
  expect_match(prompt, "Agent: nlmixr2verse")
  expect_match(prompt, "Skill: simulation")
  expect_false(grepl("Skill: estimation", prompt))
})

test_that("system_prompt includes the full agent regardless of tasks", {
  # The combined agent spans the whole ecosystem, so it is included even when
  # only one task's skill is requested.
  prompt <- system_prompt(tasks = "simulation")
  expect_match(prompt, "monolix2rx")  # mentioned by the ecosystem agent
})

test_that("system_prompt respects include argument", {
  agents_only <- system_prompt(tasks = "simulation", include = "agents")
  expect_match(agents_only, "Agent: nlmixr2verse")
  expect_false(grepl("Skill: simulation", agents_only))

  skills_only <- system_prompt(tasks = "simulation", include = "skills")
  expect_match(skills_only, "Skill: simulation")
  expect_false(grepl("Agent: nlmixr2verse", skills_only))
})

test_that("system_prompt can append skill reference files", {
  compact <- system_prompt(tasks = "interop", include = "skills")
  full <- system_prompt(tasks = "interop", include = "skills", references = TRUE)
  expect_false(grepl("Reference \\(interop\\)", compact))
  expect_match(full, "Reference \\(interop\\): references/nonmem.md")
  expect_gt(nchar(full), nchar(compact))
})

test_that("system_prompt rejects unknown tasks", {
  expect_error(system_prompt(tasks = "rxode2"), "No matching tasks")
})

test_that("install_codex writes a project AGENTS.md", {
  tmp <- withr::local_tempdir()
  path <- install_codex(
    scope = "project",
    tasks = "simulation",
    path = tmp,
    include = "agents"
  )
  expect_true(file.exists(path))
  expect_true(file.size(path) > 0)
  expect_match(readLines(path)[2], "tasks=simulation")
})

test_that("install_claude_code writes agents and skills to project scope", {
  tmp <- withr::local_tempdir()
  files <- install_claude_code(
    scope = "project",
    tasks = "interop",
    path = tmp
  )
  expect_true(any(grepl("agents/nlmixr2verse.md$", files)))
  expect_true(any(grepl("skills/interop/SKILL.md$", files)))
  # Supporting reference files travel with the skill.
  expect_true(any(grepl("skills/interop/references/nonmem.md$", files)))
  expect_false(any(grepl("skills/simulation/", files)))
  # A manifest is recorded so later re-installs can prune obsolete files.
  expect_true(file.exists(file.path(tmp, ".claude", ".nlmixr2llm-manifest")))
})

test_that("install_claude_code prunes files it no longer ships", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  skills <- file.path(tmp, ".claude", "skills")

  # Simulate a file installed by a previous version: present on disk *and*
  # recorded in the manifest, but not shipped by the current version (the old
  # per-package skill layout).
  dir.create(file.path(skills, "rxode2"))
  legacy <- file.path(skills, "rxode2", "SKILL.md")
  writeLines("legacy per-package skill", legacy)
  mf <- file.path(tmp, ".claude", ".nlmixr2llm-manifest")
  cat("skills/rxode2/SKILL.md\n", file = mf, append = TRUE)

  install_claude_code(scope = "project", path = tmp, overwrite = TRUE)

  expect_false(file.exists(legacy))                              # pruned
  expect_false(dir.exists(file.path(skills, "rxode2")))          # empty dir gone
  expect_true(file.exists(file.path(skills, "simulation", "SKILL.md")))  # kept
})

test_that("install_claude_code prune = FALSE keeps obsolete files", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  agents <- file.path(tmp, ".claude", "agents")
  legacy <- file.path(agents, "rxode2.md")
  writeLines("legacy", legacy)
  cat("agents/rxode2.md\n",
      file = file.path(tmp, ".claude", ".nlmixr2llm-manifest"), append = TRUE)

  install_claude_code(scope = "project", path = tmp, overwrite = TRUE,
                      prune = FALSE)

  expect_true(file.exists(legacy))                        # left in place
})

test_that("install_claude_code never prunes files it did not install", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  # A user's own agent that nlmixr2llm did not create (not in the manifest).
  mine <- file.path(tmp, ".claude", "agents", "my-agent.md")
  writeLines("mine", mine)

  install_claude_code(scope = "project", path = tmp, overwrite = TRUE)

  expect_true(file.exists(mine))
})

test_that("install_claude_code does not prune deselected but shipped tasks", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp,
                      tasks = c("simulation", "estimation"))
  # Re-install a subset; estimation's skill is still shipped, just not selected.
  install_claude_code(scope = "project", path = tmp, tasks = "simulation",
                      overwrite = TRUE)

  expect_true(file.exists(
    file.path(tmp, ".claude", "skills", "estimation", "SKILL.md")
  ))
})

test_that("install_positron agents_md style writes workspace agents.md", {
  tmp <- withr::local_tempdir()
  path <- install_positron(
    workspace = tmp,
    style = "agents_md",
    tasks = "simulation"
  )
  expect_true(file.exists(path))
  expect_match(path, "agents\\.md$")
})

test_that("install_positron instructions style writes per-task + agent files", {
  tmp <- withr::local_tempdir()
  files <- install_positron(
    workspace = tmp,
    style = "instructions",
    tasks = c("simulation", "estimation")
  )
  # Two task skill files plus the single combined ecosystem agent.
  expect_length(files, 3)
  expect_true(all(file.exists(files)))
  expect_true(any(grepl("nlmixr2verse.instructions.md$", files)))
  # The skill's own description is carried into the frontmatter (quoted).
  sim <- readLines(grep("simulation.instructions.md$", files, value = TRUE))
  expect_match(sim[3], '^description: ".*simulate.*"$')
})

test_that("install_claude_code flags out-of-date files when overwrite = FALSE", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  # Make one installed file stale relative to the bundled version.
  writeLines("stale", file.path(tmp, ".claude", "agents", "nlmixr2verse.md"))

  expect_message(
    install_claude_code(scope = "project", path = tmp),  # overwrite = FALSE
    "out of date"
  )
  expect_message(
    install_claude_code(scope = "project", path = tmp),
    "re-run with overwrite = TRUE"
  )
})

test_that("install_claude_code overwrite = TRUE refreshes a stale file", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  verse <- file.path(tmp, ".claude", "agents", "nlmixr2verse.md")
  writeLines("stale", verse)

  install_claude_code(scope = "project", path = tmp, overwrite = TRUE)
  expect_false(identical(readLines(verse)[1], "stale"))
})

test_that("install_claude_code is quiet about drift when nothing changed", {
  tmp <- withr::local_tempdir()
  install_claude_code(scope = "project", path = tmp)
  # Re-install over identical files: nothing reported as out of date.
  msgs <- testthat::capture_messages(
    install_claude_code(scope = "project", path = tmp)
  )
  expect_false(any(grepl("out of date", msgs)))
  expect_true(any(grepl("Installed 0 file", msgs)))
})

test_that("install_positron instructions flags out-of-date files", {
  tmp <- withr::local_tempdir()
  install_positron(workspace = tmp, style = "instructions", tasks = "simulation")
  f <- file.path(tmp, ".github", "instructions", "simulation.instructions.md")
  writeLines("stale", f)

  expect_message(
    install_positron(workspace = tmp, style = "instructions", tasks = "simulation"),
    "out of date"
  )
})

test_that("install_positron instructions style prunes obsolete files", {
  tmp <- withr::local_tempdir()
  install_positron(workspace = tmp, style = "instructions", tasks = "simulation")
  dir <- file.path(tmp, ".github", "instructions")

  # Simulate a previously installed, now-unshipped instruction file (the old
  # per-package layout).
  legacy <- file.path(dir, "rxode2.instructions.md")
  writeLines("legacy", legacy)
  cat("rxode2.instructions.md\n",
      file = file.path(dir, ".nlmixr2llm-manifest"), append = TRUE)

  install_positron(workspace = tmp, style = "instructions",
                   tasks = "simulation", overwrite = TRUE)

  expect_false(file.exists(legacy))
  expect_true(file.exists(file.path(dir, "simulation.instructions.md")))
})

test_that("the agent plus any two skills fits Codex's 32 KiB AGENTS.md cap", {
  for (pair in utils::combn(list_tasks(), 2, simplify = FALSE)) {
    tmp <- withr::local_tempdir()
    path <- expect_no_warning(
      install_codex(scope = "project", path = tmp, tasks = pair)
    )
    expect_lte(file.size(path), 32 * 1024,
               label = paste("agent +", paste(pair, collapse = " + ")))
  }
})
