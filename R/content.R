#' List the tasks covered by this package
#'
#' Content is organized around pharmacometric *tasks* rather than individual
#' packages. Each task ships a skill (`inst/skills/<task>/SKILL.md`, plus
#' optional supporting files under `inst/skills/<task>/references/`), and a
#' single combined agent, `nlmixr2verse` (see [list_agents()]), orchestrates
#' across them.
#'
#' The tasks are:
#' * `"simulation"` -- author and simulate ODE PK/PD models (rxode2, nlmixr2lib).
#' * `"estimation"` -- fit population PK/PD models (nlmixr2, nlmixr2extra).
#' * `"reporting"` -- diagnostics, VPCs, tables, and Word/PowerPoint reports
#'   (nlmixr2plot, xpose.nlmixr2, ggPMX, nlmixr2rpt, shinyMixR).
#' * `"interop"` -- work with proprietary software: run models in NONMEM /
#'   Monolix / PKNCA and import finished runs (babelmixr2, nonmem2rx,
#'   monolix2rx).
#' * `"design"` -- optimal design: evaluate a planned study and optimize its
#'   sampling times and doses (babelmixr2, PopED).
#'
#' @return Character vector of task names.
#' @seealso [list_packages()] for the packages each task covers.
#' @export
#' @examples
#' list_tasks()
list_tasks <- function() {
  sort(list.files(pkg_path("skills")))
}

#' List the nlmixr2-universe packages covered by this package
#'
#' Packages are covered through the task skills (see [list_tasks()]); this
#' helper reports which packages the bundled content addresses, optionally
#' restricted to a subset of tasks.
#'
#' @param tasks Character vector of tasks (from [list_tasks()]) to restrict
#'   the result to. Defaults to all tasks.
#' @return Character vector of package names.
#' @export
#' @examples
#' list_packages()
#' list_packages(tasks = "interop")
list_packages <- function(tasks = NULL) {
  tasks <- match_tasks(tasks)
  sort(unique(unlist(task_packages_table()[tasks], use.names = FALSE)))
}

#' List available agents
#'
#' The ecosystem is covered by a single combined agent, `nlmixr2verse`, that
#' routes work across the tasks in [list_tasks()]. Per-task depth lives in the
#' skills (see [list_skills()]); the agent is the orchestration layer.
#'
#' @return Character vector of agent names (currently the single
#'   `"nlmixr2verse"`).
#' @export
#' @examples
#' list_agents()
list_agents <- function() {
  sort(sub("\\.md$", "", list.files(pkg_path("agents"), pattern = "\\.md$")))
}

#' List available skills
#'
#' Skills are one per task, so this is the same set as [list_tasks()].
#'
#' @return Character vector of skill names.
#' @export
#' @examples
#' list_skills()
list_skills <- function() {
  list_tasks()
}

#' Read an agent's markdown content
#'
#' @param agent One of [list_agents()]. Defaults to the single combined
#'   `"nlmixr2verse"` agent.
#' @return A length-one character string with the full markdown content,
#'   including YAML frontmatter.
#' @export
#' @examples
#' cat(substr(get_agent(), 1, 200))
get_agent <- function(agent = "nlmixr2verse") {
  agent <- match.arg(agent, list_agents())
  read_file(file.path(pkg_path("agents"), paste0(agent, ".md")))
}

#' Read a skill's markdown content
#'
#' Returns the `SKILL.md` for a task. Supporting reference files that ship
#' alongside it (see [list_skill_files()]) are not included; use
#' [system_prompt()] with `references = TRUE` to concatenate them.
#'
#' @param task One of [list_tasks()].
#' @return A length-one character string with the full SKILL.md content,
#'   including YAML frontmatter.
#' @export
#' @examples
#' cat(substr(get_skill("simulation"), 1, 200))
get_skill <- function(task) {
  task <- match.arg(task, list_tasks())
  read_file(file.path(pkg_path("skills"), task, "SKILL.md"))
}

#' List the files that make up a skill
#'
#' A skill is a directory: `SKILL.md` plus any supporting files (typically
#' `references/*.md`) that give an agent extra depth on demand. Multi-file
#' installers such as [install_claude_code()] copy the whole directory.
#'
#' @param task One of [list_tasks()].
#' @return Character vector of paths relative to the skill directory, with
#'   `SKILL.md` first.
#' @export
#' @examples
#' list_skill_files("interop")
list_skill_files <- function(task) {
  task <- match.arg(task, list_tasks())
  files <- list.files(file.path(pkg_path("skills"), task), recursive = TRUE)
  c("SKILL.md", sort(setdiff(files, "SKILL.md")))
}

#' Build a combined system prompt for use with any LLM client
#'
#' Concatenates the combined `nlmixr2verse` agent and the per-task skill
#' content into a single character string suitable for use as a system prompt
#' with `ellmer`, the Anthropic SDK, the OpenAI SDK, or any other LLM client.
#' YAML frontmatter is stripped so the result is plain markdown.
#'
#' There is a single ecosystem-wide agent (`nlmixr2verse`) rather than one per
#' task, so when agents are requested it is always included in full regardless
#' of `tasks`; `tasks` only subsets the skills.
#'
#' @param tasks Character vector of tasks whose skills to include. Defaults to
#'   all available tasks (see [list_tasks()]).
#' @param include Which content to include: `"both"` (default), `"agents"`, or
#'   `"skills"`.
#' @param references If `TRUE`, also append each selected skill's supporting
#'   reference files (see [list_skill_files()]) after its `SKILL.md`. Defaults
#'   to `FALSE`, which keeps the prompt compact.
#' @return A length-one character string.
#' @seealso [list_tasks()], [get_agent()], [get_skill()]
#' @export
#' @examples
#' prompt <- system_prompt(tasks = "simulation")
#' nchar(prompt)
system_prompt <- function(tasks = NULL,
                          include = c("both", "agents", "skills"),
                          references = FALSE) {
  include <- match.arg(include)
  tasks <- match_tasks(tasks)

  parts <- character()
  parts <- c(parts, paste0(
    "# nlmixr2 ecosystem reference\n\n",
    "The following sections describe how to write correct code for the ",
    "nlmixr2 pharmacometric modeling ecosystem, organized by task. ",
    "Tasks: ", paste(tasks, collapse = ", "), ". ",
    "Packages: ", paste(list_packages(tasks), collapse = ", "), "."
  ))

  if (include %in% c("both", "agents")) {
    for (a in list_agents()) {
      parts <- c(parts, sprintf("\n## Agent: %s\n", a),
                 strip_frontmatter(get_agent(a)))
    }
  }

  if (include %in% c("both", "skills")) {
    for (t in tasks) {
      parts <- c(parts, sprintf("\n## Skill: %s\n", t),
                 strip_frontmatter(get_skill(t)))
      if (isTRUE(references)) {
        for (f in setdiff(list_skill_files(t), "SKILL.md")) {
          parts <- c(parts, sprintf("\n### Reference (%s): %s\n", t, f),
                     read_file(file.path(pkg_path("skills"), t, f)))
        }
      }
    }
  }

  paste(parts, collapse = "\n")
}

# Internal helpers --------------------------------------------------------

# Which nlmixr2-universe packages each task skill covers. Kept as a static
# table (rather than parsed from the skill files) so list_packages() is cheap
# and stable.
task_packages_table <- function() {
  list(
    simulation = c("rxode2", "nlmixr2lib"),
    estimation = c("nlmixr2", "nlmixr2est", "nlmixr2extra", "nlmixr2lib",
                   "nlmixr2nn", "nlmixr2auto", "nlmixr2autoinit"),
    reporting  = c("nlmixr2plot", "xpose.nlmixr2", "ggPMX", "nlmixr2rpt",
                   "shinyMixR"),
    interop    = c("babelmixr2", "nonmem2rx", "monolix2rx"),
    design     = c("babelmixr2", "PopED")
  )
}

# Validate a `tasks` argument: NULL means all; otherwise keep the known ones
# and error if nothing is left.
match_tasks <- function(tasks) {
  all <- list_tasks()
  if (is.null(tasks)) {
    return(all)
  }
  tasks <- intersect(tasks, all)
  if (!length(tasks)) {
    stop("No matching tasks. Available: ", paste(all, collapse = ", "))
  }
  tasks
}

# The `description:` field from a skill's YAML frontmatter (single line), or a
# generic fallback if absent. Used for the Positron instruction files.
skill_description <- function(task) {
  lines <- strsplit(get_skill(task), "\n", fixed = TRUE)[[1]]
  m <- grep("^description:", lines, value = TRUE)
  if (length(m)) {
    trimws(sub("^description:\\s*", "", m[1]))
  } else {
    sprintf("nlmixr2 ecosystem guidance for the %s task", task)
  }
}

pkg_path <- function(...) {
  system.file(..., package = "nlmixr2llm", mustWork = TRUE)
}

# Base directory under which user-scope installs are written (`~/.claude`,
# `~/.codex`). Defaults to the user's home directory, but can be redirected via
# `options(nlmixr2llm.home = ...)` so tests and examples can target a temporary
# directory instead of touching the real home filespace.
nlmixr2llm_home <- function() {
  getOption("nlmixr2llm.home", default = path.expand("~"))
}

# CRAN policy requires confirmation before writing into the user's home
# filespace. Ask in interactive sessions; in non-interactive use (scripts, CI,
# the package's own tests) the caller is explicit, so proceed without prompting.
# `options(nlmixr2llm.consent = TRUE)` pre-approves (useful for setup scripts).
confirm_home_write <- function(root) {
  if (isTRUE(getOption("nlmixr2llm.consent")) || !interactive()) {
    return(TRUE)
  }
  isTRUE(utils::askYesNo(
    sprintf("nlmixr2llm: write agent/skill files under '%s'?", root)
  ))
}

read_file <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

strip_frontmatter <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  if (length(lines) >= 1 && lines[1] == "---") {
    close_idx <- which(lines[-1] == "---")[1]
    if (!is.na(close_idx)) {
      lines <- lines[-seq_len(close_idx + 1)]
    }
  }
  paste(lines, collapse = "\n")
}

# An HTML-comment stamp embedded in concatenated installer outputs (Codex
# AGENTS.md, Positron files) so nlmixr2llm_status() can tell when an upgraded
# package ships newer content than the installed blob. Claude Code installs are
# discrete files and use content hashing instead, so they are not stamped.
stamp_comment <- function(tasks, include = NULL) {
  ver <- as.character(utils::packageVersion("nlmixr2llm"))
  paste0(
    "<!-- nlmixr2llm: version=", ver,
    " tasks=", paste(tasks, collapse = ","),
    if (!is.null(include)) paste0(" include=", include) else "",
    " -->"
  )
}

# Read the version recorded in a stamp_comment(), or NA if the file has none.
stamp_version <- function(file) {
  if (!file.exists(file)) {
    return(NA_character_)
  }
  txt <- read_file(file)
  m <- regmatches(txt, regexpr("<!-- nlmixr2llm: version=[^[:space:]]+", txt))
  if (!length(m)) {
    return(NA_character_)
  }
  sub("<!-- nlmixr2llm: version=", "", m)
}

# TRUE if the two files differ in content (or either is missing/unreadable).
files_differ <- function(a, b) {
  da <- unname(tools::md5sum(a))
  db <- unname(tools::md5sum(b))
  is.na(da) || is.na(db) || da != db
}

# Trailing note for an install summary: how many existing files were skipped
# because they were out of date (content differs but overwrite = FALSE).
drift_note <- function(n_stale) {
  if (n_stale > 0) {
    sprintf(
      " %d file(s) out of date -- re-run with overwrite = TRUE to refresh.",
      n_stale
    )
  } else {
    ""
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x
