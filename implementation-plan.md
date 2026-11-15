# Implementation Plan: Incremental Milestones

Ground rules for every milestone:

- Sim logic stays in pure scripts (`scripts/`), runnable and testable headless.
- The view layer only reads sim state and forwards input; no logic in scenes.
- Content variety comes from data rows (see `content-design.md`), not new code paths.
- Each milestone ends with: headless tests green, `--quit-after` scene sanity check,
  web re-export, and a manual playtest at `https://<pi-ip>:8443`.

## M0 — Economy skeleton (done)

Tick sim (gold/food/pop), farm/house buttons, web export + HTTPS LAN hosting,
sim test, git repo, content design doc.

## M1 — World & terrain (done)

Tile-based world with terrain types and on-map building placement.

- Deterministic seeded world generation (grass/forest/water/mountain, wild
  mountain borders, cleared keep site).
- Buildings occupy tiles; placement rules (grass only, not occupied).
- Map view with placeholder tile colors; tap-to-place build mode from the
  build bar; keep pre-placed at center.
- Tests: `tests/world_test.gd` (determinism, buildability), updated
  `tests/sim_test.gd` (tile-aware economy).

Done when: farms/houses can be placed on specific map tiles and the economy
still runs; all headless tests pass.

## M1.5 — Readability & navigation (done, pulled forward from M5)

Player feedback: color-only tiles on a fixed small map read like a minimap.

- Map grew to 48x32 (larger than the viewport).
- One-finger drag / mouse-drag pans; two-finger pinch zooms (0.6x-2.5x), edge
  clamped so the map can't be lost off-screen; tap (no drag) still places.
- Placeholder tile "pictures": trees, water waves, mountain peaks with snow
  caps, grass tufts; buildings got simple glyphs (crop rows, pitched roofs,
  flagged castle).
- Touch handled natively (ScreenTouch/ScreenDrag); emulated mouse events are
  filtered out by device ID so nothing double-processes.

## M2 — Peasant agents

Villagers become visible agents instead of abstract numbers.

- Houses spawn peasants; peasants walk to a farm, work, return food to keep.
- Food/tax production comes from peasant labor (replaces per-farm flat rates).
- Peasants flee raiders (behavior stub used again in M3).
- Tests: agent counts vs. houses, food delivered over N ticks, no stuck agents
  after long simulation (deadlock check).

Done when: you can watch peasants walking between buildings and starving
becomes visible (agents disappear) rather than a number ticking down.

## M3 — Goblins & guards (faction 1)

First hostile faction, from the wild borders.

- Goblin dens spawn on mountain edges; dens grow with successful raids.
- Raid incentive: den picks nearest farm/market, sends warband.
- Guards spawn from guardhouse (new building), patrol radius, intercept raids.
- Combat resolution is simple attrition; losers flee; dens can be cleared.
- Soft fail states: raids destroy buildings (repairable), never game over.
- Tests: raid cooldowns, den growth/clearing, guard interception, 10-game-year
  sim without deadlock or total extinction.

Done when: goblins visibly raid, guards respond, and losing a farm is
recoverable.

## M4 — Heroes & attraction (indirect control core)

- Tavern/guardhouse/shrine attract hero classes with personality weights.
- Heroes score incentives (bounty flags, treasure, smite-evil), pick goals,
  act, spend loot at market, rest at tavern.
- Player posts bounties (one-tap flags); heroes decide autonomously.
- Heroes fight goblins; level up (simple stat growth); can die (drop loot).
- Tests: incentive scoring table snapshot, hero loop (fight/rest/shop),
  attraction counts vs. building mix.

Done when: the core loop of the brief works — build tavern → rogue appears →
rogue chases treasure → player nudges with flags, never commands.

## M5 — Exploration & fog of war

- Map grows beyond viewport; pan and pinch-zoom were pulled forward into
  M1.5; remaining here: minimap.
- Soft-edged fog; heroes reveal terrain as they explore; landmarks (ruins,
  dens, shrines) appear as fog lifts; unexplored areas simulated cheaply.
- Tests: fog reveal accounting, minimap sync, perf budget at full map reveal
  on Pi (frame budget check via headless timing).

## M6 — Ecology & factions 2-3

- Dens get `needs` (terrain/food); unmet needs → migration or starvation.
- Food chains from `content-design.md` (frogs→owlbears, rabbits→wolves…).
- Kobold–gnome feud events; bandits ambush caravans; hags curse farms.
- Terrain actions (drain swamp, clear forest) with ripple consequences;
  druid reaction.
- Tests: chain reactions (drain swamp → frog collapse → owlbear claim shift),
  tension matrix drift, den migration.

## M7 — Content & diplomacy pass

- Remaining buildings from `content-design.md`: market, shrine, blacksmith,
  wizard tower, ranger hut, mead hall, herbalist grove, graveyard (risky),
  sewers.
- Hero shopping (gear points), tribute diplomacy with bandits/hags,
  necromancer risk/reward.
- Tests: per-building attraction + production, tribute stance shifts,
  graveyard undead events.

## M8 — Session layer & polish

- Save/load (pause + place buildings; autosave; no away-simulation).
- Chronicle log (readable on demand).
- Season/events cycle; difficulty tuning to the 10-15 minute session target;
  soft-fail audit.

## Later (out of scope for now)

- Real art pass (palette-locked 32x32), paper-doll hero sprites.
- Native mobile ports, iOS signing via a Mac.
