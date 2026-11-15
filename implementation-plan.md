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

## M2 — Peasants, builders & tax rounds (done, Majesty-style economy)

Villagers become visible agents, and money/buildings get their real mechanics.

- Houses spawn peasants; peasants walk to a farm, work, and carry food back
  to the keep. Food/pop growth comes from delivered labor, replacing flat rates.
- Construction flow: tapping a tile creates a **construction site flag**;
  peasants walk out to it and raise the building.
  Prototype simplification (explicit): buildings *warp in* on placement at
  first; the walk-out-and-build behavior is layered in behind the same
  interface, so the player-visible flow doesn't change.
- Tax rounds: houses accrue tax over time; a **tax collector** (employed by
  the keep) walks a round house-to-house, collects gold, and deposits it at
  the keep. Uncollected tax caps (or decays) — soft pressure to keep peasants
  safe and roads of the realm short. Replaces the abstract `gold += pop`.
- Peasants flee raiders (behavior stub reused in M3).
- Tests: construction completion accounting, tax collected vs. houses on the
  round, delivery sums over N ticks, no stuck agents in long-run sims
  (deadlock check).
- Design pivot (playtest feedback): player-facing food subsistence removed —
  gold is the limiter, matching Majesty and `design-concept.md`. Farms now
  define provisions capacity (4 people each); growth needs delivered rations
  plus headroom, shortage sheds people slowly (soft, floor of 1). Creature
  ecology (M6) and hero hunger (M4) keep their own separate food systems.

Done when: you can watch a peasant finish a house, then watch the collector
do a round and see the keep's gold tick up from what he carried.

## M2.5 — Tap-to-inspect (info panel, pulled forward from M8 polish)

Player feedback: no way to see what a building is worth or does, or what a
unit is up to.

- In explore mode (no build mode active), tapping a building or unit opens an
  inspector; build mode and map dragging behave exactly as before.
- Responsive layout: on narrow/phone screens a slim card pinned to the bottom
  edge that never covers more than ~1/3 of the map (dismiss by tapping empty
  ground or an X); on wide screens it docks as a side panel, RTS-style. Same
  data, two layouts.
- Buildings: name, flavor description, what it produces/attracts/risks
  (from content-design rows), and vague live state — e.g. a house's tax purse
  as wording or a subtle meter ("a modest purse"), never raw formulas.
- Units: role and current activity in flavor ("hauling grain home", "resting
  at the keep", "on the collector's round"); personality, items, equipment
  slots appear as they are introduced (M4 heroes).
- Ecology entries (M6 creatures/dens): what they eat, produce, or attract —
  hints at mechanics, not numbers.
- Descriptions live as data rows in `content-design.md` (a `blurb` column or
  parallel table), not new code paths; exact values stay in the sim.
- Tests: building/unit → description mapping, tap-vs-drag routing keeps build
  mode intact, panel content updates per tick.

Done when: tapping a house tells you it's "holding a modest purse", tapping a
peasant says what he's carrying and where he's headed, and the map stays
usable underneath on a phone.

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
- Occasional hero assist on construction sites or escorting tax rounds
  (flavor-weighted from personality tables, never required).
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
