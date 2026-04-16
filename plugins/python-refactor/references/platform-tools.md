# Platform Tool Mapping

Skills use Claude Code tool names by default.
On GitHub Copilot CLI, substitute the equivalent tool as shown.

| Claude Code | GitHub Copilot CLI | Notes                              |
|-------------|--------------------|------------------------------------|
| Bash        | runCommand         | Shell commands, parallel processes |
| Read        | readFile           | Read file contents                 |
| Write       | writeFile          | Write or overwrite a file          |
| Edit        | editFile           | Patch file content                 |
| Grep        | searchFiles        | Regex/pattern file search          |
| Glob        | listFiles          | File pattern matching              |
| Agent       | spawnSubagent      | Dispatch isolated subagent         |
| Skill       | skill              | Invoke another skill by name       |
| TodoWrite   | createTask         | Task tracking within session       |

## Skill discovery paths

| Platform       | Project-scoped path              | Personal path                       |
|----------------|----------------------------------|-------------------------------------|
| Claude Code    | `.claude/skills/<name>/`         | `~/.claude/skills/<name>/`          |
| GitHub Copilot | `.github/skills/<name>/`         | `~/.copilot/skills/<name>/`         |

## Plugin namespace (Claude Code only)

When installed as a plugin (with plugin.json), all skills are namespaced:
  /python-refactor:orchestrate
  /python-refactor:measure
  /python-refactor:hunt-bugs
  /python-refactor:architecture
  /python-refactor:plan-refactor

On Copilot CLI (standalone, no plugin.json), skills are invoked without namespace:
  /orchestrate
  /measure
  /hunt-bugs
  /architecture
  /plan-refactor

Or reference them by description in a chat prompt.
