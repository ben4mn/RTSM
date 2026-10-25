# Small sounds, clearer choices — beta7

This pass builds on beta6's soft illustrated French, English and Mongol civilizations. It preserves unit costs/stats, action timing, map generation and existing keyboard/touch commands. The owner added readable units behind scenery, one starting Scout for each player, and a normal population ceiling of at least 100. The new default is 100 per player, with smaller options retained. Protocol 5 prevents older clients from silently interpreting that limit as 30; map catalog 3 is unchanged.

## Design

The [reference review](interface_research_2026-10-24.md) records the previous flow's unclear online entry label, competing setup controls, lore-first civilization comparison and dark map cards. Official Clash of Clans and Age of Empires IV screenshots informed contextual grouping, visible costs/progress and overview-before-detail. Polytopia's official guidance informed comparison by play style. All game artwork remains Pocket Kingdoms' own beta6 assets.

Play solo and Play online now state their destinations. Warm paper map cards retain generated tactical layouts, add terrain traits and distinguish town markers by shape as well as color. The setup summary stays visible, rules have an explanation, and population/seed remain under More options. Civilizations share a consistent illustrated-town, strengths and tradeoff comparison.

In battle, cloth-like grouped surfaces and round utility controls reduce the rigid grid appearance. Recruitment progress appears beneath the relevant portrait. Familiar utility actions use icons; unit/building names, costs and status retain text. Settings has a Guide tab with tappable icon explanations, also reachable from the match menu. Construction's Info mode explains a building without purchasing it.

The [original sound recipes and provenance](tactile_audio_2026-10-24.md) document eighteen synthesized banks, quiet wood/cloth impacts and felt-like plucked accents. Frequent events have restrained nonrepeating variations, shared cooldowns, bounded voice pools and priorities. Hidden/offscreen world effects are dropped. Persistent master/world/interface levels and mutes remain available; browser activation, backgrounding and scene changes discard stale cues.

## Requested visibility and opening additions

During the pass, the owner requested readable units behind buildings, trees and other troops, plus a starting Scout for both players. The rendering observer shows a restrained silhouette only through actual overlaps and only for units already in the local player's current vision. It is noninteractive and does not change selection, collision or targets; fog still conceals unseen opponents.

Both solo and authoritative online starts now spawn one Scout per owner through the normal connected-space spawn solver, alongside the existing four villagers. Normal population accounting applies (5/15 at the opening); starting resource banks, building queues and unit costs are unchanged. The guide recognizes a living starting Scout and retains its recruitment fallback if the Scout is lost.

## Population and economy

The [resource and queue calculations](population_economy_2026-10-24.md) budget a 100-population army with 25 workers, the starting Scout and 74 fighters. It requires about 4,880 additional food, 3,970 wood and 60 gold after the opening bank, including nine Houses, fourteen Farms, three Camps and three production buildings. These are arithmetic estimates, not a promised build order or measured human pace.

The normal match limit is now 100, with 20/30/40/60 still selectable. Housing starts at 15 and grows through paid Houses to the selected ceiling. House cards display the actual remaining gain, including the last five slots, and explain when the ceiling is reached. The population explanation separates housing from the match limit. Large-match AI targets at most 30 workers; the existing smaller-match targets are preserved. This is an explicit scaling adjustment, with no increase to gathering rates or unit strength.

## Verification scope

Baseline public-browser screenshots were saved before changes at 844×390. Automated menu layout/reflow, civilization, gameplay, housing, audio and online checks accompany native rendered captures and browser journeys. Final counts, paid simulation outcomes and release identity are recorded at publication below.

Browser viewport checks and native renders do not certify physical phones, browser-specific mobile audio, touch latency, safe areas or prolonged performance. The controlled native audio fixture uses actual gathering/construction/production and active combat, with explicitly staged free armies to exercise a busy mix. Its debug-only capture mode keeps that simulation running offscreen; it is not a foreground lifecycle test, ordinary paid match or balance test. Audio input is unavailable to this agent, so the recording and signal/repetition checks do not constitute subjective listening. Separate lifecycle tests cover foreground/background muting and pause behavior.

## Release checkpoint

Implementation is being saved in focused commits. Publication is pending at this checkpoint. The established release workflow exports one committed revision twice, verifies matching sealed payloads, smoke-tests the matching Linux server, stages without replacing live state, checks active/closing match connections immediately before replacement, retains beta6 rollback bytes and then verifies public HTTPS and active runtime identity.
