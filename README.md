# Realm Builder — Fantasy Kingdom Sim

A real-time, indirect-control fantasy kingdom sim (Godot 4), prototyped
headless on a Raspberry Pi 5 and playable on any device via the web build.

- `design-concept.md` — project brief and constraints
- `content-design.md` — bestiary, heroes, buildings, ecology (data-ready tables)

## Requirements

- Godot 4.7+ (standard/GDScript build, ARM64 Linux is fine)
- Python 3 (for the HTTPS dev server)
- A browser on any device on the LAN (phone or Mac)

## Install

The Pi runs the official Godot binary from `~/.local/opt/godot`, symlinked to
`~/.local/bin/godot`:

```sh
mkdir -p ~/.local/opt ~/.local/bin
cd ~/.local/opt
curl -L -o godot.zip "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip"
unzip godot.zip && rm godot.zip
mv Godot_v4.7.2-stable_linux.arm64 godot && chmod +x godot
ln -sf ~/.local/opt/godot ~/.local/bin/godot
```

System dependencies:

```sh
sudo apt-get install -y libfontconfig1
```

Web export templates (needed for `--export-release`) go to
`~/.local/share/godot/export_templates/<version>.stable/`:

```sh
curl -L -o /tmp/templates.tpz "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable
unzip /tmp/templates.tpz -d /tmp/godot_tpz
mv /tmp/godot_tpz/templates/* ~/.local/share/godot/export_templates/4.7.2.stable/
```

## Common commands (from the repo root)

```sh
# Run the sim logic test (headless)
godot --headless --script tests/sim_test.gd

# Run the agent tests (peasants, builders, tax collector)
godot --headless --script tests/agents_test.gd

# Run the inspector content tests (blurbs, statuses)
godot --headless --script tests/inspect_test.gd

# Run the raid tests (dens, warbands, guards, den clearing)
godot --headless --script tests/raids_test.gd

# Run the hero tests (attraction, incentive scoring, bounty flow, loot)
godot --headless --script tests/heroes_test.gd

# Run the fog-of-war tests (reveal, landmarks, gating, perf budget)
godot --headless --script tests/fog_test.gd

# Run the ecology tests (wild dens, creatures, food chains, migration)
godot --headless --script tests/ecology_test.gd

# Run the faction tests (tension, kobold/gnome feud, bandits, hags)
godot --headless --script tests/factions_test.gd

# Run the terrain tests (drain/clear, marsh chain, druid reaction)
godot --headless --script tests/terrain_test.gd

# First editor scan (builds .godot/ cache, registers class_name)
godot --headless --editor --quit

# Run the game headless for a few frames (sanity check)
godot --headless --quit-after 5

# Export the web build (target dir must exist)
mkdir -p builds/web
godot --headless --export-release "Web" builds/web/index.html
```

## Hosting (HTTPS on the LAN)

Godot web builds require a **secure context**, so the build must be served
over HTTPS (even locally). `server/serve_https.py` handles this with a
self-signed certificate.

One-time certificate setup:

```sh
mkdir -p server/certs
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout server/certs/key.pem -out server/certs/cert.pem \
  -subj "/CN=majesty-pi"
```

Serve manually:

```sh
python3 server/serve_https.py   # listens on 0.0.0.0:8443
```

Or as a persistent systemd user service (already configured):

```sh
systemctl --user daemon-reload
systemctl --user enable --now majesty-web
systemctl --user status majesty-web
```

Then open **https://<pi-ip>:8443** on a phone or Mac. The browser will show a
certificate warning (self-signed); accept it to proceed:

- Safari (iOS): Show Details → visit this website
- Safari (macOS): Show Details → Visit Website
- Chrome: Advanced → Proceed

Note: the systemd service stops when the user logs out; to keep it running
unattended, enable linger: `sudo loginctl enable-linger $USER`.

## Project layout

```
project.godot          Godot project config (gl_compatibility renderer)
scenes/main.tscn       Main scene (UI + game view)
scripts/kingdom.gd     Pure simulation logic (no UI dependencies)
scripts/agents.gd      Pure sim agents: peasants, tax collector, goblin raiders, guards, heroes, wild creatures
scripts/descriptions.gd  Inspector flavor text (blurbs, vague statuses)
scripts/minimap.gd       Miniature map (charted ground, viewport outline, tap-to-jump)
scripts/main.gd        View layer: wires UI to the sim
scripts/*.gd.uid       Godot stable resource IDs (tracked in git)
tests/sim_test.gd      Headless sim test
tests/agents_test.gd   Headless agent tests (construction, tax, delivery, deadlock)
tests/inspect_test.gd  Headless inspector content tests
tests/raids_test.gd    Headless raid tests (dens, cooldowns, razes, guards, clearing)
tests/heroes_test.gd   Headless hero tests (attraction, scoring, bounties, loot)
tests/fog_test.gd      Headless fog tests (reveal, landmarks, gating, perf)
tests/ecology_test.gd  Headless ecology tests (wild dens, food chains, migration)
tests/factions_test.gd  Headless faction tests (tension, feud, bandits, curses)
tests/terrain_test.gd   Headless terrain-action tests (marsh chain, druid)
server/serve_https.py  LAN HTTPS server for the web build
builds/web/            Exported web build (regenerable, not committed)
export_presets.cfg     Web export preset (thread support off)
content-design.md      Starting content: creatures, heroes, buildings, ecology
design-concept.md      Original project brief
```

## Development notes

- The sim (`scripts/kingdom.gd`) is deliberately separate from rendering so it
  runs headless; new mechanics should be testable via CLI before any UI.
- Content additions should follow the tables in `content-design.md` — variety
  comes from data rows, not new code paths.
- Export templates and builds are large; both are gitignored.
- Final macOS/iOS packaging needs a Mac with Xcode (Godot can't sign Apple
  builds from Linux). The web build is the cross-device prototyping path.
