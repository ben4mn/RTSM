# Keep your kingdom moving — beta8

This focused follow-up addresses the owner's request for Age of Empires II/IV sound references and responsive play across economy, scouting and combat. It retains beta7's illustrated interface, starting Scouts, occlusion silhouettes and 100-population default.

## Sound and useful actions

The [primary-source sound review](aoe_sound_reference_2026-10-24.md) distinguishes documented behavior from material merely located for human listening. AoE II's publisher notes support distinct successful/failed actions and restrained repeated acknowledgments. AoE IV's lead music designer describes coherent state transitions and controlled density. These principles fit Pocket Kingdoms' quiet tactical feedback; no proprietary sounds or recordings were copied.

The attack warning now uses an original 430 ms, two-pulse wood/reed texture instead of the same felt-like instrument and opening pitch as a Move order. Its volume, six-second cooldown, priority, ownership routing and browser lifecycle are unchanged. Nine real-Main damage-routing checks and the PCM/scheduler regression passed. A fresh native gameplay-mix capture contains paid recruitment/construction and a staged 12-versus-12 battle: 143 landed hits produced 48 impact cues over 24.697 seconds, with two warnings, at most two voices and no clipping or capture drops. This is event/signal evidence; audio input is unavailable, so subjective listening or perceived similarity to AoE is not certified.

Useful APM means directing troops, scouting, managing production and responding between fronts. The pass does not reward empty clicks, accelerate the game clock or change costs, attack intervals or networking. Base/Economy/Army navigation, two saved groups, keyboard shortcuts and remote recruitment remain available.

## Performance and AI review

Repeated icon decoration was identified as synchronous work during selection changes. The bounded fix reuses unchanged final decoration while refreshing dynamic labels, badges, availability and selection state. A second guard avoids rebuilding hidden construction cards when the guided recommendation is unchanged; resource, age, population and menu-open paths still refresh availability. In the same alternating-selection fixture, unit selection fell from a combined baseline range of 65–147ms to 2.3–4.9ms, and Town Center selection to 12.9–17.3ms. The final synchronous sample ran alongside an AI simulation, so it is not a controlled FPS comparison. The 152-check interaction fixture covers real engine ScreenTouch and keyboard inputs, two active combat fronts, persistent orders, ongoing worker jobs and three paid worker queues per viewport profile.

Quiet native staged-combat measurements of the icon-cache change alone reduced 200-actor frame p95 from 140.75 to 124.02ms and median from 22.11 to 20.45ms. The 50-versus-50 test p95 fell from 79.02 to 43.97ms. Both fixtures lose actors during 20-second samples; they do not hold 200 live actors throughout. All 24 measured touches were accepted on the next observed frame, but the worst 200-actor response still reached 175ms. The later construction-card guard was measured synchronously, not given a new uncontended FPS claim. See [responsiveness evidence](multifront_responsiveness_2026-10-24.md) for exact scopes. Physical-phone performance remains untested.

Three complete beta7 ordinary-cost 100-population simulations across all maps/civilizations are [retained as historical evidence](beta7_paid_rounds_2026-10-24.md). They reached natural Sacred victories in 380.92–573.67 game seconds, with paid housing above 30 and peak committed population up to 86. They were automated fixed-60 Hz, supported-3× policy runs, not human play or rendered performance benchmarks. Separate paid housing tests reach the exact 100 ceiling.

Those traces exposed a larger-match AI issue: fixed small Sacred contest squads could suppress ordinary field offense while a larger army waited. The follow-up changes tactical commitment only for Medium/Hard at population limits of at least 80. A contested site receives roughly three quarters of living fighters, subject to the existing home reserve; the existing field-wave mechanism can use surplus. An urgent hostile retained victory clock recalls the full force. Home defense retains precedence. Objective, reserve and field-wave membership must remain disjoint, and recalls must not restart movement/combat every decision tick. Easy, smaller matches, economy targets, map geometry and resource stocks are preserved.

The map audit found usable authored center/flank paths and expansion sites. Current AI traces mostly use the central objective; they do not prove that changing map size would improve strategy. Flank routing and late-game economy/age diversity remain evidence-led follow-ups rather than speculative balance changes in this release.

The [AI/map audit](large_army_strategy_2026-10-24.md) records the concrete route calculations, existing workforce targets and focused lifecycle results.

## Release and limitations

Publication and final measured verification are recorded after the exact committed candidate passes its release checks. The existing workflow produces two reproducible Web exports and a matching Linux authority, tests a disposable server, checks active connections immediately before replacement and retains rollback bytes/image/context. Protocol remains 5 and map catalog remains 3.

No physical device or human audio listening pass was available. Native mouse/engine-touch tests and Windows browser viewports have separate scopes. Large staged battle frame spikes remain a performance concern; reduced interface work alone is not proof that 200-actor mobile battles are smooth. The existing narrow connection-admission race in the restart guard and late idle-browser WebGL issue remain documented limitations.
