# Content Reference: Bestiary, Heroes, Buildings & Ecology

> Agent-authored starting content for the kingdom sim. IDs are stable and
> data-friendly: every entry below is meant to migrate verbatim into JSON/YAML
> data files later. Numbers are tuning seeds, not final values.

---

## 1. Heroes (recruitable agents)

Heroes are autonomous. Each has an incentive-weight table; buildings attract
them; the player never commands them directly.

### 1.1 Lawful core (early game backbone)

| id | class | primary incentive | secondary | attracted by | quirk |
|----|-------|-------------------|-----------|--------------|-------|
| paladin | Paladin | smite evil (`lair_evil` weight 9) | defend flag (7) | Shrine | refuses tavern bounties that are dishonest; never loots |
| warrior | Warrior | bounty flag (8) | defend flag (6) | Guardhouse | becomes drunk-buff after long tavern stays |
| cleric | Cleric | heal / resurrect (8) | `lair_evil` undead (7) | Shrine | will follow wounded allies automatically |
| wizard | Wizard | `lair_arcane` (8) | artifact flags (6) | Wizard Tower | hoards scrolls; pays gold to sages instead of buying gear |

### 1.2 Neutral & wild

| id | class | primary incentive | secondary | attracted by | quirk |
|----|-------|-------------------|-----------|--------------|-------|
| rogue | Rogue | treasure flag (9) | explore flag (7) | Tavern | keeps 20% of loot for self; hates taxes |
| ranger | Ranger | explore flag (8) | ecology flags (7) | Ranger Hut | never damages wild terrain; feeds friendly beasts |
| bard | Bard | wanderlust (7) | morale events (6) | Tavern | buffs nearby heroes' reward weighting (+15%) |
| barbarian | Barbarian | combat bounty (9) | food flag (5) | Mead Hall | ignores retreat logic; grudge memory per faction |
| druid | Druid | protect wilderness (9) | punish polluters (7) | Herbalist Grove | turns hostile if kingdom deforests or drains swamps |

### 1.3 Shady (late game, double-edged)

| id | class | primary incentive | secondary | attracted by | quirk |
|----|-------|-------------------|-----------|--------------|-------|
| necromancer | Necromancer | `lair_undead` (9) | graveyard events (7) | Graveyard | raises fallen heroes as temporary allies (loyalty decays) |
| dwarf | Dwarf Craftsman | repair/upgrade flag (8) | gold flag (6) | Blacksmith | refuses to enter caves; immune to fear |
| halfling | Halfling Scout | explore flag (6) | food flags (7) | Tavern | unstealable: traps can't catch them; cowardly |

**Hero needs (background simulation):** heroes accrue `fatigue`, `hunger`,
`greed`, `fear`. Low satisfaction lowers their presence (they visit taverns,
shop for gear, or leave the realm). A hero who dies drops their gear as a
treasure flag — rogues will race to it.

---

## 2. Villagers & support units (non-hero)

| id | role | behavior | notes |
|----|------|----------|-------|
| peasant | economy | works farm/market, flees combat | backbone of taxes & food |
| guard | militia | patrol radius, weak combat | free, from Guardhouse |
| merchant | trade | visits market, random caravans | gold trickle; bandit target |

---

## 3. Buildings

Player placeable. Each declares `attracts`, `produces`, and `flags_emitted`.
Attraction decays with distance, so placement shapes hero movement.

| id | name | cost | produces | attracts | flags emitted | notes |
|----|------|------|----------|----------|---------------|-------|
| castle | Keep | (start) | pop cap +5, tax hub | peasants | defend (wide) | one per map; heroes pray here |
| farm | Farm | 10g | food +2/tick, tithe 1g (cap 6) | halfling | — | goblins raid these first |
| house | House | 15g | pop cap +3, tax 1g (cap 15) | peasants | — | from prototype |
| market | Market | 30g | gold +1/tick per pop, tax 3g (cap 30) | merchant, rogue (shop) | guard_routes | enables hero shopping |
| tavern | Tavern | 25g | morale, gossip, tax 2g (cap 20) | bard, rogue, halfling, barbarian | bounty (weak) | heroes gossip: reveals map hints |
| guardhouse | Guardhouse | 30g | guards x2 (no tax: crown service) | warrior, dwarf | defend (radius 6) | patrols clear nearby raider camps |
| shrine | Shrine | 35g | bless radius (no tax: crown service) | cleric, paladin | smite_evil (weak) | cures curses; undead avoid its aura |
| blacksmith | Blacksmith | 40g | gear points | dwarf, warrior | upgrade_hero | heroes with gear win more |
| wizard_tower | Wizard Tower | 60g | mana trickle | wizard | explore (arcane sense) | reveals landmarks slowly |
| ranger_hut | Ranger Hut | 30g | map edges revealed | ranger, druid | explore, protect | calms aggressive wildlife in radius |
| mead_hall | Mead Hall | 45g | barbarian morale | barbarian | bounty (strong) | barbarians drink, then fight |
| herbalist_grove | Herbalist Grove | 35g | healing herbs | druid, cleric | protect | heals without shrine; forest-friendly |
| graveyard | Graveyard | 50g | corpse storage | necromancer | undead (dangerous) | double-edged: undead risks vs. necromancer power |
| sewers | Sewers | 40g | plague control | rogue (den) | — | rogues use as hideout; attracts rats |

### Flavor blurbs (inspector)

Tap-to-inspect text lives in `scripts/descriptions.gd`, kept in spirit-sync
with the tables above: blurbs hint at what a building produces, attracts, or
risks, and statuses use wording tiers ("a modest purse") instead of exact
formulas. Exact mechanics stay in the sim; when adding a building or unit,
add its title/blurb row to `descriptions.gd` in the same change.

**Not player-buildable (found in wilderness):** monster dens, ruins, camps,
shrine ruins. These are terrain features that anchor ecology (see §5).

---

## 4. Creatures & factions

Creatures spawn from terrain dens, not from thin air. Each faction has a
stance toward the kingdom and other factions. Territory is expressed as a
claim radius around dens; claims overlap → tension.

### 4.1 Factions

| id | faction | stance | behavior summary |
|----|---------|--------|------------------|
| goblinkin | Goblinkin | hostile, raiding | raids farms/markets for food & gold; grows dens when raids succeed |
| kobolds | Kobold Tribes | neutral-greedy | steal chickens & shiny trash; trap-setters; feud: gnomes |
| gnomes | Gnome Enclaves | friendly-ish | tinkerers; trade gadgets; feud: kobolds |
| bandits | Bandit Companies | hostile, human | ambush caravans, rob heroes; bribable with tribute |
| hags | Hag Covens | hostile, indirect | curse buildings; trade "boons" for terrible prices |
| wilders | Wild Beasts | territorial | defend claims; only attack if provoked/territory built on |
| unquiet | Unquiet Dead | hostile, opportunistic | rise in ruins & graveyards; grow with necromancy |
| swampfolk | Swampfolk | ambivalent | hags' lesser kin; dangerous but semi-sentient traders |

### 4.2 Bestiary by terrain

**Forest**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| wolf | Grey Wolf | wilders | rabbits, frogs | low | hunts in packs of 2-4; fears fires |
| spider_giant | Giant Spider | wilders | goblins, wolves | medium | web dens near paths |
| dryad | Dryad | wilders | — | 0 (guardian) | tied to an ancient tree; attack if forest cut |
| boar | Wild Boar | wilders | roots, crops | low | tramples farms when food scarce |

**Swamp**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| frog | Giant Frog | swampfolk | flies, small beasts | 0 | base of food chain; druids love them |
| hag | Swamp Hag | hags | villagers (cursed deals) | indirect | the only creature that *trades* |
| bogling | Bogling | swampfolk | frogs, carrion | low | mob animal; swarm when hag is killed |
| willow | Grim Willow | swampfolk | travelers | low | stationary trap on swamp edges |

**Mountain**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| harpy | Harpy | wilders | goats, heroes | medium | nest cliffs; steal shiny from rogues |
| golem | Stone Golem | unclaimed | — | territorial | guardian of ruins/veins; ignores non-miners |
| gnome | Gnome | gnomes | — | low | enclave spawns tinker stalls |

**Cave / underground**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| goblin | Goblin | goblinkin | anything stolen | high | main raider unit |
| hobgoblin | Hobgoblin | goblinkin | discipline | high | appears when goblin dens grow large (warband) |
| kobold | Kobold | kobolds | chickens, buttons | medium | traps: snare/pit/bucket |
| bat | Cave Bat | wilders | insects | 0 | ambient; food for spiders |
| troll | Bridge Troll | unclaimed | tolls (meat) | medium | lairs near rivers; toll = 10g or fight |
| rat_giant | Giant Rat | unclaimed | garbage | low | from sewers & ruins; swarm vector for plague |

**Ruins / graveyard**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| skeleton | Skeleton | unquiet | — | medium | guards burial loot |
| wight | Barrow Wight | unquiet | life force | high | boss-tier for early game; shrines weaken it |
| ghoul | Ghoul | unquiet | corpses | medium | drawn to graveyards & battlefields |
| mimic | Mimic | unclaimed | greedy heroes | high | guards treasure flags; punishes careless rogues |

**Plains / roads**
| id | creature | faction | diet | aggression | notes |
|----|----------|---------|------|------------|-------|
| bandit | Bandit | bandits | caravans, taxes | high | camps; camps respawn unless cleared |
| owlbear | Owlbear | wilders | frogs, honey, boar | territorial | does not raid; attacks anyone entering its claim |
| gnoll | Gnoll | bandits | carrion, scraps | high | scavenge bandit leavings; cowardly in small numbers |

### 4.3 Faction tension matrix

Start values in `-3..+3` (positive = alliance-lean). Events shift them.

| | goblinkin | kobolds | gnomes | bandits | hags | wilders | unquiet |
|---|---|---|---|---|---|---|---|
| goblinkin | — | +1 | -3 | +1 | 0 | -1 | +1 |
| kobolds | +1 | — | **-3 (feud)** | 0 | 0 | 0 | -1 |
| gnomes | -3 | -3 | — | -1 | -1 | +1 | -2 |
| bandits | +1 | 0 | -1 | — | +1 | 0 | 0 |
| hags | 0 | 0 | -1 | +1 | — | +1 (swamp pact) | +1 |
| wilders | -1 | 0 | +1 | 0 | +1 | — | -2 |
| unquiet | +1 | -1 | -2 | 0 | +1 | -2 | — |

The **kobold–gnome feud** is a designed pressure point: peace between them
requires either territory separation or gnome tribute, both player actions.

---

## 5. Ecology chains

Creatures eat each other; player actions ripple through the chain.

```
flies → frogs → owlbears
rabbits → wolves → (packs raid farms only if rabbits die out)
goblins → giant spiders
giant rats → spiders / foxes (fox: forest, neutral)
boar crops → boars near farms → wolf packs follow boars
```

**Worked example (from the brief): draining a swamp**
1. Player drains swamp tiles for farmland.
2. Hag coven loses habitat → hags migrate to the nearest wet ruins and start
   cursing the farms that displaced them.
3. Frog population collapses → owlbear food drops → owlbears expand claims
   toward farms → farm raids.
4. Boglings swarm with no hag to keep them fed → mild early-game menace.
5. Druid heroes notice: `protect_wilderness` incentive fires; druids may
   leave or become hostile unless the grove is compensated (plant 5 trees).

**Rule of thumb:** every den has a `needs` list (food/terrain). If `needs`
are unmet for N ticks, the den migrates or starves. Starvation is visible
(indirect storytelling) rather than announced.

### 5.1 Spawning & density caps

- Each terrain type lists its spawn table with weights (e.g., swamp: frog 40%,
  bogling 30%, hag 10%, willow 10%, rat 10%).
- Global cap per faction scales with total den count; no dens → faction dies
  out locally (can return via immigration from map edges).
- Wild borders always contain at least one den of each base terrain type.

---

## 6. Incentive & flag mapping (how the player nudges)

The player speaks to agents only through buildings, terrain, and flags:

| Player action | Agent signal |
|---------------|--------------|
| Build tavern + post bounty | rogues/barbarians pick up bounty flag |
| Build guardhouse | warriors receive defend flag on radius |
| Market caravan leaves | rogue escort / bandit ambush flags on the road |
| Drain swamp / clear forest | druid polluter-punish flag fires |
| Graveyard built | necromancer attraction up; unquiet rises |
| Tribute to bandit camp | bandit stance +1 for 200 ticks |
| Shrine aura | paladins/clerics patrol from it; undead repelled |

Personality weights multiply these flags; that's the whole agent-decision
loop. Adding a new creature = adding rows to the tables above.

---

## 7. Tuning seeds (starting numbers)

| param | value |
|-------|-------|
| hero upkeep (gold/tick) | 1 |
| creature spawn interval per den | 120 ticks ± 40% |
| raid cooldown (goblin) | 400 ticks |
| den migration threshold | needs unmet 300 ticks |
| faction tension decay toward 0 | 1 / 500 ticks |
| hero grudge memory | 5000 ticks |
| owlbear claim radius | 8 tiles |
| kobold theft cooldown | 150 ticks |

---

*Design intent: content adds variety through table rows, not new code. If a
new creature can't be expressed as a row, the sim layer needs work first.*
