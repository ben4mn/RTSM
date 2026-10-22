# Pocket Kingdoms — a company worth commanding

The visual direction starts with the Builder, Warrior and Archer: practical people with recognisable equipment, expressions and roles. The route mark on the Warrior’s shield also appears in the app identity. Mineral teal identifies the home company; clay distinguishes its opponent; bone and charcoal carry the interface. This is an original cast, not borrowed game artwork.

## Research and design decisions

- [Clash Royale](https://supercell.com/en/games/clashroyale/) places its recognisable characters at the centre of its identity. Our inference: give the player a company they can recognise before asking them to read settings. We use our own illustration, silhouettes and equipment.
- [The Battle of Polytopia](https://polytopia.io/) demonstrates a coherent, readable visual world at small scale. Our inference: keep the terrain and unit vocabulary consistent, with clear silhouettes and limited team colours.
- [Bad North’s official press kit](https://www.badnorth.com/press-kit) describes real-time tactics, positioning and individually simulated troops in a restrained visual world. Our inference: let routes, formations and impact feedback explain battles without permanently covering every unit with bright markers.
- [Art of War 3](https://aow3.gear-games.com/?l=en) is a relevant mobile RTS reference for direct unit control. Our inference: keep command feedback immediate and management actions reachable in the landscape phone layout.

These are design references, not evidence that Pocket Kingdoms has achieved their commercial polish or balance. No third-party game assets were copied.

## Implemented visual system

The menu combines an original transparent character illustration with an atlas derived from the selected seed and map. The compact wordmark uses Barlow Condensed, with Barlow for controls and readable detail. Their OFL licences ship with the web release. Character equipment is echoed by the in-game unit silhouettes and command glyphs.

Custom SVG command plates use nine-slice textures, cut corners, an inset keyline and separate hover, pressed, disabled and focus states. A bone primary plate, mineral active state and quiet charcoal secondary controls establish hierarchy. Original equipment-based icons replace the old line-symbol family. Pressed icons use dark silhouettes for contrast. The same plate artwork and character composition appear on the browser welcome.

Farm materials share the restrained palette; the other existing building sprites remain unchanged. Settings, production, build choices, Pause and results share the typography, spacing and colour rules. Touch hit areas remain at least 48 logical pixels. Interfaces continue to support 844×390 and 932×430, UI scales 1.0–1.15, and simulated safe-area insets. Gameplay markers are quieter, while selection, recent damage, worker jobs and optional clearer-player markers remain visible.

## Evidence and limits

Native menu captures cover both phone sizes, UI scales 1.0 and 1.15, and all three map types. Native touch checks exercise real GUI hit testing, paid training, Repeat, queue refunds, build placement, map selection and menu-to-match transitions. Additional captures inspect Settings, Pause, results and actual rendered battles. Generated evidence is stored under `output/visual-redesign-2026-10-22/`; representative images and exact release checks are recorded in the delivery receipt.

Headless simulation, native desktop phone-size rendering and browser touch emulation answer different questions. None establishes physical iPhone/Android frame rate, heat, battery life or human competitive balance. The new maps and battle scenarios provide a repeatable starting point for that testing.
