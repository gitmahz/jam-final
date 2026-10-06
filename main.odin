package arena

// ARENA: ricochet bullets + an auto-targeting mirror clone
// Run with:  odin run .
// Controls:  WASD / arrows = move, mouse = aim, hold left click = shoot,
//            SPACE or right click = plant a bomb you picked up (run away!),
//            1-6 or click = pick a boss upgrade, R = restart

import "core:fmt"
import "core:math/linalg"
import "core:mem"
import rl "vendor:raylib"

WINDOW_W :: 960
WINDOW_H :: 640
PANEL_W :: 230 // side panel to the right of the arena; WINDOW_W stays the arena width

Vec2 :: rl.Vector2

State :: enum {
	Playing,
	Upgrade, // paused after a boss dies: pick one upgrade
	Lost,
}

// One finished game. An all-zero entry means "empty slot".
ScoreEntry :: struct {
	score:   i32, // enemies killed
	seconds: i32, // how long you survived
}

SCOREBOARD_SIZE :: 8
Scoreboard :: [SCOREBOARD_SIZE]ScoreEntry

Player :: struct {
	pos:         Vec2,
	radius:      f32,
	speed:       f32,
	health:      int,
	max_health:  int,
	hurt_timer:  f32, // invincibility frames after a hit
	shoot_timer: f32, // cooldown until next shot
	shield_timer: f32, // seconds of shield left (0 = no shield)
	aim_angle:   f32, // degrees; direction of the last shot, used to rotate the sprite
}

Assets :: struct {
    background: rl.Texture2D,
	player:  rl.Texture2D,
	enemy:   rl.Texture2D,
	boss:    rl.Texture2D,
	bullet:  rl.Texture2D,
    shoot_sfx:  rl.Sound,
}

assets: Assets

load_assets :: proc() {
    assets.background = rl.LoadTexture("assets/background.png")
	assets.player = rl.LoadTexture("assets/ufo_game_art/player_ship.png")
	assets.enemy  = rl.LoadTexture("assets/ufo_game_art/enemy_1.png")
	assets.boss   = rl.LoadTexture("assets/ufo_game_art/boss_0.png")
	assets.bullet = rl.LoadTexture("assets/ufo_game_art/player_shot_0.png")
    assets.shoot_sfx = rl.LoadSound("assets/sounds/laserShoot.wav")
	rl.SetSoundVolume(assets.shoot_sfx, 0.4) // shooting is frequent, so keep it quiet

}

unload_assets :: proc() {
    rl.UnloadTexture(assets.background)
	rl.UnloadTexture(assets.player)
	rl.UnloadTexture(assets.enemy)
	rl.UnloadTexture(assets.boss)
	rl.UnloadTexture(assets.bullet)
    rl.UnloadSound(assets.shoot_sfx)
}

// Draw a texture centred on `pos`, scaled so its width/height span 2*radius.
// `rotation` is in degrees. `tint` defaults to white (no tint).
draw_sprite :: proc(tex: rl.Texture2D, pos: Vec2, radius: f32, rotation: f32 = 0, tint: rl.Color = rl.WHITE) {
	size := radius * 2
	src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
	dst := rl.Rectangle{pos.x, pos.y, size, size}
	origin := Vec2{radius, radius} // rotate around the centre
	rl.DrawTexturePro(tex, src, dst, origin, rotation, tint)
}

// A pickup lying somewhere in the arena. Touch it to get a shield.
ShieldDrop :: struct {
	active: bool,
	pos:    Vec2,
	life:   f32, // seconds before it vanishes if not picked up
}

// A heart pickup lying somewhere in the arena. Touch it to heal.
HealthDrop :: struct {
	active: bool,
	pos:    Vec2,
	life:   f32, // seconds before it vanishes if not picked up
}

// A snowflake pickup lying somewhere in the arena. Touch it to freeze every enemy.
FreezeDrop :: struct {
	active: bool,
	pos:    Vec2,
	life:   f32, // seconds before it vanishes if not picked up
}

// A bomb pickup lying somewhere in the arena. Grab it, then trigger it yourself.
BombDrop :: struct {
	active: bool,
	pos:    Vec2,
	life:   f32, // seconds before it vanishes if not picked up
}

// A speed pickup lying somewhere in the arena. Touch it to run faster for a while.
SpeedDrop :: struct {
	active: bool,
	pos:    Vec2,
	life:   f32, // seconds before it vanishes if not picked up
}

Bullet :: struct {
	pos:        Vec2,
	vel:        Vec2,
	life:       f32,
	bounces:    int, // wall hits so far; once > 0 the bullet can hurt the player
	from_clone: bool, // fired by the clone, not by the player
}

Enemy :: struct {
	pos:        Vec2,
	radius:     f32,
	speed:      f32,
	health:     int, // normal enemies have 1; bosses have a lot more
	max_health: int,
	boss:       bool,
}

// The clone mirrors your position across the arena centre and
// automatically shoots the nearest enemy it can see.
Clone :: struct {
	active:      bool,
	life:        f32, // seconds left before it disappears
	pos:         Vec2,
	shoot_timer: f32,
	aim_angle:   f32, // degrees; direction of the clone's last shot
}

Game :: struct {
	state:       State,
	player:      Player,
	clone:       Clone,
	bullets:     [dynamic]Bullet,
	enemies:     [dynamic]Enemy,
	spawn_timer: f32,
	elapsed:     f32,
	score:       int,
	next_clone_at: f32, // g.elapsed value when the next clone appears
	shield_drop:    ShieldDrop,
	next_shield_at: f32, // g.elapsed value when the next shield drops
	health_drop:    HealthDrop,
	next_health_at: f32, // g.elapsed value when the next health drop appears
	scores:         Scoreboard, // best games, kept across runs (saved to SCORES_FILE)
	last_rank:      int, // where the game that just ended placed (-1 = didn't place)
	next_boss_at:   f32, // g.elapsed value when the next boss drops
	bosses_spawned: int, // each boss has more health than the last
	freeze_drop:    FreezeDrop,
	next_freeze_at: f32, // g.elapsed value when the next freeze drop appears
	freeze_timer:   f32, // seconds of freeze left (0 = enemies move normally)
	bomb_drop:      BombDrop,
	next_bomb_at:   f32, // g.elapsed value when the next bomb drop appears
	has_bomb:       bool, // true once you've picked one up and haven't used it yet
	bomb_flash:     f32, // seconds left of the blast animation (0 = none)
	bomb_origin:    Vec2, // where the blast started (for the expanding ring)
	ricochet_off_timer: f32, // seconds of "no ricochet" power-up left (0 = off)
	next_powerup_score: int, // score needed to trigger the next no-ricochet power-up
	bomb_planted:   bool, // a bomb is on the ground with its fuse burning
	bomb_fuse:      f32, // seconds until the planted bomb blows
	bomb_pos:       Vec2, // where it was planted
	pending_upgrade: bool, // a boss died this frame: open the upgrade menu
	up_bounces:     int, // upgrade levels picked so far
	up_fire:        int,
	up_shield:      int,
	up_big:         int, // "big targets" upgrade level (pawns are bigger)
	up_bullet:      int, // "big bullets" upgrade level
	speed_drop:     SpeedDrop,
	next_speed_at:  f32, // g.elapsed value when the next speed drop appears
	speed_timer:    f32, // seconds of speed boost left (0 = normal speed)
}

// Which way the ship PNG points before any rotation, as a correction in degrees:
//   0 = art points right, 90 = art points up, 180 = art points left, -90 = art points down
// If the ship faces the wrong way, change this one number.
SHIP_ART_ANGLE :: 90.0

// ---------- tuning knobs: change these first ----------
FIRE_RATE :: 0.15 // seconds between your shots
BULLET_SPEED :: 650.0
BULLET_LIFE :: 3.0
BULLET_RADIUS :: 4.0
MAX_BOUNCES :: 3 // bullet disappears after this many wall hits
BULLET_DAMAGE :: 1 // damage to the player from a bounced bullet
CONTACT_DAMAGE :: 1
HURT_COOLDOWN :: 0.8
CLONE_FIRE_RATE :: 0.45 // seconds between clone shots (slower than yours)
CLONE_RANGE :: 500.0 // clone only targets enemies this close to it
CLONE_INTERVAL :: 20.0 // a clone appears this often
CLONE_LIFETIME :: 10.0 // ...and stays this long (set to 15 for no gap)
SHIELD_INTERVAL :: 12.0 // a shield drops somewhere in the arena this often
SHIELD_DROP_LIFE :: 8.0 // it disappears if nobody picks it up in this time
SHIELD_DROP_RADIUS :: 12.0
SHIELD_DURATION :: 5.0 // seconds of damage immunity after pickup
HEALTH_DROP_MIN_INTERVAL :: 15.0 // a health drop appears every MIN..MAX seconds (random)
HEALTH_DROP_MAX_INTERVAL :: 30.0
HEALTH_DROP_LIFE :: 10.0 // it disappears if not picked up in this time
HEALTH_DROP_RADIUS :: 12.0
HEALTH_DROP_AMOUNT :: 1 // health restored on pickup
FREEZE_MIN_INTERVAL :: 20.0 // a freeze drop appears every MIN..MAX seconds (random)
FREEZE_MAX_INTERVAL :: 45.0
FREEZE_DROP_LIFE :: 10.0 // it disappears if not picked up in this time
FREEZE_DROP_RADIUS :: 12.0
FREEZE_DURATION :: 5.0 // seconds every enemy is frozen after pickup
BOMB_MIN_INTERVAL :: 25.0 // a bomb drop appears every MIN..MAX seconds (random)
BOMB_MAX_INTERVAL :: 50.0
BOMB_DROP_LIFE :: 12.0 // it disappears if not picked up in this time
BOMB_DROP_RADIUS :: 12.0
BOMB_FLASH_TIME :: 0.45 // length of the blast animation
BOMB_BOSS_DAMAGE :: 15 // health a bomb takes off each boss caught in the blast
BOMB_FUSE :: 1.5 // seconds between planting the bomb and the explosion
BOMB_RADIUS :: 300.0 // everything this close to the bomb is hit
BOMB_SELF_RADIUS :: 130.0 // ...but if YOU are this close when it blows, it hurts you too
BOMB_SELF_DAMAGE :: 2
FREEZE_FIRE_COOLDOWN_MULT :: 2.0 // while enemies are frozen your guns are this much slower
SHIELD_SPEED_MULT :: 0.7 // while shielded you move at this fraction of normal speed
FIRE_UPGRADE_MULT :: 0.8 // each "faster fire" upgrade multiplies the shot cooldown by this
SHIELD_UPGRADE_BONUS :: 2.5 // each "bigger shield" upgrade adds this many seconds
HEALTH_UPGRADE_AMOUNT :: 2 // each "tougher" upgrade adds this many max hearts

SPEED_MIN_INTERVAL :: 20.0 // a speed drop appears every MIN..MAX seconds (random)
SPEED_MAX_INTERVAL :: 40.0
SPEED_DROP_LIFE :: 10.0 // it disappears if not picked up in this time
SPEED_DROP_RADIUS :: 12.0
SPEED_BOOST_DURATION :: 6.0 // seconds of speed boost after pickup
SPEED_BOOST_MULT :: 1.5 // you move this much faster while boosted...
SPEED_FIRE_COOLDOWN_MULT :: 1.4 // ...but your guns are this much slower (can't sprint and spray)
BULLET_SIZE_UPGRADE :: 0.3 // each "big bullets" upgrade makes bullets this much bigger
PAWN_RADIUS :: 12.0 // size of a normal enemy
PAWN_SIZE_UPGRADE :: 0.15 // each "big targets" upgrade makes pawns this much bigger
DROP_RATE_RAMP :: 0.005 // drops get this much more frequent per second survived (0.005 = +50% per 100s)
DROP_RATE_MAX :: 2.5 // ...up to this many times as often (clone, shield, health, freeze, bomb)

UPGRADE_COUNT :: 6
UPGRADE_NAMES := [UPGRADE_COUNT]cstring{"More bounces", "Faster fire", "Bigger shield", "Tougher", "Big targets", "Big bullets"}
UPGRADE_DESCS := [UPGRADE_COUNT]cstring {
	"Bullets bounce\n1 extra time.\nMore bank shots,\nmore danger.",
	"Shoot 20% faster.\nMore bullets to\ndodge.",
	"Shields last 2.5s\nlonger. You still\nmove slower while\nshielded.",
	"+2 max hearts and\nheal 2 now.",
	"Pawns grow 15%.\nEasier to shoot,\nbut they bump\ninto you easier.",
	"Bullets grow 30%.\nEasier to hit with,\nbut bounced ones\nhit you easier too.",
}
RICOCHET_OFF_SCORE :: 30 // every this many points, the no-ricochet power-up triggers
RICOCHET_OFF_DURATION :: 15.0 // seconds bullets stop ricocheting (they vanish on walls)
// --- enemy pacing: raise these numbers to make the game easier or harder ---
ENEMY_BASE_SPEED :: 70.0 // how fast enemies move at the start
ENEMY_SPEED_RAMP :: 0.4 // extra speed gained per second survived
ENEMY_MAX_SPEED :: 130.0 // speed cap (you move at 280)
ENEMY_SPEED_JITTER :: 15.0 // each enemy gets 0..this extra speed
SPAWN_START_INTERVAL :: 1.6 // seconds between spawns at the start
SPAWN_MIN_INTERVAL :: 0.8 // spawns never get faster than this
SPAWN_RAMP :: 0.006 // how quickly the spawn interval shrinks per second
MAX_ENEMIES :: 25 // no new enemies spawn while this many are alive
BOSS_INTERVAL :: 60.0 // a boss drops this often
BOSS_WARNING :: 10.0 // seconds of warning before it drops
BOSS_HEALTH :: 30 // hits to kill the first boss
BOSS_HEALTH_GROWTH :: 15 // extra health for each later boss
BOSS_SPEED :: 55.0 // slower than normal enemies (90+)
BOSS_CONTACT_DAMAGE :: 2 // hearts lost when a boss touches you
BOSS_SCORE :: 10 // score for killing a boss
SCORES_FILE :: "scores.dat" // created next to the game the first time you die

rand_f32 :: proc() -> f32 {
	return f32(rl.GetRandomValue(0, 10000)) / 10000.0
}

// Seconds from now until the next health drop (random between MIN and MAX).
next_health_delay :: proc(rate: f32) -> f32 {
	return (HEALTH_DROP_MIN_INTERVAL + rand_f32() * (HEALTH_DROP_MAX_INTERVAL - HEALTH_DROP_MIN_INTERVAL)) / rate
}

// Seconds from now until the next bomb drop (random between MIN and MAX).
next_bomb_delay :: proc(rate: f32) -> f32 {
	return (BOMB_MIN_INTERVAL + rand_f32() * (BOMB_MAX_INTERVAL - BOMB_MIN_INTERVAL)) / rate
}

// Seconds from now until the next freeze drop (random between MIN and MAX).
next_freeze_delay :: proc(rate: f32) -> f32 {
	return (FREEZE_MIN_INTERVAL + rand_f32() * (FREEZE_MAX_INTERVAL - FREEZE_MIN_INTERVAL)) / rate
}

// Seconds from now until the next speed drop (random between MIN and MAX).
next_speed_delay :: proc(rate: f32) -> f32 {
	return (SPEED_MIN_INTERVAL + rand_f32() * (SPEED_MAX_INTERVAL - SPEED_MIN_INTERVAL)) / rate
}

// Current bullet size (grows with the "big bullets" upgrade).
bullet_radius :: proc(g: ^Game) -> f32 {
	return BULLET_RADIUS * (1 + BULLET_SIZE_UPGRADE * f32(g.up_bullet))
}

// How much more often things drop: starts at 1x and climbs the longer you survive.
drop_rate :: proc(g: ^Game) -> f32 {
	return min(DROP_RATE_MAX, 1.0 + g.elapsed * DROP_RATE_RAMP)
}

// Current size of a normal enemy (grows with the "big targets" upgrade).
pawn_radius :: proc(g: ^Game) -> f32 {
	return PAWN_RADIUS * (1 + PAWN_SIZE_UPGRADE * f32(g.up_big))
}

reset_game :: proc(g: ^Game) {
	clear(&g.bullets)
	clear(&g.enemies)
	g.state = .Playing
	g.elapsed = 0
	g.score = 0
	g.spawn_timer = 1.0
	g.player = Player {
		pos        = {WINDOW_W / 2, WINDOW_H / 2},
		radius     = 14,
		speed      = 280,
		health     = 10,
		max_health = 10,
	}
	g.clone = {} // starts inactive
	g.next_clone_at = CLONE_INTERVAL
	g.shield_drop = {}
	g.next_shield_at = SHIELD_INTERVAL
	g.health_drop = {}
	g.next_health_at = next_health_delay(1)
	g.last_rank = -1
	g.next_boss_at = BOSS_INTERVAL
	g.bosses_spawned = 0
	g.freeze_drop = {}
	g.next_freeze_at = next_freeze_delay(1)
	g.freeze_timer = 0
	g.bomb_drop = {}
	g.next_bomb_at = next_bomb_delay(1)
	g.has_bomb = false
	g.bomb_flash = 0
	g.ricochet_off_timer = 0
	g.next_powerup_score = RICOCHET_OFF_SCORE
	g.bomb_planted = false
	g.pending_upgrade = false
	g.up_bounces = 0
	g.up_fire = 0
	g.up_shield = 0
	g.up_big = 0
	g.up_bullet = 0
	g.speed_drop = {}
	g.next_speed_at = next_speed_delay(1)
	g.speed_timer = 0
}

// A random point just outside one of the four arena edges.
edge_spawn_pos :: proc(margin: f32) -> Vec2 {
	pos: Vec2
	switch rl.GetRandomValue(0, 3) {
	case 0:
		pos = {rand_f32() * WINDOW_W, -margin} // top
	case 1:
		pos = {rand_f32() * WINDOW_W, WINDOW_H + margin} // bottom
	case 2:
		pos = {-margin, rand_f32() * WINDOW_H} // left
	case:
		pos = {WINDOW_W + margin, rand_f32() * WINDOW_H} // right
	}
	return pos
}

spawn_enemy :: proc(g: ^Game) {
	// enemies get a bit faster the longer you last
	speed := min(ENEMY_MAX_SPEED, ENEMY_BASE_SPEED + g.elapsed * ENEMY_SPEED_RAMP) + rand_f32() * ENEMY_SPEED_JITTER
	append(&g.enemies, Enemy{pos = edge_spawn_pos(30), radius = pawn_radius(g), speed = speed, health = 1, max_health = 1})
}

// Boss: big, slow and tanky. Each one has more health than the last.
spawn_boss :: proc(g: ^Game) {
	hp := BOSS_HEALTH + BOSS_HEALTH_GROWTH * g.bosses_spawned
	append(
		&g.enemies,
		Enemy{pos = edge_spawn_pos(70), radius = 36, speed = BOSS_SPEED, health = hp, max_health = hp, boss = true},
	)
	g.bosses_spawned += 1
}

// Clone: mirror the player's position, then shoot the nearest on-screen enemy in range.
update_clone :: proc(g: ^Game, dt: f32) {
	c := &g.clone

	// appear every CLONE_INTERVAL seconds
	if g.elapsed >= g.next_clone_at {
		c.active = true
		c.life = CLONE_LIFETIME
		c.shoot_timer = 0.3
		// later in the run clones come more often, but always leave a short gap
		g.next_clone_at = g.elapsed + max(CLONE_LIFETIME + 2.0, CLONE_INTERVAL / drop_rate(g))
	}
	if !c.active {
		return
	}

	// expire after CLONE_LIFETIME seconds
	c.life -= dt
	if c.life <= 0 {
		c.active = false
		return
	}

	c.pos = {WINDOW_W - g.player.pos.x, WINDOW_H - g.player.pos.y}

	c.shoot_timer -= dt
	if c.shoot_timer > 0 {
		return
	}

	best := -1
	best_d: f32 = CLONE_RANGE * CLONE_RANGE
	for e, i in g.enemies {
		// ignore enemies that haven't entered the arena yet
		if e.pos.x < 0 || e.pos.x > WINDOW_W || e.pos.y < 0 || e.pos.y > WINDOW_H {
			continue
		}
		d := linalg.length2(e.pos - c.pos)
		if d < best_d {
			best_d = d
			best = i
		}
	}

	if best >= 0 {
		aim := linalg.normalize0(g.enemies[best].pos - c.pos)
		c.aim_angle = linalg.to_degrees(linalg.atan2(aim.y, aim.x))
		append(&g.bullets, Bullet{pos = c.pos, vel = aim * BULLET_SPEED, life = BULLET_LIFE, from_clone = true})
		c.shoot_timer = CLONE_FIRE_RATE
	}
}

// Shield: drop a pickup at a random spot on a timer, grant a shield when touched.
update_shield :: proc(g: ^Game, dt: f32) {
	p := &g.player
	d := &g.shield_drop

	p.shield_timer = max(0, p.shield_timer - dt)

	if g.elapsed >= g.next_shield_at {
		margin: f32 = 40
		d.active = true
		d.life = SHIELD_DROP_LIFE
		d.pos = {
			margin + rand_f32() * (WINDOW_W - 2 * margin),
			margin + rand_f32() * (WINDOW_H - 2 * margin),
		}
		g.next_shield_at = g.elapsed + SHIELD_INTERVAL / drop_rate(g)
	}
	if !d.active {
		return
	}

	d.life -= dt
	if d.life <= 0 {
		d.active = false
		return
	}
	if rl.CheckCollisionCircles(p.pos, p.radius, d.pos, SHIELD_DROP_RADIUS) {
		d.active = false
		p.shield_timer = SHIELD_DURATION + SHIELD_UPGRADE_BONUS * f32(g.up_shield)
	}
}

// Health: drop a heart at a random spot at random intervals, heal when touched.
update_health_drop :: proc(g: ^Game, dt: f32) {
	p := &g.player
	d := &g.health_drop

	if g.elapsed >= g.next_health_at {
		margin: f32 = 40
		d.active = true
		d.life = HEALTH_DROP_LIFE
		d.pos = {
			margin + rand_f32() * (WINDOW_W - 2 * margin),
			margin + rand_f32() * (WINDOW_H - 2 * margin),
		}
		g.next_health_at = g.elapsed + next_health_delay(drop_rate(g))
	}
	if !d.active {
		return
	}

	d.life -= dt
	if d.life <= 0 {
		d.active = false
		return
	}
	// only collect it if you actually need the health
	if p.health < p.max_health && rl.CheckCollisionCircles(p.pos, p.radius, d.pos, HEALTH_DROP_RADIUS) {
		d.active = false
		p.health = min(p.max_health, p.health + HEALTH_DROP_AMOUNT)
	}
}

// Freeze: a snowflake appears at random times. Touching it freezes all enemies in place.
update_freeze :: proc(g: ^Game, dt: f32) {
	p := &g.player
	d := &g.freeze_drop

	g.freeze_timer = max(0, g.freeze_timer - dt)

	if g.elapsed >= g.next_freeze_at {
		margin: f32 = 40
		d.active = true
		d.life = FREEZE_DROP_LIFE
		d.pos = {
			margin + rand_f32() * (WINDOW_W - 2 * margin),
			margin + rand_f32() * (WINDOW_H - 2 * margin),
		}
		g.next_freeze_at = g.elapsed + next_freeze_delay(drop_rate(g))
	}
	if !d.active {
		return
	}

	d.life -= dt
	if d.life <= 0 {
		d.active = false
		return
	}
	if rl.CheckCollisionCircles(p.pos, p.radius, d.pos, FREEZE_DROP_RADIUS) {
		d.active = false
		g.freeze_timer = FREEZE_DURATION
	}
}

// Speed: a pickup appears at random times. Touching it makes you run faster for a few
// seconds, but your guns are slower while it lasts.
update_speed :: proc(g: ^Game, dt: f32) {
	p := &g.player
	d := &g.speed_drop

	g.speed_timer = max(0, g.speed_timer - dt)

	if g.elapsed >= g.next_speed_at {
		margin: f32 = 40
		d.active = true
		d.life = SPEED_DROP_LIFE
		d.pos = {
			margin + rand_f32() * (WINDOW_W - 2 * margin),
			margin + rand_f32() * (WINDOW_H - 2 * margin),
		}
		g.next_speed_at = g.elapsed + next_speed_delay(drop_rate(g))
	}
	if !d.active {
		return
	}

	d.life -= dt
	if d.life <= 0 {
		d.active = false
		return
	}
	if rl.CheckCollisionCircles(p.pos, p.radius, d.pos, SPEED_DROP_RADIUS) {
		d.active = false
		g.speed_timer = SPEED_BOOST_DURATION
	}
}

// Bomb: a pickup appears at random times. Touch it to carry one bomb, then press
// SPACE or right click to PLANT it where you stand. After a short fuse it blasts a
// big circle: enemies inside die (bosses take damage), and if you're still close you
// get hurt too. Lure enemies in, then run.
update_bomb :: proc(g: ^Game, dt: f32) {
	p := &g.player
	d := &g.bomb_drop

	g.bomb_flash = max(0, g.bomb_flash - dt)

	if g.elapsed >= g.next_bomb_at {
		margin: f32 = 40
		d.active = true
		d.life = BOMB_DROP_LIFE
		d.pos = {
			margin + rand_f32() * (WINDOW_W - 2 * margin),
			margin + rand_f32() * (WINDOW_H - 2 * margin),
		}
		g.next_bomb_at = g.elapsed + next_bomb_delay(drop_rate(g))
	}

	if d.active {
		d.life -= dt
		if d.life <= 0 {
			d.active = false
		} else if !g.has_bomb && rl.CheckCollisionCircles(p.pos, p.radius, d.pos, BOMB_DROP_RADIUS) {
			d.active = false
			g.has_bomb = true
		}
	}

	// plant: drops the bomb where you stand and starts the fuse
	if g.has_bomb && !g.bomb_planted && (rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.RIGHT)) {
		g.has_bomb = false
		g.bomb_planted = true
		g.bomb_fuse = BOMB_FUSE
		g.bomb_pos = p.pos
	}

	// fuse burns down, then it blows
	if g.bomb_planted {
		g.bomb_fuse -= dt
		if g.bomb_fuse <= 0 {
			g.bomb_planted = false
			g.bomb_flash = BOMB_FLASH_TIME
			g.bomb_origin = g.bomb_pos
			for ei := len(g.enemies) - 1; ei >= 0; ei -= 1 {
				e := &g.enemies[ei]
				if linalg.length(e.pos - g.bomb_pos) > BOMB_RADIUS + e.radius {
					continue // outside the blast
				}
				if e.boss {
					// bosses survive unless the blast finishes them off
					e.health -= BOMB_BOSS_DAMAGE
					if e.health <= 0 {
						g.score += BOSS_SCORE
						g.pending_upgrade = true
						unordered_remove(&g.enemies, ei)
					}
				} else {
					g.score += 1
					unordered_remove(&g.enemies, ei)
				}
			}
			// the blast hurts you too if you stayed close (a shield protects you)
			if linalg.length(p.pos - g.bomb_pos) < BOMB_SELF_RADIUS && p.shield_timer <= 0 {
				p.health -= BOMB_SELF_DAMAGE
				p.hurt_timer = HURT_COOLDOWN
			}
		}
	}
}

// Seconds between your shots: boss upgrades shorten it, being near frozen enemies lengthens it.
fire_cooldown :: proc(g: ^Game) -> f32 {
	cd: f32 = FIRE_RATE
	for _ in 0 ..< g.up_fire {
		cd *= FIRE_UPGRADE_MULT
	}
	if g.freeze_timer > 0 {
		cd *= FREEZE_FIRE_COOLDOWN_MULT
	}
	if g.speed_timer > 0 {
		cd *= SPEED_FIRE_COOLDOWN_MULT
	}
	return cd
}

upgrade_level :: proc(g: ^Game, i: int) -> int {
	switch i {
	case 0:
		return g.up_bounces
	case 1:
		return g.up_fire
	case 2:
		return g.up_shield
	case 3:
		return (g.player.max_health - 10) / HEALTH_UPGRADE_AMOUNT
	case 4:
		return g.up_big
	case 5:
		return g.up_bullet
	}
	return 0
}

// Screen rectangle of upgrade card i (3 columns x 2 rows, centred in the arena).
upgrade_rect :: proc(i: int) -> rl.Rectangle {
	w, h, gap: f32 = 200, 160, 14
	cols := 3
	total := f32(cols) * w + f32(cols - 1) * gap
	col, row := i % cols, i / cols
	return rl.Rectangle{(WINDOW_W - total) / 2 + f32(col) * (w + gap), 250 + f32(row) * (h + gap), w, h}
}

// Upgrade menu: the game is paused until you pick one (keys 1-6 or click a card).
update_upgrade :: proc(g: ^Game) {
	choice := -1
	if rl.IsKeyPressed(.ONE) {choice = 0}
	if rl.IsKeyPressed(.TWO) {choice = 1}
	if rl.IsKeyPressed(.THREE) {choice = 2}
	if rl.IsKeyPressed(.FOUR) {choice = 3}
	if rl.IsKeyPressed(.FIVE) {choice = 4}
	if rl.IsKeyPressed(.SIX) {choice = 5}
	if rl.IsMouseButtonPressed(.LEFT) {
		m := rl.GetMousePosition()
		for i in 0 ..< UPGRADE_COUNT {
			if rl.CheckCollisionPointRec(m, upgrade_rect(i)) {
				choice = i
			}
		}
	}
	switch choice {
	case 0:
		g.up_bounces += 1
	case 1:
		g.up_fire += 1
	case 2:
		g.up_shield += 1
	case 3:
		g.player.max_health += HEALTH_UPGRADE_AMOUNT
		g.player.health = min(g.player.max_health, g.player.health + HEALTH_UPGRADE_AMOUNT)
	case 4:
		g.up_big += 1
		for &e in g.enemies {
			if !e.boss {
				e.radius = pawn_radius(g) // pawns already on screen grow too
			}
		}
	case 5:
		g.up_bullet += 1
	case:
		return // nothing picked yet
	}
	g.state = .Playing
}

// Read the saved scoreboard (if there is one) using raylib's file helpers.
load_scores :: proc(g: ^Game) {
	size: i32
	data := rl.LoadFileData(SCORES_FILE, &size)
	if data == nil {
		return
	}
	defer rl.UnloadFileData(data)
	if int(size) == size_of(Scoreboard) {
		mem.copy(&g.scores, rawptr(data), size_of(Scoreboard))
	}
}

save_scores :: proc(g: ^Game) {
	rl.SaveFileData(SCORES_FILE, &g.scores, i32(size_of(Scoreboard)))
}

// Insert the game that just ended into the sorted top-N list and save it.
record_score :: proc(g: ^Game) {
	entry := ScoreEntry {
		score   = i32(g.score),
		seconds = i32(g.elapsed),
	}
	g.last_rank = -1
	for i in 0 ..< SCOREBOARD_SIZE {
		slot := g.scores[i]
		is_empty := slot.score == 0 && slot.seconds == 0
		if entry.score > slot.score || is_empty {
			for j := SCOREBOARD_SIZE - 1; j > i; j -= 1 {
				g.scores[j] = g.scores[j - 1] // push lower scores down
			}
			g.scores[i] = entry
			g.last_rank = i
			break
		}
	}
	save_scores(g)
}

update :: proc(g: ^Game, dt: f32) {
	p := &g.player
	g.elapsed += dt
	br := bullet_radius(g) // bullet size (grows with the big-bullets upgrade)

	// ----- movement -----
	dir: Vec2
	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {dir.y -= 1}
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {dir.y += 1}
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {dir.x -= 1}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {dir.x += 1}
	speed := p.speed
	if p.shield_timer > 0 {
		speed *= SHIELD_SPEED_MULT // the shield is heavy
	}
	if g.speed_timer > 0 {
		speed *= SPEED_BOOST_MULT
	}
	p.pos += linalg.normalize0(dir) * speed * dt
	// keep the player inside the arena
	p.pos.x = clamp(p.pos.x, p.radius, WINDOW_W - p.radius)
	p.pos.y = clamp(p.pos.y, p.radius, WINDOW_H - p.radius)

	// ----- shooting -----
	p.shoot_timer -= dt
	if rl.IsMouseButtonDown(.LEFT) {
		aim := linalg.normalize0(rl.GetMousePosition() - p.pos)
		if aim != {0, 0} {
			// face the current aim every frame while the fire button is held
			p.aim_angle = linalg.to_degrees(linalg.atan2(aim.y, aim.x))
			if p.shoot_timer <= 0 {
				append(&g.bullets, Bullet{pos = p.pos, vel = aim * BULLET_SPEED, life = BULLET_LIFE})
				p.shoot_timer = fire_cooldown(g)
                rl.PlaySound(assets.shoot_sfx)
			}
		}
	}

	// ----- clone (may add bullets, so it runs before the bullet loop) -----
	update_clone(g, dt)
	update_shield(g, dt)
	update_health_drop(g, dt)
	update_bomb(g, dt)
	update_freeze(g, dt)
	update_speed(g, dt)

	for i := len(g.bullets) - 1; i >= 0; i -= 1 {
		b := &g.bullets[i]
		b.pos += b.vel * dt
		b.life -= dt

		// ricochet: reflect the velocity component that hit the wall
		bounced := false
		if b.pos.x < br {
			b.pos.x = br
			b.vel.x = abs(b.vel.x)
			bounced = true
		} else if b.pos.x > WINDOW_W - br {
			b.pos.x = WINDOW_W - br
			b.vel.x = -abs(b.vel.x)
			bounced = true
		}
		if b.pos.y < br {
			b.pos.y = br
			b.vel.y = abs(b.vel.y)
			bounced = true
		} else if b.pos.y > WINDOW_H - br {
			b.pos.y = WINDOW_H - br
			b.vel.y = -abs(b.vel.y)
			bounced = true
		}
		if bounced {
			// clone bullets never ricochet, and neither does anything while the power-up is on:
			// they just die on the wall
			if g.ricochet_off_timer > 0 || b.from_clone {
				unordered_remove(&g.bullets, i)
				continue
			}
			b.bounces += 1
		}

		if b.life <= 0 || b.bounces > MAX_BOUNCES + g.up_bounces {
			unordered_remove(&g.bullets, i)
		}
	}

	// ----- enemies: spawn (ramps up) and chase -----
	g.spawn_timer -= dt
	if g.spawn_timer <= 0 {
		if len(g.enemies) < MAX_ENEMIES {
			spawn_enemy(g)
		}
		g.spawn_timer = max(SPAWN_MIN_INTERVAL, SPAWN_START_INTERVAL - g.elapsed * SPAWN_RAMP)
	}
	if g.elapsed >= g.next_boss_at {
		spawn_boss(g)
		g.next_boss_at += BOSS_INTERVAL
	}
	if g.freeze_timer <= 0 { // frozen enemies stay put
		for &e in g.enemies {
			e.pos += linalg.normalize0(p.pos - e.pos) * e.speed * dt
		}
	}

	// ----- bullet vs enemy -----
	for bi := len(g.bullets) - 1; bi >= 0; bi -= 1 {
		for ei := len(g.enemies) - 1; ei >= 0; ei -= 1 {
			e := &g.enemies[ei]
			if rl.CheckCollisionCircles(g.bullets[bi].pos, br, e.pos, e.radius) {
				e.health -= 1
				if e.health <= 0 {
					g.score += e.boss ? BOSS_SCORE : 1
					if e.boss {
						g.pending_upgrade = true
					}
					unordered_remove(&g.enemies, ei)
				}
				unordered_remove(&g.bullets, bi)
				break
			}
		}
	}

	// ----- power-up: enough points stops ricochet for a while -----
	g.ricochet_off_timer = max(0, g.ricochet_off_timer - dt)
	if g.score >= g.next_powerup_score {
		g.ricochet_off_timer = RICOCHET_OFF_DURATION
		// next trigger is the next multiple of RICOCHET_OFF_SCORE above the current score
		g.next_powerup_score = (g.score / RICOCHET_OFF_SCORE + 1) * RICOCHET_OFF_SCORE
	}

	// ----- health: enemy touches player -----
	p.hurt_timer -= dt
	if p.hurt_timer <= 0 && p.shield_timer <= 0 { // frozen enemies still hurt if you touch them
		for e in g.enemies {
			if rl.CheckCollisionCircles(p.pos, p.radius, e.pos, e.radius) {
				p.health -= e.boss ? BOSS_CONTACT_DAMAGE : CONTACT_DAMAGE
				p.hurt_timer = HURT_COOLDOWN
				break
			}
		}
	}

	// ----- health: bounced bullets can hit the player -----
	if p.hurt_timer <= 0 && p.shield_timer <= 0 {
		for bi := len(g.bullets) - 1; bi >= 0; bi -= 1 {
			b := g.bullets[bi]
			if b.bounces > 0 && rl.CheckCollisionCircles(p.pos, p.radius, b.pos, br) {
				p.health -= BULLET_DAMAGE
				p.hurt_timer = HURT_COOLDOWN
				unordered_remove(&g.bullets, bi)
				break
			}
		}
	}

	// ----- death: the only way a round ends -----
	if p.health <= 0 {
		g.state = .Lost
		record_score(g)
	}

	// ----- boss killed: pause for an upgrade pick -----
	if g.state == .Playing && g.pending_upgrade {
		g.pending_upgrade = false
		g.state = .Upgrade
	}
}

draw_centered :: proc(text: cstring, y: i32, size: i32, color: rl.Color) {
	rl.DrawText(text, (WINDOW_W - rl.MeasureText(text, size)) / 2, y, size, color)
}

// Side panel: saved high scores plus a live readout of the current run.
draw_scoreboard :: proc(g: ^Game) {
	x: i32 = WINDOW_W
	rl.DrawRectangle(x, 0, PANEL_W, WINDOW_H, {14, 15, 22, 255})
	rl.DrawLine(x, 0, x, WINDOW_H, rl.DARKGRAY)

	rl.DrawText("HIGH SCORES", x + 20, 20, 24, rl.GOLD)
	has_scores := false
	for e, i in g.scores {
		if e.score == 0 && e.seconds == 0 {
			continue // empty slot
		}
		has_scores = true
		// the game you just finished is highlighted
		color := i == g.last_rank ? rl.GOLD : rl.LIGHTGRAY
		rl.DrawText(fmt.ctprintf("%d. %d pts  %ds", i + 1, e.score, e.seconds), x + 20, i32(60 + i * 28), 20, color)
	}
	if !has_scores {
		rl.DrawText("No games yet", x + 20, 60, 20, rl.GRAY)
	}

	// live readout: where the current run would place right now
	if g.state != .Lost {
		y: i32 = 60 + SCOREBOARD_SIZE * 28 + 24
		rank := 1
		for e in g.scores {
			is_empty := e.score == 0 && e.seconds == 0
			if !is_empty && e.score >= i32(g.score) {
				rank += 1
			}
		}
		rl.DrawText("THIS RUN", x + 20, y, 24, rl.SKYBLUE)
		rl.DrawText(fmt.ctprintf("%d pts  %.0fs", g.score, g.elapsed), x + 20, y + 36, 20, rl.RAYWHITE)
		if rank <= SCOREBOARD_SIZE {
			rl.DrawText(fmt.ctprintf("On track for #%d", rank), x + 20, y + 64, 20, rl.GREEN)
		} else {
			rl.DrawText("Not on the board yet", x + 20, y + 64, 20, rl.GRAY)
		}

		// power-up counter: time left while active, otherwise progress to the next one
		py := y + 110
		if g.ricochet_off_timer > 0 {
			rl.DrawText("NO RICOCHET", x + 20, py, 24, rl.ORANGE)
			rl.DrawText(fmt.ctprintf("%.1fs left", g.ricochet_off_timer), x + 20, py + 32, 20, rl.RAYWHITE)
			bar_w := f32(PANEL_W - 40)
			rl.DrawRectangle(x + 20, py + 60, i32(bar_w), 8, rl.DARKGRAY)
			rl.DrawRectangle(x + 20, py + 60, i32(bar_w * g.ricochet_off_timer / RICOCHET_OFF_DURATION), 8, rl.ORANGE)
		} else {
			rl.DrawText("POWER-UP", x + 20, py, 24, rl.GRAY)
			rl.DrawText(fmt.ctprintf("Next at %d pts", g.next_powerup_score), x + 20, py + 32, 20, rl.LIGHTGRAY)
			rl.DrawText(fmt.ctprintf("%d to go", g.next_powerup_score - g.score), x + 20, py + 56, 20, rl.GRAY)
		}
	}
}

draw :: proc(g: ^Game) {
	rl.ClearBackground({20, 22, 30, 255})

    rl.DrawTexturePro(
        assets.background,
        {0, 0, f32(assets.background.width), f32(assets.background.height)},
        {0, 0, WINDOW_W, WINDOW_H},
        {0, 0},
        0,
        rl.WHITE,
    )

	rl.DrawRectangleLines(0, 0, WINDOW_W, WINDOW_H, rl.DARKGRAY)

	// shield pickup: green ring, flickers when about to vanish
	if g.shield_drop.active {
		d := g.shield_drop
		flicker := d.life < 2 && int(g.elapsed * 10) % 2 == 0
		if !flicker {
			rl.DrawCircleV(d.pos, SHIELD_DROP_RADIUS, rl.Fade(rl.GREEN, 0.35))
			rl.DrawCircleLines(i32(d.pos.x), i32(d.pos.y), SHIELD_DROP_RADIUS, rl.GREEN)
			rl.DrawCircleLines(i32(d.pos.x), i32(d.pos.y), SHIELD_DROP_RADIUS - 4, rl.GREEN)
		}
	}

	// health pickup: pink circle with a white cross, flickers when about to vanish
	if g.health_drop.active {
		d := g.health_drop
		flicker := d.life < 2 && int(g.elapsed * 10) % 2 == 0
		if !flicker {
			x, y := i32(d.pos.x), i32(d.pos.y)
			rl.DrawCircleV(d.pos, HEALTH_DROP_RADIUS, rl.Fade(rl.PINK, 0.35))
			rl.DrawCircleLines(x, y, HEALTH_DROP_RADIUS, rl.PINK)
			rl.DrawRectangle(x - 6, y - 2, 12, 4, rl.WHITE) // horizontal bar
			rl.DrawRectangle(x - 2, y - 6, 4, 12, rl.WHITE) // vertical bar
		}
	}

	// bomb pickup: dark ball with a lit fuse, flickers when about to vanish
	if g.bomb_drop.active {
		d := g.bomb_drop
		flicker := d.life < 2 && int(g.elapsed * 10) % 2 == 0
		if !flicker {
			x, y := i32(d.pos.x), i32(d.pos.y)
			rl.DrawCircleV(d.pos, BOMB_DROP_RADIUS, rl.Fade(rl.ORANGE, 0.25))
			rl.DrawCircleV(d.pos, BOMB_DROP_RADIUS - 3, rl.BLACK)
			rl.DrawCircleLines(x, y, BOMB_DROP_RADIUS, rl.ORANGE)
			rl.DrawLine(x + 5, y - 9, x + 10, y - 15, rl.LIGHTGRAY) // fuse
			rl.DrawCircle(x + 10, y - 15, 3, int(g.elapsed * 8) % 2 == 0 ? rl.YELLOW : rl.ORANGE) // spark
		}
	}

	// speed pickup: green circle with double chevrons, flickers when about to vanish
	if g.speed_drop.active {
		d := g.speed_drop
		flicker := d.life < 2 && int(g.elapsed * 10) % 2 == 0
		if !flicker {
			x, y := i32(d.pos.x), i32(d.pos.y)
			rl.DrawCircleV(d.pos, SPEED_DROP_RADIUS, rl.Fade(rl.LIME, 0.3))
			rl.DrawCircleLines(x, y, SPEED_DROP_RADIUS, rl.LIME)
			rl.DrawLine(x - 7, y - 6, x - 1, y, rl.WHITE)
			rl.DrawLine(x - 1, y, x - 7, y + 6, rl.WHITE)
			rl.DrawLine(x, y - 6, x + 6, y, rl.WHITE)
			rl.DrawLine(x + 6, y, x, y + 6, rl.WHITE)
		}
	}

	// planted bomb: red danger zone (stay out!), faint blast radius, countdown
	if g.bomb_planted {
		bx, by := i32(g.bomb_pos.x), i32(g.bomb_pos.y)
		rl.DrawCircleV(g.bomb_pos, BOMB_RADIUS, rl.Fade(rl.ORANGE, 0.05))
		rl.DrawCircleLines(bx, by, BOMB_RADIUS, rl.Fade(rl.ORANGE, 0.6))
		rl.DrawCircleV(g.bomb_pos, BOMB_SELF_RADIUS, rl.Fade(rl.RED, 0.15))
		rl.DrawCircleLines(bx, by, BOMB_SELF_RADIUS, rl.RED)
		rl.DrawCircleV(g.bomb_pos, 10, int(g.elapsed * 10) % 2 == 0 ? rl.ORANGE : rl.BLACK)
		rl.DrawText(fmt.ctprintf("%.1f", g.bomb_fuse), bx - 14, by - 40, 22, rl.WHITE)
	}

	// freeze pickup: icy circle with a snowflake, flickers when about to vanish
	if g.freeze_drop.active {
		d := g.freeze_drop
		flicker := d.life < 2 && int(g.elapsed * 10) % 2 == 0
		if !flicker {
			x, y := i32(d.pos.x), i32(d.pos.y)
			ice := rl.Color{150, 220, 255, 255}
			rl.DrawCircleV(d.pos, FREEZE_DROP_RADIUS, rl.Fade(ice, 0.3))
			rl.DrawCircleLines(x, y, FREEZE_DROP_RADIUS, ice)
			rl.DrawLine(x - 8, y, x + 8, y, rl.WHITE)
			rl.DrawLine(x, y - 8, x, y + 8, rl.WHITE)
			rl.DrawLine(x - 6, y - 6, x + 6, y + 6, rl.WHITE)
			rl.DrawLine(x - 6, y + 6, x + 6, y - 6, rl.WHITE)
		}
	}

	// enemies (sprites): frozen ones get an icy tint
	frozen := g.freeze_timer > 0
	ice := rl.Color{150, 220, 255, 255}
	for e in g.enemies {
		if e.boss {
			draw_sprite(assets.boss, e.pos, e.radius, 0, frozen ? rl.SKYBLUE : rl.WHITE)
			// health bar above the boss
			bar_w := e.radius * 2
			bar_x := e.pos.x - e.radius
			bar_y := e.pos.y - e.radius - 12
			rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_w), 6, rl.DARKGRAY)
			rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_w * f32(e.health) / f32(e.max_health)), 6, rl.ORANGE)
		} else {
			draw_sprite(assets.enemy, e.pos, e.radius, 0, frozen ? ice : rl.WHITE)
		}
	}

	// clone: translucent sky-blue copy of the player
	if g.clone.active {
		draw_sprite(assets.player, g.clone.pos, g.player.radius, g.clone.aim_angle + SHIP_ART_ANGLE, rl.Fade(rl.SKYBLUE, 0.5))
	}

	for b in g.bullets {
		// white = yours, sky blue = clone's, magenta = bounced (can hurt you)
		color := rl.WHITE
		if b.bounces > 0 {
			color = rl.MAGENTA
		} else if b.from_clone {
			color = rl.SKYBLUE
		}
		draw_sprite(assets.bullet, b.pos, bullet_radius(g), 0, color)
	}

	// player blinks while invincible
	p := g.player
	blink := p.hurt_timer > 0 && int(g.elapsed * 20) % 2 == 0
	if !blink {
		draw_sprite(assets.player, p.pos, p.radius, p.aim_angle + SHIP_ART_ANGLE)
	}

	// shield bubble around the player, flickers in its last 1.5 s
	if p.shield_timer > 0 && !(p.shield_timer < 1.5 && int(g.elapsed * 10) % 2 == 0) {
		rl.DrawCircleV(p.pos, p.radius + 8, rl.Fade(rl.GREEN, 0.25))
		rl.DrawCircleLines(i32(p.pos.x), i32(p.pos.y), p.radius + 8, rl.GREEN)
	}

	// bomb blast: white screen flash plus an expanding ring
	if g.bomb_flash > 0 {
		t := g.bomb_flash / BOMB_FLASH_TIME // 1 -> 0 over the animation
		rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, rl.Fade(rl.WHITE, 0.3 * t))
		ring := (1 - t) * BOMB_RADIUS
		ox, oy := i32(g.bomb_origin.x), i32(g.bomb_origin.y)
		rl.DrawCircleLines(ox, oy, ring, rl.ORANGE)
		rl.DrawCircleLines(ox, oy, ring - 3, rl.YELLOW)
		rl.DrawCircleLines(ox, oy, ring - 6, rl.ORANGE)
	}

	// HUD
	if g.freeze_timer > 0 {
		rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, rl.Fade(rl.SKYBLUE, 0.06)) // faint icy tint
		rl.DrawText(fmt.ctprintf("FROZEN (guns slowed): %.1fs", g.freeze_timer), 12, 100, 22, ice)
	}
	if g.speed_timer > 0 {
		rl.DrawText(fmt.ctprintf("SPEED BOOST (guns slowed): %.1fs", g.speed_timer), 12, 128, 22, rl.LIME)
	}
	if g.has_bomb {
		color := int(g.elapsed * 4) % 2 == 0 ? rl.ORANGE : rl.YELLOW
		rl.DrawText("BOMB READY - SPACE / RIGHT CLICK TO PLANT", 12, 72, 20, color)
	}
	if p.shield_timer > 0 {
		rl.DrawText(fmt.ctprintf("Shield: %.1fs", p.shield_timer), WINDOW_W - 200, 68, 22, rl.GREEN)
	}
	for i in 0 ..< p.max_health {
		color := i < p.health ? rl.RED : rl.DARKGRAY
		rl.DrawRectangle(i32(12 + i * 26), 12, 22, 22, color)
	}
	rl.DrawText(fmt.ctprintf("Score: %d", g.score), 12, 44, 22, rl.RAYWHITE)
	rl.DrawText(fmt.ctprintf("Time: %.0fs", g.elapsed), WINDOW_W - 170, 12, 22, rl.RAYWHITE)
	if g.clone.active {
		rl.DrawText(fmt.ctprintf("Clone: %.0fs left", g.clone.life), WINDOW_W - 200, 40, 22, rl.SKYBLUE)
	} else {
		rl.DrawText(fmt.ctprintf("Clone in: %.0fs", max(0, g.next_clone_at - g.elapsed)), WINDOW_W - 200, 40, 22, rl.GRAY)
	}

	// boss warning: shown for the last BOSS_WARNING seconds before it drops
	boss_in := g.next_boss_at - g.elapsed
	if g.state == .Playing && boss_in <= BOSS_WARNING {
		flash := int(g.elapsed * 4) % 2 == 0
		draw_centered(fmt.ctprintf("WARNING: BOSS IN %.0f", boss_in), 90, 30, flash ? rl.ORANGE : rl.RED)
	}

	// ricochet-off popup: flashes in the middle while the power-up is active
	if g.state == .Playing && g.ricochet_off_timer > 0 {
		flash := int(g.elapsed * 4) % 2 == 0
		draw_centered(
			fmt.ctprintf("RICOCHET OFF ENDS IN: %.0fs", g.ricochet_off_timer),
			130,
			30,
			flash ? rl.ORANGE : rl.YELLOW,
		)
	}

	draw_scoreboard(g)

	// upgrade menu (the game is paused behind it)
	if g.state == .Upgrade {
		rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, rl.Fade(rl.BLACK, 0.7))
		draw_centered("BOSS DOWN!", 140, 48, rl.GOLD)
		draw_centered("Pick one upgrade (press 1-6 or click)", 205, 24, rl.RAYWHITE)
		mouse := rl.GetMousePosition()
		for i in 0 ..< UPGRADE_COUNT {
			r := upgrade_rect(i)
			hover := rl.CheckCollisionPointRec(mouse, r)
			fill := rl.Color{30, 33, 48, 255}
			border := rl.GRAY
			if hover {
				fill = {50, 55, 80, 255}
				border = rl.GOLD
			}
			rl.DrawRectangleRec(r, fill)
			rl.DrawRectangleLinesEx(r, 2, border)
			tx, ty := i32(r.x) + 10, i32(r.y) + 14
			rl.DrawText(fmt.ctprintf("%d. %s", i + 1, UPGRADE_NAMES[i]), tx, ty, 18, rl.GOLD)
			rl.DrawText(UPGRADE_DESCS[i], tx, ty + 40, 16, rl.LIGHTGRAY)
			rl.DrawText(fmt.ctprintf("Level %d", upgrade_level(g, i)), tx, ty + 125, 16, rl.SKYBLUE)
		}
	}

	// end screens
	if g.state == .Lost {
		rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, rl.Fade(rl.BLACK, 0.6))
		draw_centered("YOU DIED", 220, 56, rl.RED)
		draw_centered(fmt.ctprintf("Score: %d   Time: %.0fs", g.score, g.elapsed), 295, 28, rl.RAYWHITE)
		if g.last_rank >= 0 {
			draw_centered(fmt.ctprintf("New #%d on the scoreboard!", g.last_rank + 1), 340, 26, rl.GOLD)
		}
		draw_centered("Press R to play again", 390, 24, rl.LIGHTGRAY)
	}
}

main :: proc() {
	rl.InitWindow(WINDOW_W + PANEL_W, WINDOW_H, "ARENA")
	defer rl.CloseWindow()
    rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	load_assets()
	defer unload_assets()

	game: Game
	defer delete(game.bullets)
	defer delete(game.enemies)
	reset_game(&game)
	load_scores(&game)

	for !rl.WindowShouldClose() {
		switch game.state {
		case .Playing:
			update(&game, rl.GetFrameTime())
		case .Upgrade:
			update_upgrade(&game)
		case .Lost:
			if rl.IsKeyPressed(.R) {
				reset_game(&game)
			}
		}

		rl.BeginDrawing()
		draw(&game)
		rl.EndDrawing()

		free_all(context.temp_allocator) // clears fmt.ctprintf strings
	}
}
