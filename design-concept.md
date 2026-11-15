# Project Brief: Casual Indirect-Control Fantasy Kingdom Sim

## Concept
A real-time fantasy kingdom builder in the spirit of Majesty (and, loosely, Dungeon Keeper). The player builds and shapes the kingdom but never directly commands heroes or creatures. Autonomous agents decide what to do based on incentives and the world around them. Creature variety is inspired by D&D-style bestiaries.

## Design constraints
- **Casual play:** The player has limited time and attention, so no heavy micromanagement, steep learning curve, or long practice requirements.
- **Real-time with pause:** The sim runs in real time. The player can pause and place buildings while paused, and can save and resume later. There is no "while you were away" simulation.
- **Interruption-friendly:** Autosave constantly, make sessions work in about 10 to 15 minutes, and avoid harsh fail states.
- **Open wilderness feel:** The kingdom is a small lit pocket in a large, dangerous map. Exploration and fog of war are driven by heroes wandering, so discovery stays indirect.

## Core loop
Agents pick actions by scoring incentives (bounties, flags, needs, personality weights). Creature and hero variety comes from different weightings. For example, a rogue loves treasure flags, while a paladin ignores gold and chases evil lairs.

## Depth systems (chosen)
1. **Attraction by building:** Buildings draw specific types. A tavern draws bards and rogues, a shrine draws clerics, and a graveyard draws necromancers and undead. The player shapes the population through placement.
2. **Ecology and factions:** Creatures are not just enemies. Goblins raid, owlbears defend territory, and kobolds feud with gnomes. Building and terrain choices shift the balance. For example, draining a swamp may drive out hags and also remove frogs that druids like.

## Optional additions (not yet chosen)
- Hero relationships, rivalries, and persistent names and traits
- A **chronicle** log of notable events, read on demand
- Villager contracts and requests with no deadline pressure
- Seasons and events
- Taming or allying with monsters through tribute or territory deals
- A second light resource such as renown or mana, gating a few one-tap actions

## World and presentation
- **View:** Top-down / 3/4 view with tilemap terrain (recommended over isometric for mobile, art consistency, and agent-friendliness).
- **World:** A large map with a small viewport, pan and pinch-zoom, a zoom-out cap, and a minimap.
- **Terrain:** Forests, swamps, mountains, ruins, and caves, each with distinct residents.
- **Fog of war:** Soft-edged. Heroes reveal terrain as they explore.
- **Landmarks:** Ruins, shrines, monster dens, and hidden camps appear as fog lifts.
- **Wild borders:** Edges stay dangerous and unclaimed.
- **Performance:** Use chunked tilemaps and avoid simulating unexplored areas at full detail.

## Platforms and input
- **Targets:** Mac first, mobile eventually.
- **Touch-friendly from the start:** Tap a spot, pick from a short menu. Tap a hero or creature to inspect mood, goals, and relationships. Keep the main screen free of clutter, and show faction tension and territory through icons or tinting.
- **Prototype on desktop first.** Mobile should be a port, not a redesign.

## Tech approach (recommendations, not final decisions)
- **Engine:** Godot 4 (text-based scenes and scripts, headless mode, Mac/iOS/Android export). Alternative: TypeScript with Phaser or PixiJS, wrapped with Capacitor for mobile.
- **Agent-friendly architecture:**
  - Keep the simulation separate from rendering so it can run headless.
  - Define creatures, buildings, and factions as data files (JSON or YAML).
  - Have the agent write headless tests, such as "simulate 10 game-years and check for deadlocks."
- **Development environment:**
  - Agents run on a Raspberry Pi 5 (always-on server).
  - Headless sim tests, git, and code edits work on the Pi.
  - Use the Compatibility (OpenGL) renderer. Avoid Vulkan-based renderers on Pi.
  - Visual playtesting and screenshots may need Xvfb on the Pi, or the Windows/WSL desktop.
  - iOS builds, signing, and notarization require a Mac with Xcode.
  - Verify current Godot ARM64 editor and export-template availability before relying on them.

## Art approach
- **Start with placeholder shapes** so the sim is playable before any art exists.
- **Later options:**
  - Pixel-art-focused generators (e.g., PixelLab, Retro Diffusion) for consistent sprites.
  - Paper-doll layered sprites (body, armor, weapon, palette swaps) for large hero variety from few assets.
  - Agent-written procedural art for buildings, terrain, and effects.
- **Style lock:** Fixed canvas size (32x32 or 64x64), one palette, one view angle, side-facing sprites that flip. Use a post-process script to snap art to the palette.
- **Policy:** Check Steam's AI-content disclosure rules and App Store policies before release. Verify tool licensing.

## Existing games to try (for reference)
- **Majesty-likes:** Lessaria: Fantasy Kingdom Sim, Crown of Greed, Driftland: The Magic Revival
- **Dungeon Keeper-likes:** Dungeons 3 and 4, War for the Overworld, Evil Genius 2
- **Indirect colony sims:** Dwarf Fortress, RimWorld

## Instructions for the agent
Build a minimal playable prototype first: a small map, a handful of creature types, 2-3 factions, and 4-6 buildings with attraction rules, all using placeholder art. Prioritize a working sim loop and headless tests before visuals. Surprise the user with sensible creative choices within these constraints.

