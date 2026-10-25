# Small sounds, clearer choices — beta7

This bounded pass builds on beta6's soft illustrated French, English and Mongol civilizations. It changes sound and interface presentation, without changing balance, action timing, map generation, network protocol 4 or the existing keyboard/touch command bindings.

## Design

The [reference review](interface_research_2026-10-24.md) records the previous flow's unclear online entry label, competing setup controls, lore-first civilization comparison and dark map cards. Official Clash of Clans and Age of Empires IV screenshots informed contextual grouping, visible costs/progress and overview-before-detail. Polytopia's official guidance informed comparison by play style. All game artwork remains Pocket Kingdoms' own beta6 assets.

Play solo and Play online now state their destinations. Warm paper map cards retain generated tactical layouts, add terrain traits and distinguish town markers by shape as well as color. The setup summary stays visible, rules have an explanation, and population/seed remain under More options. Civilizations share a consistent illustrated-town, strengths and tradeoff comparison.

In battle, cloth-like grouped surfaces and round utility controls reduce the rigid grid appearance. Recruitment progress appears beneath the relevant portrait. Costs, availability labels and contextual action names remain. A tap-access field guide explains icons, and construction's Info mode explains a building without purchasing it.

The [original sound recipes and provenance](tactile_audio_2026-10-24.md) document eighteen synthesized banks, quiet wood/cloth impacts and felt-like plucked accents. Frequent events have restrained nonrepeating variations, shared cooldowns, bounded voice pools and priorities. Hidden/offscreen world effects are dropped. Persistent master/world/interface levels and mutes remain available; browser activation, backgrounding and scene changes discard stale cues.

## Verification scope

Baseline public-browser screenshots were saved before changes at 844×390. The menu's phone/layout, mode/reflow and civilization suites pass 2,207, 1,304 and 485 checks respectively. Web shell/export wrapper tests pass 26 cases. Integrated rendered gameplay, focused gameplay regression, audio recording and matching release results are recorded at publication below.

Browser viewport checks and native renders do not certify physical phones, browser-specific mobile audio, touch latency, safe areas or prolonged performance. The native audio fixture uses actual gathering/construction/production and unchanged active combat, with explicitly staged free armies to exercise a busy mix. It is not an ordinary paid match or a balance test. Signal measurements are not a substitute for subjective listening.

## Release checkpoint

Implementation is being saved in focused commits. Publication is pending at this checkpoint. The established release workflow exports one committed revision twice, verifies matching sealed payloads, smoke-tests the matching Linux server, stages without replacing live state, checks active/closing match connections immediately before replacement, retains beta6 rollback bytes and then verifies public HTTPS and active runtime identity.
