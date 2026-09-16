---
title: Agent skills
nav_order: 5
---

# Agent skills

A coding agent that helps you with Hibiki has the same problem you had on
your first day: the answers are on this site, spread over thirty pages, and
the traps that matter are easy to miss. Agent skills fix that. A skill is a
directory with a `SKILL.md` file, whose short body an agent reads once it
decides the skill applies, and a `references/` directory it opens only when
it needs the detail. The format is the open
[Agent Skills](https://agentskills.io) standard, which Claude Code, Codex,
Gemini CLI, Cursor, GitHub Copilot, OpenCode and many other agents read.

Hibiki ships six skills in the
[`skills/`](https://github.com/planetaska/hibiki/tree/main/skills)
directory of the core repository, one per area. Each is a condensed,
agent-oriented digest of the pages here, and every reference file ends with
a link to the page it condenses, so an agent that wants the full story knows
where to find it.

| Skill | What it covers |
| ----- | -------------- |
| `hibiki` | the core gem: `state`, `derived`, `effect`, batching, equality, class-based reactivity, the threading model. It also tells the agent which sibling skill to load for the Rails side. |
| `hibiki-rails` | channels, islands, the JS client, broadcast helpers, loading state, working with ActiveRecord, troubleshooting |
| `hibiki-rails-forms` | `ReactiveForm`, nested forms, multi-select associations, file uploads |
| `hibiki-rails-scaffold` | every `hibiki:rails:*` generator, the CRUD scaffold and its options, the query object, the post-install notices |
| `hibiki-rails-motion` | enter and leave transitions, `data-motion`, the `hbk-*` utilities |
| `hibiki-phlex` | reactive Phlex components with `Hibiki::Phlex.render_effect` |

## Installing

The [`skills` CLI](https://github.com/vercel-labs/skills) reads the
directory straight from GitHub and installs into every agent it finds on
your machine. To see the six before installing anything:

```sh
npx skills add planetaska/hibiki --list
```

To install all six into the current project:

```sh
npx skills add planetaska/hibiki --all
```

To install one skill, for one agent, in that agent's global folder rather
than the project:

```sh
npx skills add planetaska/hibiki --skill hibiki-rails-forms -a claude-code --global
```

The agent ids you are most likely to want are `claude-code`, `codex`,
`gemini-cli`, `cursor`, `github-copilot`, `opencode`, `windsurf` and `zed`.

Without the CLI, copy a skill directory into your agent's skills folder:
`.claude/skills/` for Claude Code, `.agents/skills/` for Codex, Cursor and
Copilot, or the global folder your agent documents.

## Which skill an agent loads

Each skill's description names the situations it is for, and an agent picks
from those descriptions on its own. A question about a derived value that
never recomputes loads `hibiki`; a request to add a live edit form loads
`hibiki-rails-forms`; a scaffold command loads `hibiki-rails-scaffold`. You
can also name a skill directly, in Claude Code as `/hibiki-rails`, to load
it for the current task.

The `hibiki` skill carries the one table of versions the family is tested
against, and the map of which sibling to load when. The others state only
their own gem's version and point back to it.

## Keeping them current

The `metadata` block at the top of each `SKILL.md` names the gem versions
the skill describes. In the core repository, `bundle exec rake skills:check`
compares those against `Hibiki::VERSION` and the newest row of
[Version lockstep]({{ "/version-lockstep/" | relative_url }}), validates the
frontmatter against the Agent Skills specification, and resolves every link,
so a release that forgets the skills fails the default `rake` task. After a
release, run the same `npx skills add` command again to pick up the new
copies.
