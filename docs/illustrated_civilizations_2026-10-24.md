# A gentler little world — beta6

The owner requested a bounded redesign of every civilization asset to match the landscape: soft color, rounded silhouettes, painterly texture and restrained detail. This release replaces the glossy miniature presentation with 18 unit illustrations, 30 building illustrations, three native vector crests, a painted menu/welcome scene and a softer app icon.

## Identity and balance

| Stable ID | Display identity | Art direction |
| --- | --- | --- |
| 0 / crownlands | French | Warm limestone, muted blue slate, coifs and padded coats, simple fleur-de-lis |
| 1 / verdant | English | Cream plaster, timber, ochre thatch, madder cloth, yew longbows, rose |
| 2 / sunstride | Mongols | Ivory felt gers, sage deel robes, ochre ties, stocky ponies, horsehair standard |

These are stylized historical inspirations, not a reconstruction of one precise date. The Mongol farm is a cultivated frontier grain plot; it preserves the game's existing food-building role. Everyday equipment and architectural silhouettes carry identity without ornate fantasy fittings.

Numeric civilization IDs and all bonuses are retained: French occupy the balanced original slot; English retain wood gathering and Longbow tradeoffs; Mongols retain food gathering, Outrider and building-HP tradeoffs. Unit/building costs, collisions, damage, speed, windup, gathering, maps, AI and victory rules are unchanged. Network protocol 4 and map catalog 3 remain unchanged.

## Shared assets and movement

The existing KingdomArt catalog feeds battlefield sprites, HUD portraits, recruitment cards, construction cards and placement ghosts. New atlas regions retain bottom/ground anchors and aspect ratio. The worker sprite has empty hands so the runtime can supply an axe, hoe, pick or hammer. Feet stay planted during work; tool rotation and compression track the body's pose. Walking, melee, bows, riders and siege recoil are restrained to suit the larger illustrated shapes. Accessibility settings remain honored. These are procedural poses, not frame-by-frame animation sheets.

Assets were produced with the built-in image_gen tool using the game's landscape as a style reference. Generation prompts are retained in `docs/illustrated_civilizations_prompts_2026-10-24.json`. Original generated pixels/alpha are preserved in the six sheets and hero. Reviewed alpha bounds and source hashes are recorded in `assets/kingdoms/atlas_layout.json`; `tools/prepare_kingdom_atlases.py` reproducibly writes all 48 texture resources and the manifest.

## Verification and publication

Verified implementation checkpoint, publication pending:

- Clean Godot 4.6 import.
- Fifteen distinct focused regression cases passed across the initial and affected-case runs: all 48 catalog sprites (1,178 checks), unit actions (402), civilization rules/menu, phone menu/reflow, combat damage/timing, gathering/dropoff, AI economic investment, Sacred state machine, online unit/building replicas, recruitment and selection geometry (848).
- The initial production test exposed tall portrait icons expanding the 80px dock to 94px. Recruitment now fits icons in both axes. The final production test passes eight screen/scale profiles; the four affected final suites all pass. This is a presentation fix, not a queue or economy change.
- 26 Web shell/export-wrapper tests passed.
- 27 native GL-compatibility phone captures passed at 844×390 and 932×430, covering each civilization on actual terrain, work/combat phases, recruitment, construction previews and building cards. All 48 sprites and ten action rows were also reviewed in native rendered galleries.
- A military fixture now explicitly selects baseline civilizations before asserting baseline cavalry HP; previously saved preferences contaminated that test. Attack logic was not changed.

The art review corrected overlapping atlas rows and strengthened the initially faded English/Mongol unit rendering. No final crop contains a neighboring sprite. No gameplay balance values changed. Matching Web/server build, service restart and public-browser receipts will follow below.

![All 48 illustrated sprites](images/beta6-illustrated-catalog.png)

![English recruitment at 932×430](images/beta6-english-recruitment.png)

![Mongol construction at 844×390](images/beta6-mongol-construction.png)
 `tools/capture_illustrated_civilizations.tscn` captures the actual main scene, terrain, unit/building resources, recruitment HUD and placement preview at 844×390 and 932×430. Its staged/frozen actors are visual evidence, not a paid-gameplay or physical-device performance claim.

Scope is deliberately bounded to this presentation pass. The known late idle-browser WebGL error, physical-phone performance and full-match pacing remain separate follow-ups.
