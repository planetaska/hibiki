---
title: Agent skills
nav_order: 5
---

# Agent skills

If you write Hibiki code with a coding agent such as Claude Code, Codex or
Cursor, install the Hibiki skills first. Hibiki is a young library, and an
agent has seen little of it in training. Asked to write Hibiki code without
help, it fills the gaps with guesses, and it walks into the mistakes this
site warns about.

A skill is a folder of instructions written for an agent. Its main file,
`SKILL.md`, opens with a description of the tasks the skill is for. The
agent keeps that description in view and loads the rest only when a task
matches: first the body of `SKILL.md`, a short summary, and then the files
under `references/`, one at a time, as it needs the detail. A skill the
agent never uses costs it only the description.

The format is the open [Agent Skills](https://agentskills.io) standard,
which Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot, OpenCode and
many other agents read.

## The six skills

Hibiki is three gems, and the skills follow them. `hibiki` is the signals
library itself, plain Ruby with no opinion about the web; the
[introduction]({{ "/introduction/" | relative_url }}) shows it in a dozen
lines. `hibiki_rails` uses signals to keep the interactive parts of a Rails
page up to date: the state lives on the server, and the server re-renders
the HTML and sends it to the browser whenever the state changes. The
[Rails introduction]({{ "/rails-introduction/" | relative_url }}) explains
how. `hibiki_phlex` re-renders a [Phlex](https://www.phlex.fun) component
whenever a signal it read changes.

The core gem has one skill and so does Phlex. The Rails gem is large enough
to need four.

| Skill | Gem | What it covers |
| ----- | --- | -------------- |
| `hibiki` | `hibiki` | The three primitives, `state`, `derived` and `effect`; batching several writes; deciding when two values count as equal; signals as class attributes; threads. |
| `hibiki-rails` | `hibiki_rails` | Channels and islands, the two halves of a live part of a page; the JavaScript client; broadcasting to several browsers; loading state; ActiveRecord; troubleshooting. |
| `hibiki-rails-forms` | `hibiki_rails` | Live forms with `ReactiveForm`, including nested forms, multi-select associations and file uploads. |
| `hibiki-rails-scaffold` | `hibiki_rails` | Every `hibiki:rails:*` generator, among them a CRUD scaffold as general as `rails g scaffold`, with its options and the notices it prints. |
| `hibiki-rails-motion` | `hibiki_rails` | Enter and leave transitions for elements the server adds or removes: `data-motion` and the `hbk-*` CSS utilities. |
| `hibiki-phlex` | `hibiki_phlex` | Reactive Phlex components with `Hibiki::Phlex.render_effect`. |

Each skill condenses pages of this site, and every file under `references/`
ends with a link to the page it condenses, so an agent that wants the full
account can find it. The source is the
[`skills/`](https://github.com/planetaska/hibiki/tree/main/skills) directory
of the core repository.

## Installing the skills

The [`skills` CLI](https://github.com/vercel-labs/skills) reads that
directory straight from GitHub and installs into every agent it finds on
your machine. To install all six into the current project:

```sh
npx skills add planetaska/hibiki --all
```

To list the six without installing anything:

```sh
npx skills add planetaska/hibiki --list
```

To install one skill, for one agent, in that agent's global folder rather
than the project:

```sh
npx skills add planetaska/hibiki --skill hibiki-rails-forms -a claude-code --global
```

The agent ids you are most likely to want are `claude-code`, `codex`,
`gemini-cli`, `cursor`, `github-copilot`, `opencode`, `windsurf` and `zed`.

You can also install by hand. Copy a skill's directory from the repository
into your agent's skills folder: `.claude/skills/` for Claude Code,
`.agents/skills/` for Codex, Cursor and Copilot, or the global folder your
agent documents.

## How an agent chooses a skill

Once the skills are installed you have nothing more to do. The agent matches
each task against the six descriptions and loads the skill that fits. Ask
why a derived value never recomputes, and it loads `hibiki`. Ask for a live
edit form, and it loads `hibiki-rails-forms`. Ask it to run a scaffold
command, and it loads `hibiki-rails-scaffold`.

When a task spans two areas, the `hibiki` skill directs the agent. It holds
a table that maps what the agent is looking at, a channel file or a
generator command, to the skill that covers it.

You can also load a skill yourself by name. In Claude Code, type
`/hibiki-rails`.

## Updating after a release

A skill describes particular versions of the gems, and the `metadata` block
at the top of its `SKILL.md` names them. The `hibiki` skill also lists the
versions of the three gems that are tested together. When you upgrade a gem,
run the same `npx skills add` command again to replace your copies.

The skills in the repository cannot fall behind the gems. The repository's
default `rake` task fails unless every skill names the current gem
versions, as recorded in the newest row of
[Version lockstep]({{ "/version-lockstep/" | relative_url }}), and every
link in every skill resolves.
