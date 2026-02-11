# AOEM Roadmap

## Current State (Prototype Complete)

Working prototype with: isometric tilemap, 6 unit types, 9 building types, resource gathering (food/wood/gold), production queues, fog of war, A* pathfinding, AI opponent, 3-age progression, combat with counter system, minimap, and full HUD.

---

## Phase 1: Visual Overhaul (Placeholder Art -> Real Art)

### 1.1 Sprite-Based Units
- [ ] Replace colored circles with animated sprite sheets (idle, walk, attack, gather, die)
- [ ] Per-unit-type sprite sets (villager, infantry, archer, cavalry, scout, siege)
- [ ] Directional facing (8 directions for isometric)
- [ ] Team color tinting on sprites (not separate ring)

### 1.2 Building Art
- [ ] Replace colored diamonds with isometric building sprites
- [ ] Construction animation (scaffolding stages: 0%, 33%, 66%, 100%)
- [ ] Destruction animation (rubble sprite on death)
- [ ] Smoke/fire particles when damaged below 50% HP

### 1.3 Terrain Tileset
- [ ] Replace flat colored tiles with textured isometric tileset
- [ ] Terrain blending at biome edges (grass-to-sand, grass-to-water)
- [ ] Animated water tiles
- [ ] Tree sprites on forest tiles (fall when chopped)
- [ ] Gold/stone mine sprites with depletion stages

### 1.4 UI Redesign
- [ ] Custom theme (medieval/parchment style instead of default Godot)
- [ ] Unit/building portrait icons for selection panel
- [ ] Proper resource icons (not just colored text)
- [ ] Stylized buttons with pressed/hover states
- [ ] Build menu as grid of icon buttons (not text list)

### 1.5 VFX & Juice
- [ ] Attack particles (sword slash, arrow projectile, siege boulder)
- [ ] Resource gather particles (wood chips, gold sparkle)
- [ ] Building placement dust cloud
- [ ] Death effects (unit falls, blood splash)
- [ ] Selection ring as ground decal (not drawn circle)
- [ ] Rally point flag sprite with line to building

---

## Phase 2: Gameplay Polish

### 2.1 Formation & Movement
- [ ] Group formation when moving multiple units (not all stacking on one point)
- [ ] Spread units in arc/line at destination
- [ ] Collision avoidance between friendly units (steering behaviors)
- [ ] Attack-move command (move but engage enemies along path)
- [ ] Patrol command

### 2.2 Gathering Improvements
- [ ] Farms as renewable food (build, villager auto-farms, reseeds)
- [ ] Villager auto-retarget when resource depletes (find nearest same-type)
- [ ] Drop-off building auto-detection by resource type (lumber camp for wood)
- [ ] Villagers show carry animation (hold bundle of wood, basket of food)
- [ ] Gather rate upgrades per age

### 2.3 Building System
- [ ] Building queue: queue multiple buildings for placement
- [ ] Multi-villager construction (faster with more villagers)
- [ ] Building upgrades (Town Center → Castle in Age 3)
- [ ] Gates and walls (Age 2+)
- [ ] Watch towers with garrison (units inside shoot arrows)

### 2.4 Combat Depth
- [ ] Projectile system (arrows travel through air, can miss)
- [ ] Garrison mechanic (units enter buildings for protection + arrow fire)
- [ ] Healing: monks/healers unit type
- [ ] Unit upgrades (blacksmith: +1 attack, +1 armor per age)
- [ ] Stance system: aggressive / defensive / stand ground / no attack

### 2.5 Economy
- [ ] Trade routes between markets (gold income over distance)
- [ ] Relics on sacred sites (monks carry to monastery for gold trickle)
- [ ] Tribute resources to ally (for multiplayer)
- [ ] Population cap increase via houses (currently 10 per house — tune this)

---

## Phase 3: Mobile-First UX

### 3.1 Touch Controls
- [ ] Pinch-to-zoom smoothing and limits
- [ ] Tap unit → tap ground = move (current flow, verify feel)
- [ ] Long-press for context menu (attack/gather/build options)
- [ ] Swipe-from-edge for quick-access panels
- [ ] Double-tap minimap to jump camera

### 3.2 Mobile HUD
- [ ] Bottom-anchored action bar (thumb-reachable)
- [ ] Collapsible resource bar (swipe to hide/show details)
- [ ] Unit action buttons (move, stop, attack, patrol) as bottom icons
- [ ] Quick-select buttons: "select all military", "select all idle villagers"
- [ ] Idle villager alert button (flashing icon when villagers idle)

### 3.3 Quality of Life
- [ ] Idle villager notification with tap-to-select
- [ ] "Find my army" button (centers on military units)
- [ ] Auto-queue toggle for production buildings (keep training)
- [ ] Rally point visual (flag + line from building)
- [ ] Event log feed (top of screen): "Villager killed", "Building completed", "Under attack"

### 3.4 Performance
- [ ] Object pooling for units/projectiles (avoid GC spikes)
- [ ] Culling: don't process units off-screen
- [ ] LOD system: simplify distant units to dots
- [ ] Batch draw calls for terrain tiles
- [ ] Profile and optimize A* pathfinding for 50+ unit armies

---

## Phase 4: Audio

### 4.1 Sound Effects
- [ ] Unit acknowledgment voices ("Yes?", "Right away", "Wololo")
- [ ] Attack sounds (sword clash, bow twang, siege crash)
- [ ] Building construction hammer sounds
- [ ] Resource gathering sounds (chopping, mining, farming)
- [ ] UI click/hover sounds
- [ ] Alert sounds (under attack horn, age up fanfare)

### 4.2 Music
- [ ] Main menu theme
- [ ] In-game ambient tracks (calm economy, tense combat)
- [ ] Dynamic music system (crossfade between peace/war based on combat state)
- [ ] Victory/defeat stingers

---

## Phase 5: Advanced AI

### 5.1 Smarter Decisions
- [ ] AI scouting (send scout to explore map early)
- [ ] AI adapts strategy to player behavior (rush defense if player rushes)
- [ ] AI build order priorities tuned per difficulty
- [ ] AI retreats damaged units to heal
- [ ] AI targets high-value units (siege, villagers) in combat

### 5.2 AI Personalities
- [ ] Rusher: early military pressure
- [ ] Boomer: fast economy, late-game army
- [ ] Turtler: walls, towers, defensive play
- [ ] Random: picks a personality each game

### 5.3 Difficulty Scaling
- [ ] Easy: slower decisions, smaller armies, no counter-unit targeting
- [ ] Medium: balanced play, some mistakes
- [ ] Hard: optimized build orders, perfect micro, counter-unit targeting
- [ ] Resource bonus for AI on higher difficulties (standard RTS approach)

---

## Phase 6: Map & Content

### 6.1 Map Variety
- [ ] Multiple biomes: grassland, desert, winter, tropical
- [ ] Map size options: small (24x24), medium (32x32), large (48x48)
- [ ] Map types: open, closed (forest walls), islands (water between bases), arena
- [ ] Elevation system (hills give attack bonus)
- [ ] Random map seed display for replaying

### 6.2 Civilizations
- [ ] 3-4 unique civilizations with different bonuses
- [ ] Unique units per civilization (1-2 per civ)
- [ ] Economic bonuses (e.g., faster gathering, cheaper buildings)
- [ ] Military bonuses (e.g., stronger cavalry, longer archer range)
- [ ] Civ selection screen pre-game

### 6.3 Game Modes
- [ ] Skirmish (vs AI, current mode — polish this first)
- [ ] Campaign: scripted single-player missions with objectives
- [ ] Survival: endless waves of enemies
- [ ] King of the Hill: control sacred site to win

---

## Phase 7: Multiplayer

### 7.1 Local Multiplayer
- [ ] Split-screen or shared-screen hot-seat mode
- [ ] Pass-and-play turn-based variant

### 7.2 Online Multiplayer
- [ ] Lobby system (create/join game)
- [ ] Peer-to-peer or client-server architecture decision
- [ ] Deterministic lockstep simulation (standard RTS networking)
- [ ] Replay system (save game state for playback)
- [ ] Anti-cheat: server-authoritative resource/unit validation

### 7.3 Social
- [ ] Player profiles and match history
- [ ] ELO/ranked matchmaking
- [ ] Friend list and invite system
- [ ] Spectator mode
- [ ] Chat (pre-game lobby, in-game taunts)

---

## Phase 8: Monetization & Distribution

### 8.1 Mobile Release
- [ ] App Store / Google Play submission
- [ ] Screen size adaptation (phone, tablet, foldable)
- [ ] Battery/thermal optimization
- [ ] Offline play support
- [ ] Cloud save

### 8.2 Monetization (if applicable)
- [ ] Cosmetic skins for units/buildings
- [ ] Civilization unlocks
- [ ] Battle pass with seasonal rewards
- [ ] No pay-to-win: all gameplay content earnable

---

## Priority Order

**Ship-ready MVP (Phases 1-3):**
The game becomes a real product once it has proper art, polished gameplay, and mobile-native controls. This is the target for a soft launch.

**Full Experience (Phases 4-6):**
Audio, smarter AI, and content variety make it a game people want to play more than once.

**Scale (Phases 7-8):**
Multiplayer and distribution turn it into a live game.

---

## Quick Wins (Can Do Now)

These are small improvements that make the current prototype feel much better:

1. **Formation spreading** — offset unit destinations so they don't stack
2. **Idle villager indicator** — flash a UI button when villagers have nothing to do
3. **Auto-queue toggle** — checkbox on production buildings to repeat training
4. **Event notifications** — text feed for "Under attack!", "Building complete", etc.
5. **Unit count badges** — show "x5" on selection panel when multiple units selected
6. **Villager auto-retarget** — when a resource depletes, find the nearest same-type
7. **Camera bounds** — prevent scrolling off the edge of the map
8. **Better minimap click** — click minimap to jump camera to that location
9. **Rally point visual** — draw a flag/line from building to rally point
10. **Speed controls** — 1x, 2x, 3x game speed buttons for single player
