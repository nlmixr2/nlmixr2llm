# Build a combined system prompt for use with any LLM client

Concatenates the combined \`nlmixr2verse\` agent and the per-task skill
content into a single character string suitable for use as a system
prompt with \`ellmer\`, the Anthropic SDK, the OpenAI SDK, or any other
LLM client. YAML frontmatter is stripped so the result is plain
markdown.

## Usage

``` r
system_prompt(
  tasks = NULL,
  include = c("both", "agents", "skills"),
  references = FALSE
)
```

## Arguments

- tasks:

  Character vector of tasks whose skills to include. Defaults to all
  available tasks (see \[list_tasks()\]).

- include:

  Which content to include: \`"both"\` (default), \`"agents"\`, or
  \`"skills"\`.

- references:

  If \`TRUE\`, also append each selected skill's supporting reference
  files (see \[list_skill_files()\]) after its \`SKILL.md\`. Defaults to
  \`FALSE\`, which keeps the prompt compact.

## Value

A length-one character string.

## Details

There is a single ecosystem-wide agent (\`nlmixr2verse\`) rather than
one per task, so when agents are requested it is always included in full
regardless of \`tasks\`; \`tasks\` only subsets the skills.

## See also

\[list_tasks()\], \[get_agent()\], \[get_skill()\]

## Examples

``` r
prompt <- system_prompt(tasks = "simulation")
nchar(prompt)
#> [1] 18183
```
