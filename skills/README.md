# Agent Skills for Hibiki

Six skills in the [Agent Skills](https://agentskills.io) format: a `SKILL.md`
with a short body, and a `references/` directory an agent opens only when it
needs the detail. They are condensed, agent-oriented digests of the
[documentation site](https://planetaska.github.io/hibiki/); every reference
ends with a link to the page it condenses.

| Skill | Load it for |
| --- | --- |
| `hibiki` | the core gem: `state`, `derived`, `effect`, batching, equality, class-based reactivity, threads. Also names which sibling to load. |
| `hibiki-rails` | channels, islands, the JS client, broadcast helpers, loading state, ActiveRecord, troubleshooting |
| `hibiki-rails-forms` | `ReactiveForm`, nested forms, multi-select, file uploads |
| `hibiki-rails-scaffold` | every `hibiki:rails:*` generator, the CRUD scaffold and its options, the query object, post-install notices |
| `hibiki-rails-motion` | enter and leave transitions, `data-motion`, the `hbk-*` utilities |
| `hibiki-phlex` | reactive Phlex components with `Hibiki::Phlex.render_effect` |

## Install

The [`skills` CLI](https://github.com/vercel-labs/skills) reads this directory
and installs into Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot,
OpenCode and some seventy other agents.

List the skills:

```sh
npx skills add planetaska/hibiki --list
```

Install all six into the current project, for every agent it detects:

```sh
npx skills add planetaska/hibiki --all
```

Install one skill, for one agent, globally:

```sh
npx skills add planetaska/hibiki --skill hibiki-rails-forms -a claude-code --global
```

Common agent ids: `claude-code`, `codex`, `gemini-cli`, `cursor`,
`github-copilot`, `opencode`, `windsurf`, `zed`.

Without the CLI, copy a skill directory into your agent's skills folder:
`.claude/skills/` for Claude Code, `.agents/skills/` for Codex, Cursor and
Copilot, or the agent's own global folder.

## Update

Run the same `npx skills add` command again after a release. The
`metadata` block in each `SKILL.md` names the gem versions the skill
describes; `bundle exec rake skills:check` in this repo fails when those fall
behind the gems or the docs.
