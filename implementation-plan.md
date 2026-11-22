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
- Heroes pick fights, not just take them: a visible enemy within 6 tiles
  (or 12 when it is a raider or standing at a building's door) pulls them
  off patrols, leisure and errands into a chase. Overriding needs win
  instead: fleeing, exhaustion, low health, or being indoors (tavern
  rest, market shopping) keep a hero from answering; a siege in progress
  stays committed. Fog still gates what they can see.
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

## M5.8 — Hero arrival pacing (player feedback)

Heroes took minutes to show: a 120-tick attraction cycle at 60% whose
countdown ran from world attach, so a hall built late could wait out a
stale cycle on top of the wait.

- Attraction rolls now come every ~45s (75% chance).
- Finishing any hero hall pulls the next roll forward to ~10 ticks —
  the first hero steps out within seconds of the door opening; later
  arrivals keep the steady 45s cadence.
- Perf fix (surfaced by the faster arrivals): heroes charting the whole
  map made every idle decision flood it hunting for a frontier that no
  longer existed, ~10.8 ms/tick. Exploration now probes the live set of
  uncharted open tiles with the early-exit pathfinder, and sealed pockets
  (unreachable uncharted land) are memoized once: ~1.0 ms/tick.
- Test: first arrival within 12 ticks of the tavern's finish.

## M6 — Ecology & factions 2-3

Ground shape: the den system becomes a real ecology before new factions
stack on top of it. Split into staged chunks, each testable headless.

## M6.1 — Ecology core: dens, creatures, food chains (built, awaiting playtest)

- Dens are content rows (`DEN_KINDS` in `kingdom.gd`: faction, site
  terrain, unit, diet); goblins become one row among many, and every den
  dict carries a `kind`.
- Wild dens behind a `wild_ecology` toggle (exact-accounting suites run
  with it off, same pattern as fog): rabbit warrens graze the meadows and
  regrow their larder; wolf packs hunt warrens for food; giant spiders
  raid goblin dens' stores — the first two chains from
  `content-design.md` (rabbits → wolves, goblins → spiders).
- Every wild den has `needs` (its food): a larder empty for
  `den_migrate_ticks` migrates the den toward better grounds — predators
  follow prey, and wolves with no warrens left fall back to raiding
  farm stores; with nowhere to go, the den starves out (dissolves, no
  loot, its creatures die off). Goblin dens raid instead of migrating —
  hunger is their pressure valve.
- Wild regrowth now seeds from a weighted table (goblins still dominant):
  warrens on grass, wolf/spider dens in deep forest, always far from the
  keep and clear of buildings; wild dens cap separately from goblin ones.
- Wild creatures are agents with per-species behavior rolls (graze /
  lurk / wander / hunt). They never fight the realm in this chunk —
  wilder territoriality lands later.
- Realm gating: heroes smite only *hostile* dens by nature, but a posted
  bounty can flag **any lair** outside the realm's own walls (goblin den,
  rabbit warren, bandit camp...) — the flag makes it a siege target for
  the realm's armed folk. You cannot build on a wild den tile; fog
  discovery events, inspector text, map view and minimap are kind-aware.
- Hero leisure (tuned after playtesting): hunting (rogues love it,
  fresh legs only — it yields to bounties and peters out before the
  warren runs dry), prayer at the shrine (weary paladins), and tavern
  evenings that drop a coin in the till.
- Decisions are a weighted draw, not a locked ranking: overriding
  priorities are safety (an exhausted hero always turns in) and
  self-defense (nearby foes pull heroes into a chase outside goal
  choice; adjacent fighting is reflexive);
  everything else squares its incentive score into a weight and rolls,
  so favored pursuits usually win but anything on the table keeps a
  chance. Pull scales with the stakes: a bounty's reward does the
  tugging (an 18g flag tempts a rogue ~65% of draws, a 5000g one takes
  everyone), and a carousing hero leans on the tavern in proportion to
  the purse (a broke rogue drinks ~30% of draws, a 30g one ~80% — the
  market still outranks it while the purse is worth banking). A round
  of hunt or carouse halves its own score for ~60 ticks (quarter
  weight) — rotation comes from the odds, not gates. Rogues were still
  a touch hunt-happy, so their hunt weight is 4 (hunt ~53% of idle
  draws beside a tavern and a warren, down from ~60%). Leisure is not
  snapped off in a tick: tavern evenings run 8 ticks, prayer 6, a spot
  of hunting 4; errands (shop, loot, assist) stay quick.
  `_best_hero_goal` remains the deterministic "favored pursuit" query
  for tests/UI.
- Tests: `tests/ecology_test.gd` (seeded lairs, prey regrowth, hunt
  chain accounting, spider-vs-goblin chain, migration vs starvation,
  farm fallback, gating, long-run sim + tick budget).
- Deferred to the next chunks: faction tension matrix (lands with the
  factions that act on it).

## M6.2 — Factions 2-3: kobolds, gnomes, bandits, hags (built, awaiting playtest)

- Four new `DEN_KINDS` rows: `kobold_den` (kobolds, neutral, hill thief
  role), `gnome_enclave` (gnomes, neutral, hill trader), `bandit_camp`
  (hostile, road raider — musters bandit agents), `hag_coven` (hostile,
  forest curser — no agents, curses instead). Titles, blurbs, status
  lines, map art, minimap hostility and inspector rows are kind-aware;
  wild dens now include the hills (`mountain_edge` sites), and
  `_den_respawn_tick` counts only goblin dens so the other factions do
  not crowd the goblin cap.
- Faction tension ledger `tension` (`"a|b"` sorted keys, content rows
  normalized at init): the `content-design.md` §4.3 matrix seeds it at
  -3..+3, events shift it clamped, and it drifts one step toward 0 every
  `tension_decay_ticks` (500). Territory is the root quarrel: dens of
  different factions whose claims (radius 6) overlap sour their ledger
  every `claim_friction_ticks` (120) — beasts don't do politics.
- The kobold–gnome feud is the designed pressure point: the seed squats
  the closest pair of hill shoulders so claims overlap from day one.
  The quarrel needs that shared ground: friction sours the ledger while
  claims overlap, kobolds only rob an enclave their claim reaches, and
  warbands march only across contested hills. Clearing either side (or
  territory separation) thaws the ledger to 0 at once — trade reopens
  and strikes stop — and respawned burrows keep clear of a rival's
  claim, so the lock cannot silently reassert itself. Kobolds still
  steal from the nearest farm every 150 ticks (or the enclave, when in
  reach); gnome tinkers trickle a coin into the realm every 200 ticks
  *unless* the feud is at a boil (≤ -2). At ≤ -2 warbands strike the
  enclave for coin, else its larder (and stay home when there is
  nothing worth taking).
- Bandits: a camp musters a rider every 300 ticks up to 2 + level,
  seeded near the frontier so the roads bite early; idle bandits hunt
  for laden purses within reach (collectors first, heroes as fallback),
  shadow the mark, lift at most `bandit_take` (10), flee home with it,
  heal at camp, and bank the take in the camp strongbox. Bandits join
  combat both ways: guards and heroes cut them down, they beat on
  guards/heroes, and a killed bandit spills his takings on the road.
- Hags: covens curse the nearest complete farm within 20 tiles every
  300 ticks (`cursed_until`, 300-tick duration). A cursed farm accepts
  no new farmers, delivers no harvest (`FARM_CARRY` becomes 0), and
  says so in the inspector; the curse wears off on its own.
- Seeding/balance: the starting wilds hold the warren/wolf pair, the
  feuding hillfolk, a road bandit camp and a hag coven near the settled
  woods; `wild_dens_max` rises to 8 so spawns still happen. Predator
  larders now drain (`predator_upkeep_ticks` 200) so wolves regularly
  get hungry and hunt — M6.1's wolf/warren chain actually runs.
- UI: a bottom-left **Log** toggle opens a compact event-log card (not a
  full-screen takeover) with the whole scrollback, tick-stamped and
  auto-scrolling; it rebuilds from `sim.event_log` on open and appends
  incrementally by monotonic id, so rotated entries never duplicate.
  The sim keeps the log itself (the `last_event` setter records every
  announcement into a 300-entry ring), which also makes events testable
  headlessly.
- Bounties are no longer hostile-only: inspecting any lair (wild warrens,
  wolf dens, kobold burrows, gnome enclaves, camps, covens) offers the
  bounty button; the gold pennant draws over every lair kind, a migrating
  lair carries its flag along, a lair that dies off drops it, and a
  cleared wild lair now takes its creatures with it.
- Tests: `tests/factions_test.gd` (ledger seed/symmetry/drift, claim
  friction, kobold theft, trade on/off, feud threshold, bandit muster +
  mug with exact purse accounting, hag curse landing/blocking
  farms/expiry, cursed harvest carry, three-year soak). Ecology suite
  updated for hill dens and hostile wild lairs; sim suite covers the
  event-log ring (recording, monotonic ids, cap).

## M6.3 — Terrain actions & druid reaction (built, awaiting playtest)

- The world gains `SWAMP` terrain, and open land is split roughly in
  thirds: nine woodlands and nine marshes are seeded first, then grown
  together as organic blobs so each claims about a third of the open
  ground (forest ~32%, marsh ~32%, grass ~36% across seeds). Land is a
  standing tradeoff, not an afterthought. Swamp is walkable but not
  buildable until drained.
- Terrain actions on the inspector card are *ordered work*, not instant
  purchases: paying `drain_cost` (25g) or `clear_cost` (15g) stakes out a
  worksite, then peasants (or a hero lending a hand) invest
  `TERRAIN_WORK_TICKS` labour ticks before the tile becomes grass.
  Draining adds the tile to the open-ground/fog bookkeeping, so the new
  farmland is explorable and buildable at once; pollution (+2 drain, +1
  clear) lands when the work finishes. Dens and buildings block the work;
  costs are vars.
- Marsh chain: `frog_den` (swampfolk, prey, swamp habitat ≥3 within its
  claim) and `owlbear_den` (wilders, predator, diet frogs, farm
  fallback). A den whose land need fails migrates or starves even with a
  full larder, and migration seeks the right terrain. Forest lairs (wolf,
  spider, owlbear, hag) carry the same forest habitat, so felling woods
  under them drives them out. Frog/owlbear spawn weights land in the
  wild tables and `wild_dens_max` rises to 10 for the pair.
- Druid class arrives (drawn by shrines until the M7 Herbalist Grove):
  `protect_wilderness` scores charted wilders/swampfolk lairs and rises
  with pollution; its `protect` goal walks to a wild lair and feeds its
  larder (+1, capped, counted in `wilderness_tended`). Past
  `druid_pollution_limit` (8) the druid departs the defiled realm
  (`druids_departed`, event), and shrines stop drawing new ones while
  the land stays defiled.
- UI/readability: swamp tiles and frog/owlbear den art on map and
  minimap, terrain titles/blurbs/status, druid color and activity lines,
  and the one-tap terrain action on the same inspector card as bounties.
- Tests: new `tests/terrain_test.gd` (ordered drain/clear costs and
  labour, peasant assignment, refusals, frog habitat collapse/migration,
  forest ripple, owlbear prey→farm fallback, druid
  scoring/tending/departure, soak). World suite
  counts swamp; ecology suite maps swamp sites and tolerates lairs
  cleared out from under their beasts; inspector/hero suites cover the
  new rows and shrine attraction.

## M7 — Content & diplomacy pass

Split into staged chunks like M6: the halls and their folk land first, then
the gear economy, then the double-edged diplomacy/necromancy pass.

### M7.1 — Remaining halls & new classes (built)

- Five content halls join the build bar: **blacksmith** (40g), **wizard
  tower** (60g), **ranger hut** (30g), **mead hall** (45g), and **herbalist
  grove** (35g). Each carries its own production timer so a late hall starts
  its cycle when the door opens, not on a global beat.
- **Blacksmith** forges gear points onto its racks (cap 6); **wizard tower**
  gathers mana (cap 9) and scries a radius of the wilds every minute;
  **ranger hut** patrols and reveals the ground around it; **mead hall**
  brews morale (cap 9) that heartens heroes toward bounty flags; **herbalist
  grove** grows herbs (cap 9) and spends them to lift hag curses, and serves
  as a hero's resting hearth when the tavern is farther away.
- New hero classes as content rows: **dwarf craftsman** (blacksmith),
  **wizard** (tower), **ranger** (hut), **barbarian** (mead hall). The
  **druid** now follows the herbalist grove instead of the shrine. A hall
  row's `attracted_by` may list more than one hall (the blacksmith signs
  warriors as well as dwarves).
- Ranger calm: a completed hut keeps predator fallback raids off farms
  within 8 tiles.
- UI/readability: build-bar buttons, building titles/blurbs/statuses, map
  glyphs and class colors for every new hall.
- Tests: `tests/halls_test.gd` (costs, per-building attraction and
  production, multi-hall arrival, tower/ranger fog reveal, grove cures and
  rest choice, long soak). Existing hero/terrain suites updated for the
  druid's move to the grove.

### M7.2 — Experience & the forge economy (built)

- Heroes now earn XP from meaningful ventures, not only kills: exploring,
  tending wild lairs, hunting, looting treasure, honest worksite labour, and
  carousing each pay 1 XP. A class's core pursuit pays an extra point, so a
  rogue grows by treasure and a druid by the wilds. Combat and den-clear XP
  remain unchanged.
- **Blacksmith gear is real.** Heroes with at least 8g walk to a forge that
  has stock and buy one gear point (max 4), turning purse coin back into
  realm gold. Each gear point adds +1 damage to a landed hero hit. Wizards
  pay sages instead and never shop the forge.
- Gear is shown in the hero inspector (`gear N`), the activity line, and as
  pale pips above the level pips on the map.
- Tests: new `tests/hero_progression_test.gd` (activity XP table and
  integration, explore arrival XP, gear scoring/purchase/refusals, forge
  stock, melee bonus); full headless suite green.

### Tuning — Lair regrowth & predator pressure (built)

- The wild fills faster than heroes can empty it: goblin dens seed 3 and cap
  at 5, with a 220-tick respawn rest and 0.65 spawn chance; wild lairs cap at
  16 with a 110-tick rest and 0.55 chance. Failed-site retries are now
  measured in tens of ticks rather than hundreds, so a cleared map recovers
  within a normal session.
- Predator appetites are sharper: larders drain every 90 ticks (was 200),
  packs start hunting at 6 food (was 4), and a starving pack at 2 food sends
  a second hunter out while the first is away.
- Tests: ecology suite covers the hungry/starving hunt thresholds and
  second-hunter behavior; the long-run and pacing suites still pass.
  `tests/hero_progression_test.gd` remains the newest suite, so no README
  command list change was needed.

### Tuning — Population-scaled hero cap (built)

- The hero ceiling now follows the living peasant population at one hero per
  five peasants, minimum one (`hero_cap()`, `hero_cap_per_peasant`). Losing
  people can leave the realm over its means; a growing realm gradually
  earns room for more heroes.
- Over the cap, the realm logs two spaced warnings ("too many", then "some
  may leave"), then a `leave` option joins the hero action table with a pull
  that grows with the overage. A departing hero walks to the nearest
  reachable map rim and is removed from the realm, counted in
  `heroes_departed`; the druid pollution departure uses the same counter.
- Tests: `tests/heroes_test.gd` covers cap scaling, exactly two warnings,
  the leave option, map-edge departure, and the long-run
  spawned = fallen + departed + alive accounting.

### Tuning — Placement breathing room & mobile confirmation (built)

- Buildings now need a full one-tile ring of open ground: `can_build_at()`
  rejects any tile in the 8-neighbor footprint of an existing building or
  construction site, including the keep. The check lives in
  `build_block_reason()`, so the UI can say exactly why a spot is refused.
  `building_padding` is a var, letting layout-focused tests opt out while
  `tests/sim_test.gd` proves the rule itself.
- The build flow is now two-tap for touch screens: choosing a hall stages a
  map tap, which paints a translucent ghost of the building plus its
  footprint and padding ring (green valid, red blocked). A **✓ Place** button
  commits the preview; **✕** cancels. The old tap-to-build shortcut is gone, and the
  over-cap warning gap is tightened from 45 to 30 ticks.

### Tuning — Multi-tile halls & Palace footprint (built)

- Buildings now occupy real footprints, with the keep (the Palace) a centred
  **3x3** and the hall rows scaled to their role: tavern, market, shrine,
  blacksmith, guardhouse, ranger hut and mead hall **2x1**; wizard tower
  **1x2**; herbalist grove **2x2**; farm and house stay **1x1**.
- Footprints are validated tile-by-tile, so every covered tile must be
  charted, clear of dens/works, and have legal terrain. The herbalist grove
  and ranger hut may root on forest or marsh as well as grass; other
  buildings still demand open grass. Padding is now a one-tile ring around
  the whole footprint, not just
  the anchor tile.
- Map art, construction sites, minimap blocks, placement ghosts, selection
  outlines and inspector hit-testing all span the full footprint. Tests keep
  their old compact fixtures via `building_footprints`, while
  `tests/sim_test.gd` proves centred keep occupancy, grove terrain, padding,
  and 2x1 occupancy.

### Tuning — Simulation performance budget (built)

- Population is abstract; at most `PEASANT_AGENT_CAP` (4) visible peasants
  walk the map. Growth, shortage and hero-cap math still use `pop`, so large
  house-driven populations do not create a crowd of pathfinding villagers.
- Real travel routes use Godot's native `AStarGrid2D` (C++); the scripted BFS
  survives only for depth-capped speculative searches. `hero_search_radius`
  (10) bounds frontier probes and alarm chases, while long journeys still get
  a full route.
- `building_origin_at()` uses a tile-to-origin cache keyed by building count
  and footprint mode, so occupancy checks stay cheap as settlements grow.
  Raider alarms now check only the eight neighboring tiles instead of every
  building footprint.
- Stress check (60 buildings, 45 agents, fog/ecology/raids/heroes): ~34 ms/tick
  before, ~2.2 ms/tick after on the dev box. Existing ecology/fog perf budget
  tests remain green.

### Tuning — Hero roster, dismissal & demolition (built)

- The top-left header now carries a live **Heroes x / y** line and a **Hero
  Roster** button. The roster lists every hero's title, level, gear and current
  activity; tapping a row selects that hero for the inspector, even when they
  are standing inside a hall.
- Selecting a hero offers **Dismiss hero** in the inspector. Dismissal uses the
  same exit walk as the over-cap `leave` goal, so the hero heads for the map
  rim and is removed/counted normally; the button disables once they are
  already leaving.
- Friendly buildings can be demolished from the inspector; the Palace is
  excluded. Demolition removes construction sites and completed structures
  without a refund, updates farm/house/hall counters, and removes a
  guardhouse's guards.
- Tests: `tests/heroes_test.gd` covers dismissal and roster counts;
  `tests/agents_test.gd` covers farm/site demolition and the Palace refusal.

### M7.3 — Graveyard, sewers, tribute & the necromancer (built)

- **Graveyard** (50g, 2x2): stores corpses from deaths nearby and slowly
  fills its own stock. Without a shrine ward in range, a stocked graveyard
  periodically raises a hostile undead raider that hunts nearby living folk.
  A shrine's ward suppresses the risings and is surfaced in the inspector.
  The graveyard independently adds 2 safe population for plague checks.
- **Necromancer** hero class: drawn by a graveyard. While one is home, the
  graveyard spends stored corpses to raise temporary **allied undead** (army
  cap 3). Servants fight for the realm, join sieges, and lose loyalty over
  time; expired servants crumble without a corpse.
- **Sewers** (40g, 1x1): attracts rogues as a home hall, draws periodic rats,
  and spoils stored provisions. Each sewer raises the safe population by 4
  (base 6), as does each graveyard by 2. Every 60 ticks a crowded realm
  rolls a 25% base plague chance,
  plus 5% for each person beyond that safe capacity.
- **Tribute** (25g, 200 ticks) on bandit camps and gnome enclaves, offered as
  a second inspector action. Paid bandits stop mustering and release current
  muggings; paid gnomes trade through the feud, cool kobold tension, and stop
  claim friction/feud warbands while the tribute holds.
- Combat/aggro treats rats and hostile undead as attackers, allied undead as
  defenders, and siege pressure counts allied servants. Map/minimap/fog hide
  hostile rats and undead until charted.
- Tests: `tests/m7_rest_test.gd` covers content rows, corpse storage, risings,
  necromancer raising/decay, shrine wards, rats/provision loss, plague control,
  and bandit/gnome tribute behavior.

### Hero combat tuning & explore bounties (built)

- Hero base HP was cut by about 20% across the class table. Level-ups still
  add 2 max HP and heal to full.
- Hero attacks now roll accuracy: 40% at level 1, +5% per level, capped at
  90%. Guards and allied undead remain deterministic.
- Damage per landed hit is 4, +1 every three levels, plus gear; sieges use
  the same roll and damage. This replaces the old level+1+gear deterministic
  swing, so veterans hit more reliably rather than simply harder.
- **Explore bounties** (20g, same 2g crown fee) can be posted on reachable
  uncharted tiles. They stack, draw heroes toward that exact spot, show a
  gold marker through the fog, and pay the arriving hero the net purse.
- Tests: `heroes_test.gd` covers explore posting, stacking, targeting,
  arrival payout, and charting; `hero_progression_test.gd` covers accuracy,
  damage breakpoints, HP cuts, and probabilistic gear hits.

### Player manual & in-game reference (built)

- `MANUAL.md` is the player-facing guide: core loop, economy, fog and terrain,
  every hall, hero attraction/levels/caps/gear, bounties, combat, ecology,
  faction diplomacy, tribute, graveyards, sewers and recovery.
- The bottom-right book button opens the same Markdown in a scrollable
  in-game card. `scripts/manual.gd` renders its small Markdown subset to
  BBCode, so the repository copy and the game text stay in sync.
- `MANUAL.md` is included in the web export; `tests/manual_test.gd` guards
  the file's major sections and the Markdown-to-BBCode conversion.

## M8 — Session layer & polish

- Save/load (pause + place buildings; autosave; no away-simulation).
- Chronicle log (readable on demand).
- Season/events cycle; difficulty tuning to the 10-15 minute session target;
  soft-fail audit.

## Later (out of scope for now)

- Real art pass (palette-locked 32x32), paper-doll hero sprites.
- Native mobile ports, iOS signing via a Mac.
