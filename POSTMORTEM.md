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
total_minutes: 310
total_prompts: 44
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

My Arena is a top-down surivival shooter where bullets can be used as a weapon. The main idea is to move around the arena using WASD, and aim with the mouse, and shoot with the left click. Pawn enemies constantly spawn and chase you, hile a boss enemy appears every sixty seconds. The run only ends when health reaches zero. A main feature  include, bullets ricocheting off the edges and coming back to you.  A mirror clone, timed pickups, and boss-kill upgrades are also included. A scoreboard is also displayed. What's kept is the main core loop of move, aim, shoot, and survive chasing enemies. What's added is that bullets that ricochet can also harm you, the player. No core feature was removed. Some added features are, pickups (sheild, health, freezse, speed, and bomb). Bosses that scale in health, and a six-option upgrade menu after each kill (with trade-offs). The longer a player survives, the more the drop rates increase.

The depth in this game is in the constant decision making the player has to do in order to survive longer and gain more points. Such as where to stand when to shoot, how much bullets to shoot, which direction to aim at. What is a risky shot? Every pickup also forces the player to make a choice: is it worth leaving a safe position to go grab it? Where should they place the bomb in order to not get hurt themselves and defeat the most pawns? More  decision making comes from each boss kill. Thesea are the major trade offs:

The trade-off. Almost nothing is free:

Shield: immune to damage, but you move at 70% speed.


Freeze: enemies stop, but your guns fire at half speed, and frozen enemies still hurt on contact.


Speed boost: you move 1.5x faster, but your guns are 1.4x slower.


Bomb: it kills everything within 300 px after a 1.5 s fuse, but it hurts you if you're within 130 px when it blows.


More bounces and big bullets: more kills from bank shots, but more bounced bullets that can hit you.


Big targets: pawns are easier to hit but also bump into you more easily.


Clone: it mirrors your position across the arena center, so where you stand also decides where it fights.

The mastery: As the player gets more experienced, they will become more strategic about how much bullets they should shoot, and from where. They will also know which drops are worth it and which ones are not. For example, a more experienced player would analyze whether its safe to leave their spot to go for a health drop or not, and whether doing so would allow them to live longer. They would also plant their bombs in more efficient places, rather than a new player who would plant their bomb as soon as they get them. A mastered player would also take advantage of the no-ricochet window, whereas a new player would need time to get use to it. 

## 2. Your setup

I  used Claude-web since I am most familiar with it, and since it helps me generate code in neat files. I did not give the code any project instruction file, just initially asked it to help me generate a basic arena game with certain features.

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

The LLM helped me most with generating the base game, endless mode, scoreboard, ricochet bullets, and mirror clone. It also helped me with the drop features, and boss upgrade meny options.

I would say this is roughly 12-14 hours of work, and with the LLM it was done in about five hours of sessions (310 minutes). Since a lot of the features were repetitive, such as the drops and the upgrade options, the process was sped up some more. 

## 5. Where it did not help

The initial game that the LLM gave me was too difficult to complete. So I had to fine tune a lot of the parameters myself and test it many times in order to get the game to be playable for up to three minutes and more in a single round without the player dying immedietely. I had to adjust parameters such as ENEMY_BASE_SPEED and SPAWN_RAMP.

Another problem I faced was with the rotation of the sprite when it shoot. Initally, the LLM gave me a circle as the player, but when I introduced a spaceship sprite, it was hard to figure out the rotation and how it match the direction in where it shot a bullet. The LLM wasn't able to see the sprite so I had to fix this part myself.

Every change I made needed my own testing, since LLM can't run it. So after every feature I worked with on the LLM, I had to test thoroughly and make sure it was working properly myself.

## 6. One LLM-introduced bug: found, fixed, verified

While I was adding a sound to the shoot, I was facing a difficulty. Becuase the shot rate is high in the game, every shot cut off the previous one, resulting in a warped sound. I noticed it when I was testing the game after adding the sound.

Code: p.shoot_timer = fire_cooldown(g)
rl.PlaySound(assets.shoot_sfx)

Fix: p.shoot_timer = fire_cooldown(g)
play_shoot()

Before:

<video controls width="640" loop playsinline
       poster="assets/recordings/bug_before.png">
  <source src="assets/recordings/bug_before.webm" type="video/webm">
  <source src="assets/recordings/bug_before.mp4" type="video/mp4">
  Your browser doesn't support video.
</video>

After: 

<video controls width="640" loop playsinline
       poster="assets/recordings/bug_after.png">
  <source src="assets/recordings/bug_after.webm" type="video/webm">
  <source src="assets/recordings/bug_after.mp4" type="video/mp4">
  Your browser doesn't support video.
</video>

## 7. Pitch vs. delivered

Wednesday, my code was in its beginning stages. Only the basics, such as shoot and chasing enemies. Everything survived, but much was added. The game needed creativity and originality. Along with a polished finish. After Monday, I changed the difficulty and how fast the enemies chase the player. I also added more drops. 

## 8. Improving the pipeline

The main thing I would do is use an LLM that can run code. I would move from claude-web to something like Claude Code, to be used directly within the editor. This would save lots of time, having to constantly run the code and debug it myself.

I would set up the projects folders (such as assets) properly before I ask the LLM for the first prompt, to avoid confusion during the process and make sure everything is in the right place.

I'd also write an instruction file. Such as CLAUDE.md to give the LLM. In this file, I'd have existing patterns in can pickup and make sure it organized paramters in the way I want it too. I would also advise it to use helpers whenever possible.

A prompting habit I would change is to make the prompts more direct. I made ambigous prompts that led to confusion sometimes, and the LLM did not return what I wanted. I'd also make sure that the LLM knew what I was looking for in the feature. Such as a trade off instead of just a power up.

I think I already had a pretty solid grasp of when to use the LLM and not. I use the LLM for boilerplate, pattern-following features, UI layout, and to compile errors. By hand I should do it when there is difficulty fine tuning involved, and how I want the game to look and feel.
 Also deciding what the depth is, and the features I want in my game is something I do myself.

I would make big changes when using github. Instead of commiting together, I would commit after every feature.

I'd like for the tools to run and see the game for themself. I would also like the tools to be able to take a look at the assets and what its dealing with. A big thing I'd want from tools is to be able to token count per session, so that the CSV can be filled in properly. This is why I'd change to Claude Code. 

## 9. Anything else

Optional: what surprised you, what you learned about Odin, Raylib or game
development, what you would tell next year's class.

Writing the code isn't the hard part, as much as finding out what went wrong while playing is. While LLM's can get you far, it's important to be able to constantly test and see how the game is doing.

Raylib pleasantly surprised me with how easy it made loading assets into the game.

Another thing I found is that basing the game off one big feature is a good strategy. As for me, I chose ricochet. Then choosing what came after became easier.

For next years class, I'd say get the build and asets working and accounted for before starting to prompt is the way to go.  Keep prompts small, and avoid ambiguity. Play after every change. Commit after every change. Don't let the model decide what is fun and how the game should feel. That is entirely up to you.