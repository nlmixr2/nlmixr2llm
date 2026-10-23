# List the files that make up a skill

A skill is a directory: \`SKILL.md\` plus any supporting files
(typically \`references/\*.md\`) that give an agent extra depth on
demand. Multi-file installers such as \[install_claude_code()\] copy the
whole directory.

## Usage

``` r
list_skill_files(task)
```

## Arguments

- task:

  One of \[list_tasks()\].

## Value

Character vector of paths relative to the skill directory, with
\`SKILL.md\` first.

## Examples

``` r
list_skill_files("interop")
#> [1] "SKILL.md"                          "references/babelmixr2-backends.md"
#> [3] "references/monolix.md"             "references/nonmem.md"             
```
