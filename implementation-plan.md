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

## M3 — Goblins & guards (faction 1, done)

First hostile faction, from the wild borders.

- Goblin dens spawn on mountain edges (reachable doorsteps only); dens grow
  with successful raids (3 levels).
- Raid incentive: hungry dens pick nearest farm/house, send warbands. The den
  runs a weighted mood machine (lurk/prowl/forage/raid/muster/rest); goblins
  run their own weighted behavior layer under it (lurk/wander/prowl/forage).
- Guards spawn from guardhouses, patrol radius, intercept raids; the watch is
  leashed to the keep and never storms dens — that is hero work (M4).
- Combat resolution is simple attrition; losers flee; dens can be cleared by
  siege (guards adjacent chip den hp). Cleared dens spill their gold as a
  loot pile and leave a long respawn rest.
- Soft fail states: raids destroy buildings (razed tiles are rebuildable),
  never game over.
- Tests: `tests/raids_test.gd` (den placement, raid pacing, moods, razes and
  recovery, den growth, guard intercept, leash, retraining, den respawn,
  10-game-year sim without deadlock or extinction).

Done when: goblins visibly raid, guards respond, and losing a farm is
recoverable. ✓

## M3.5 — Rename & sim speed (done)

Two small player-facing tweaks pulled out of band:

- The game is now **Realm Builder** (window/project name, scene title,
  README); "Majesty" lives on only as the inspiration in the docs.
- A **Dev** button (top-right) opens a small speed panel: 1x / 1.5x / 2x /
  3x. Speed only re-times the tick timer (1/speed seconds per tick), so the
  sim itself stays identical at every speed. Purely a dev/comfort tool.

## M4 — Heroes & attraction (indirect control core, done)

- Three hero classes as content rows (`HERO_CLASSES` in `kingdom.gd`):
  rogue (tavern), warrior (guardhouse), paladin (shrine), each with a
  personality weight table (bounty / treasure / smite_evil / assist).
  Attraction: a periodic roll whose weights come straight from the completed
  building mix; heroes wander in from a connected map edge to the hall that
  drew them, up to a cap.
- Heroes score the world (`hero_goal_scores`, pure and table-driven) and
  always act on their own: rest at the tavern when weary (heals), spend
  loot at the market (realm profits), chase bounty flags, smite dens,
  race to loot piles, occasionally lend a hand at construction sites
  (lowest weight — never required), otherwise patrol the realm.
- Player posts bounties via the den inspector (one-tap flag, 20g posting
  of which 18g lands on the flag and 2g is the office's cut; stackable).
  Heroes decide autonomously whether it beats their other options.
- Heroes fight in the attrition step with melee weight = level, level up
  on kills and den clears (+2 max hp), and can die — dropping their purse
  as a loot pile that treasure-loving heroes (rogues) race to. Fleeing
  heroes break off at 1 hp and heal at the tavern.
- Dens cleared by heroes credit xp, pay standing bounties, and leave a
  loot pile.
- Escorting tax rounds: deferred (M7 content pass) — construction assist
  covers the "occasional hero helpfulness" slot for now.
- Tests: `tests/heroes_test.gd` (attraction mix vs. building mix, arrival,
  full incentive snapshot per class, shop+rest loop, combat + level-ups,
  bounty flow, death → loot drop → pickup, 10-game-year run).

Done when: build a tavern → a rogue arrives → rogues chase treasure and
bounties → the player nudges with flags, never commands. ✓

## M5 — Exploration & fog of war (built, awaiting playtest)

- Map grows beyond viewport; pan and pinch-zoom were pulled forward into
  M1.5; remaining here: minimap.
- **Minimap** (bottom-right): the whole map in miniature showing only
  charted ground — terrain, keep (gold), dens (red), heroes (white) — plus
  a viewport outline; tap it to jump the main view there.
- Fog (single permanent layer): the map starts dark and charted ground
  stays lit for good. The keep charts its surroundings at start; heroes
  reveal with a wide radius as they roam, workers with a small one;
  goblins reveal nothing. The view softens tile edges by neighbor
  sampling. Dens, loot piles and uncharted goblins stay hidden until the
  fog lifts. The wilds are simulated exactly as before — fog is a view
  gate plus one rule: you cannot build on unexplored land.
- Heroes are not omniscient: dens and loot piles in uncharted land are
  not options in their incentive scoring until the realm has charted
  them (bounties are charted by construction — the player posts them on
  dens they can see). With no venture on the books and wilds left, a
  hero heads for the walk-nearest frontier about half the time
  (coin-flip against patrolling, tie broken toward exploring), lighting
  the map as it goes.
- **Dev toggle**: the Dev panel (top-right) now has a "Fog of war" switch
  that reveals/hides the whole map for troubleshooting; turning it back on
  re-charts from the realm's actual footing.
- Tests: `tests/fog_test.gd` (starting reveal, stamp accounting,
  landmark/den discovery events, hero + worker reveal, build gating,
  toggle round-trip, minimap data sync, headless perf budget — currently
  ~5.8 ms/tick with the full sim running). Existing suites run with fog
  disabled so their exact accounting is unaffected.

Done when: the map starts mostly hidden, a roaming hero visibly lights up
the wilds, a den surfaces on the minimap as fog lifts, and the Dev fog
switch makes the whole map plain when troubleshooting.

## M5.5 — Keep gold trickle (player feedback)

Failure mode: build only non-income buildings (shrine, guardhouse…) until
gold hits 0 and the realm is hard-stuck — no income without a farm, no farm
without gold.

- The keep's household now scrapes together a slow trickle: **5g per
  minute** of normal time (`keep_trickle` / `keep_trickle_ticks` vars in
  `kingdom.gd`), regardless of the building mix. Slow enough that farms
  and taxes stay the real economy; fast enough to dig out of a mistake.
- Tests: exact 5g/60-tick pacing in `tests/sim_test.gd`, plus a broke-realm
  recovery scenario. Exact-accounting suites run with the trickle zeroed
  (same pattern as fog).

Done when: a realm at 0 gold can rebuild a farm after a couple of minutes
without player income.

## M5.6 — Hero halls, building taxes & pathfinding fix (player feedback)

- Heroes no longer stroll in from the map edge: they spawn at a random
  complete hall of their attracting kind (rogue → tavern, warrior →
  guardhouse, paladin → shrine) and adopt it as home.
- Building taxes: farms (1g, cap 6), houses (1g, cap 15, unchanged),
  taverns (2g, cap 20), markets (3g, cap 30) all owe the collector;
  shrines and guardhouses are crown service and earn nothing. The
  collector's round now stops at any tax-bearing building; the inspector
  mentions the till/tithe on taxed buildings.
- Perf fix (uncovered while profiling): `find_path` flooded the whole
  walkable map on every call, so a healthy realm (constant farm-worker
  cycling) cost ~25 ms/tick on the Pi. BFS now exits the moment the
  target is reached (same shortest paths): ~0.15 ms/tick for the same
  economy, ~170x. The old fog-perf numbers had been measuring a
  raid-collapsed economy, which is why this hid until now.
- Tests: existing suites cover both behavior changes (hero arrival at the
  hall that drew them, tax/deposit invariants over any building mix);
  fog perf budget now passes with a healthy economy (0.7 ms/tick).

## M5.7 — Hero resilience (player feedback)

Rogues were dying near-instantly when a warband mobbed them.

- Base hp scaled up: rogue 6 → 10, warrior 10 → 14, paladin 12 → 18.
- Heroes swing harder than rank alone: melee weight is level + 1, so a
  fresh hero can carve through a small warband. Den siege damage stays
  level-based, so den-clear pacing is unchanged.
- Heroes break off before dying: they flee at a third of max hp
  (rank-and-file still break at the last breath), limp to the tavern,
  heal, and come back.
- Result: all three classes clear a 3-goblin mob — warrior and paladin
  stand their ground (8/14 and 12/18 hp left), the rogue wipes it and
  retreats at 4/10 to recover.

Done when: a fresh hero survives the kind of ambush that used to delete
rogues, and hero deaths feel like drama, not like losing a villager.

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
