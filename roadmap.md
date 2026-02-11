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
- [x] Group formation when moving multiple units (spiral offsets)
- [x] Spread units in arc/line at destination
- [ ] Collision avoidance between friendly units (steering behaviors)
- [x] Attack-move command (move but engage enemies along path)
- [ ] Patrol command

### 2.2 Gathering Improvements
- [x] Farms as renewable food (build, villager auto-farms, reseeds)
- [x] Villager auto-retarget when resource depletes (find nearest same-type)
- [x] Drop-off building auto-detection by resource type (lumber camp for wood)
- [ ] Villagers show carry animation (hold bundle of wood, basket of food)
- [x] Gather rate upgrades per age (Wheelbarrow research)

### 2.3 Building System
- [ ] Building queue: queue multiple buildings for placement
- [x] Multi-villager construction (faster with more villagers)
- [ ] Building upgrades (Town Center → Castle in Age 3)
- [ ] Gates and walls (Age 2+)
- [x] Watch towers with garrison (tower auto-attacks enemies)

### 2.4 Combat Depth
- [x] Projectile system (arrow VFX for ranged attacks)
- [ ] Garrison mechanic (units enter buildings for protection + arrow fire)
- [ ] Healing: monks/healers unit type
- [x] Unit upgrades (blacksmith: +2 attack, +1 armor, +gather, +villager HP)
- [x] Stance system: aggressive / stand ground

### 2.5 Economy
- [ ] Trade routes between markets (gold income over distance)
- [ ] Relics on sacred sites (monks carry to monastery for gold trickle)
- [ ] Tribute resources to ally (for multiplayer)
- [x] Population cap increase via houses (10 per house)

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

## Quick Wins — COMPLETED (Iterations 11-17)

All quick wins have been implemented:

1. ~~Formation spreading~~ — spiral offsets for unit destinations
2. ~~Idle villager indicator~~ — gold flashing button when villagers idle
3. ~~Auto-queue toggle~~ — checkbox on production buildings
4. ~~Event notifications~~ — scrolling feed: under attack, building complete, unit trained, etc.
5. ~~Unit count badges~~ — "5x Infantry" / "Mixed (8 units)" in selection panel
6. ~~Villager auto-retarget~~ — finds nearest same-type resource on depletion
7. ~~Camera bounds~~ — clamped to map edges
8. ~~Better minimap click~~ — click/drag minimap to jump camera
9. ~~Rally point visual~~ — dashed line + circle from building to rally point
10. ~~Speed controls~~ — 0.5x/1x/2x game speed toggle

Additional completed features:
- Resource float numbers (+10 Food on deposit)
- Combat damage float numbers (-5 on hit)
- Building damage smoke/fire effects (<50% / <25% HP)
- Attack-move command for units
- Stand ground stance (no chase)
- Kill tracking and full game-over stats (units killed/lost/trained, resources gathered, buildings built)
- Main menu with difficulty selector
- Game over → main menu flow
- AI attack-move, distributed defense, scouting
- Minimap camera viewport rectangle
- Smart drop-off building selection (lumber camp for wood, etc.)
- Farms as renewable food sources
- Cancel queue buttons
- Keyboard shortcut tooltips on all buttons
- Terrain visual distinction (forest/berry/gold tile textures + minimap colors)
- Resource node glow effects and increased sizes
- Grass tile variety (3 variants for visual interest)
- Fog of war delta-based updates (only changed cells, not full grid)
- Auto-attack throttle (0.3s cooldown on O(n²) enemy scanning)
- Building placement invalid reason text (Out of bounds, Blocked, Overlaps)
- AI difficulty resource bonus (passive income + starting bonus on Medium/Hard)
- Minimap sacred site indicator (purple dot, fog-aware)
- Sacred site hints at 3min game time
- Unit stuck detection (fallback to direct move after 1.5s)
- Damage flash changed to white (visible on both ally and enemy units)
- Villager gather spread (random offset prevents stacking)
- Tighter specialty dropoff preference (lumber camp/mining camp)
- Towers target enemy buildings when no enemy units in range
- Enemy building red tint for team identification
- AI age-up notification ("Enemy advancing to Feudal Age!")
- Stance display in unit selection panel ([Aggressive]/[Stand Ground])
- Arrow projectile VFX for ranged attacks (arced trajectory)
- Counter bonus floating text ("x1.5!" on type advantage)
- Critical HP pulsing red ring (< 25% HP warning)
- Pause menu overlay (Resume / Quit to Main Menu)
- Villager flee to safety when attacked (prefer Town Center)
- Speed button sync (keyboard +/- updates HUD button text)
- Population cap approaching/reached warnings
- Larger minimap (200px for better readability)
- Villager task breakdown on HUD (F:2 W:1 G:1 B:0)
- Wheelbarrow research (+25% gather rate) and Loom (+15 villager HP)
- New units inherit researched attack/armor upgrades on spawn
- HP bar color coding (green >60%, yellow 30-60%, red <30%)
- Colored villager task labels (resource-matched colors: red F, green W, gold G)
- Enemy score comparison display (Score: X / Y)
- Dedicated attack-move VFX indicator (orange/red, distinct from green move)

---

## What's Done vs What's Left (as of Iteration 47)

### Prototype Status: ~90% Complete for Skirmish Mode

The single-player skirmish experience is very close to "basically done." All core systems work: gathering, building, training, combat, aging up, fog of war, AI opponent, win conditions (landmark + sacred site), research upgrades, and comprehensive HUD/UI.

### Remaining Phase 2 Items (Nice-to-Have for Prototype)
- [ ] Collision avoidance between friendly units (steering behaviors)
- [ ] Patrol command
- [ ] Villagers show carry animation
- [ ] Building queue (queue multiple buildings for placement)
- [ ] Building upgrades (Town Center → Castle in Age 3)
- [ ] Gates and walls (Age 2+)
- [ ] Garrison mechanic (units enter buildings)
- [ ] Healing: monks/healers unit type
- [ ] Trade routes between markets
- [ ] Relics on sacred sites

### Suggested Next Iterations (Priority Order)
1. **Patrol command** — simple to implement, standard RTS feature
2. **Collision avoidance** — units stack on each other, most visible remaining issue
3. **Building upgrades** — TC → Castle makes age progression feel complete
4. **Garrison mechanic** — adds defensive depth
5. **Balance pass** — playtest a full game start-to-finish, tune gather rates / AI timing / unit costs
6. **Touch controls polish** — pinch-to-zoom, long-press context menu for mobile
