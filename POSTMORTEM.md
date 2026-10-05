---
# ---- Fill every field. Use `unavailable` (with a reason in tokens_source) rather than guessing. ----
game_title: "Space Mini Arena"
twist_one_liner: "ARENA, but ricochet mechanic in space"            # "ARENA, but ..."
twist_category: "| shooter | enemies | boss | points system | health bar | level ups (with trade offs) | strategy |"             # rule-bender | enemies | player-progression | world | other
twist_from_ideas_list: yes      # yes | adapted | no
how_far_from_arena: "substantial"         # small-twist | substantial | barely-recognizable

# Tools and models (lists; exact names as the tool shows them)
tools: [claude-web]                      # e.g. [claude-code, chatgpt-web]
models: [claude-sonnet-5]                     # e.g. [claude-sonnet-5, gpt-5-mini]
primary_model: "claude-sonnet-5"              # the one that did most of the work
plan: "free"                       # free | student | paid-personal | api | none
agent_instructions_file: no    # yes | no  (CLAUDE.md, AGENTS.md, .cursorrules, ...)

# Totals (must match jam-log.csv)
sessions: 4
total_minutes: 0
total_prompts: 0
total_tokens_in: unavailable             # or unavailable
total_tokens_out: unavailable            # or unavailable
tokens_source: "unavailable (used claude web)"              # ccusage | cost-command | dashboard | cli-summary | estimated | unavailable (+ why)

# Your estimate of who wrote the code in the final build (should add to 100)
code_share_llm_pct: claude web (95%)          # accepted from an LLM with little or no change
code_share_mixed_pct: 0        # LLM-generated then substantially edited by you
code_share_hand_pct: 5%         # written by you

# Before this jam
odin_experience_before: none     # none | under-10h | 10-50h | over-50h
llm_coding_before: occasional          # never | occasional | weekly | daily
gamedev_experience_before: none  # none | a-tutorial | a-few-small-games | shipped-something

transcripts_shared: no         # yes | no  (optional, ungraded)
---

# Postmortem — <game title>

> Your own words. Grammar and spelling help from a tool is fine; the argument
> and the evidence are yours. Aim for 1-2 pages plus the table.

## 1. The game

One paragraph: what your game is and how to play it. Then what you **kept**,
**changed**, **removed** and **added** compared with ARENA.

**Where is the depth?** Answer the three questions from the README: the new
**decision** the twist creates, the **trade-off** behind it, and what an
**expert** does differently from a beginner. Use what you saw players do at
the Monday showcase as evidence.

My arena is a shooter game with a theme of space. It main idea is that the player is the main ufo shooter, and it defeats alien ufos that are chasing it. If it crashes into an alien ufo it loses health. 

## 2. Your setup

Which tools and models, and **why** those (cost, familiarity, a friend's
advice...). Did you give the agent a project instruction file, the Raylib
binding, docs, example code? Paste the instruction file, or its key lines, if
you used one.

## 3. Feature by feature

One row per feature you built. The first rows are ARENA's parts; drop the ones
you removed, and add a row for each feature of your own.
`who` = `llm`, `mixed` or `me`. `first try` = did the first LLM answer work
without changes? `help` = 1 (got in the way) - 5 (did it well).

| feature | who | prompts | first try? | minutes | help 1-5 | note |
|---|---|--:|---|--:|:--:|---|
| window, loop, game states, restart | claude-web | 1 | yes | 10 | 4 | helped a lot with base code |
| player movement | claude-web | 1 | yes | 10 | 5 | |
| shooting | claude-web | 2 | no | 15 | 5 | |
| enemies and spawning | mixed | 2 | no | 20 | 3 | |
| health, damage, hit feedback | mixed | 3 | no | 15 | 2| |
| difficulty over time | claude-web | 5 | yes | 50 | 4 | |
| HUD | claude-web | 4 | yes | 20 | 5 | |
| (optional) sprites / sound | mixed | 2 | yes | 30 | 4| i found the sprites/sound, asked claude how to incorporate in code|
| ricochet off walls | claude-web | 2 | yes | 25 | 5 | |
| clone addition | mixed | 2 | no | 20 | 3 | took time to get this feature right|
| random drops (sheild, speed up, additional health, freeze, bomb) | mixed | 8 | no | 30 | 4 | |
| power up (ricochet off) | claude-web | 1 | yes | 5 | 5 | |
| boss (boss power ups when defeated boss) | claude-web | 3 | yes | 30 | 5 | |
| scoreboard | claude-web | 1 | yes | 5 | 5 | |

## 4. Where the LLM sped you up

The easy parts. Name the features, the session number from `jam-log.csv` or
the commit, and estimate how long it would have taken you without it.

## 5. Where it did not help

The hard parts. What was the problem, what did you try (prompts, other models,
docs, a classmate, doing it by hand), and what finally worked? Was the
difficulty Odin, Raylib, game design, tuning the feel, or the tool itself?

## 6. One LLM-introduced bug: found, fixed, verified

- **The bug**: what it did wrong, and the code (a short excerpt or a commit link).
- **How you noticed**.
- **The fix**: the code after.
- **How you know it is fixed**: the evidence (debug draw, printed values, a
  test, a before/after clip or screenshot in the repo).

## 7. Pitch vs. delivered

Paste your Wednesday pitch. What survived, what was cut, what was added, and why.
What did you change after the Monday showcase, based on how people played it?

## 8. Improving the pipeline

If you did another jam next week with the same tools, what would you change?
Be concrete: setup, instruction files, prompting habits, when to use the LLM
and when not, commit rhythm, how you verify, which model for which job.
What would you want **from the tools** that they do not do today?

## 9. Anything else

Optional: what surprised you, what you learned about Odin, Raylib or game
development, what you would tell next year's class.
