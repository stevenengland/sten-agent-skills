# Sten Skills

This repository contains custom skills and resources, packaged as
installable plugins for **Claude Code** and **GitHub Copilot CLI**.

## Plugins

| Plugin | Description |
|---|---|
| [`stenswf`](plugins/stenswf/README.md) | Opinionated SDLC bundle: PRD → slice issues → plan → ship → review → apply, plus always-on craft skills (tdd, clean-code, lint-escape, architecture, brevity, …). |
| [`python-refactor`](plugins/python-refactor/README.md) | Agentic Python codebase analysis suite (complexity, PBT bug hunting, architecture RFCs, refactor plan). |

## Install

### GitHub Copilot CLI

Copilot CLI only supports plugins via a registered marketplace — direct
install from a path or `OWNER/REPO:PATH` is no longer supported.

```bash
# Register this repo as a marketplace (once per machine)
copilot plugin marketplace add stevenengland/sten-agent-skills

# Browse and install
copilot plugin marketplace browse sten-agent-skills-marketplace
copilot plugin install stenswf@sten-agent-skills-marketplace
copilot plugin install python-refactor@sten-agent-skills-marketplace
```

### Claude Code

```bash
claude /plugin install ./plugins/stenswf
claude /plugin install ./plugins/python-refactor

# Or directly from GitHub:
claude /plugin install stevenengland/sten-agent-skills:plugins/stenswf
```

See each plugin's README for namespace prefix, command reference, and
project-scoped install options.

## Structure

```
sten-agent-skills/
  plugins/          # Installable plugins (stenswf, python-refactor)
  skills/           # Standalone skills (not bundled)
  frameworks/       # Reference frameworks studied during design
  research/         # Design notes and token-efficiency research
```

## Contributing

Feel free to add new skills and improve existing ones.
