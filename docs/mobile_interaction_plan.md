# Pocket Kingdoms mobile menu and hold interaction plan

Pocket Kingdoms should expose frequent actions in stable positions and return screen space to the battlefield when secondary controls finish their job. Add optional hold shortcuts after making menu dismissal and touch ownership predictable. Preserve the current character art, medieval theme, command meanings, paid economy, explicit construction confirmation, selection gestures, and simulation speed.

Implement in the sequence below. The first review milestone covers reliable collapse, hold information, and one command shortcut. Expanding world gestures follows only after that milestone proves useful.

## Patterns from complex mobile games

| Official example | Documented interaction | Application to Pocket Kingdoms |
| --- | --- | --- |
| [Company of Heroes controls](https://www.feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios/) | A persistent command panel or a hold command wheel; dragging previews an ability, release chooses, and returning to the center cancels. Panel icons also support hold descriptions. | Keep tap access. Give a small command chooser a preview, release commitment, and neutral cancel region. |
| [ROME battle interface](https://www.feralinteractive.com/en/news/managing-the-battle-ui-in-rome-total-war-for-iphone/) and [Imperium controls](https://feralinteractive.com/en/games/rometw/android-ios/imperium-update/) | Battle UI slides away during path drawing and selection. Later controls include collapsible groups, hold positioning, and configurable automatic deselection. | Collapse secondary chrome during world interaction. Keep selection and current orders independent of menu visibility. |
| [Wild Rift pings](https://support.riotgames.com/en-us/wild-rift/gameplay/pings-in-wild-rift) | Tap provides a quick ping; holding reveals a minimap, dragging targets it, and release commits. Releasing outside cancels. | A hold can offer precision without making everyday taps slower. Always explain how to cancel before release. |
| [Company of Heroes button overlay](https://www.feralinteractive.com/en/news/feature-highlight-button-overlay-in-company-of-heroes-for-iphone-and-android/) | Tap Assist enlarges a button cluster before a second tap confirms; an alternative hold enlarges the button under the finger. | Expand dense production details into a readable surface. Preserve generous ordinary targets rather than relying on magnification to repair small buttons. |

These applications are design proposals. The examples establish useful interaction patterns; their documentation does not determine Pocket Kingdoms' best hold duration or thumb reach. Riot's [2.5 control changes](https://wildrift.leagueoflegends.com/en-us/news/game-updates/wild-rift-patch-notes-2-5/) also describe tuning accidental drags and drag sensitivity, supporting a deliberate device tuning pass.

## What the current code needs first

The existing HUD already contains View, More, a Queue page, and a Build sheet. Their close rules are partly independent. View remains open after Center, Reset, and world orders. More can survive a change between two unit selections. Queue and F2 Help can coexist with other disclosure. See [View](/Users/ben/Documents/1_Projects/aoem/scripts/ui/hud.gd:511), [More](/Users/ben/Documents/1_Projects/aoem/scripts/ui/hud.gd:1156), [selection refresh](/Users/ben/Documents/1_Projects/aoem/scripts/ui/hud.gd:2268), and [Queue](/Users/ben/Documents/1_Projects/aoem/scripts/ui/hud.gd:2939).

World hold already triggers at 350 ms with a 12 pixel movement tolerance. One available action executes at the threshold; multiple actions open a popup. Extend this recognizer rather than installing another global recognizer. Its activation currently accumulates simulation `delta`, whereas its release fallback uses real milliseconds. At 3× game speed, the activation path can reach 350 ms in approximately 117 ms of real time. A drag beyond the hold tolerance followed by a return can also qualify again on release. Use one monotonic clock and latch movement cancellation. See [activation](/Users/ben/Documents/1_Projects/aoem/scripts/managers/selection_manager.gd:149), [release](/Users/ben/Documents/1_Projects/aoem/scripts/managers/selection_manager.gd:324), and [drag cancellation](/Users/ben/Documents/1_Projects/aoem/scripts/managers/selection_manager.gd:370).

Main refreshes selection details every half second. A refresh of HP, cargo, or queue progress must preserve inspection and an in-flight touch. Only changed entity membership, producer identity, or command authority should invalidate that context. See [Main refresh](/Users/ben/Documents/1_Projects/aoem/scripts/main/main.gd:3055).

## Menu visibility and dismissal

Keep resources, objectives, Pause, selected entity identity and HP, frequent commands, visible costs, Repeat state, and queue count accessible. An armed command retains its destination instruction and cancellation. Placement retains its ghost, validity feedback, Place, and Cancel. Collapsing a menu does not deselect units or stop their orders.

Allow one secondary surface at a time. A small HUD coordinator should own View, More, Queue, Info, Help, and the existing world context popup. Build, Pause, age advancement, and results take priority through the existing modal lifecycle. Placement remains a separate world mode.

| Surface | Preserve while | Collapse when |
| --- | --- | --- |
| View | Repeated zoom adjustments | Center or Reset succeeds; world tap or pan starts; selection changes; another surface opens |
| More | Reading available commands | A command is chosen or armed; world interaction starts; selection changes; another surface opens |
| Queue | Canceling/refunding items; production advances; Repeat waits for resources | Train/back is chosen; producer changes; queue becomes empty with Repeat off; world interaction starts |
| Build | Scrolling, changing category, reading costs, affordability changes | A card enters placement; Close/Escape; outside dismissal; modal interruption |
| Info | Reading through the tap alternative | Close/Escape; changed context; another surface; world interaction |
| Hold information | Its owning finger remains held in the allowed area | Release; latched movement cancellation; second contact; invalid context |
| Help | Deliberate reading | Close/Escape; replacement surface; modal interruption |
| World context | Choosing a valid contextual action | Choice; outside dismissal; context invalidation; modal interruption |

Use action-based dismissal rather than an inactivity timer. Queue and Build must remain steady while players read prices, cancel several items, or wait for resources.

For View, More, and Queue, a world-origin tap or pan closes the surface and continues through the existing world dispatcher exactly once. Pause remains reachable in one tap and takes modal priority. Other taps outside Build, Info, Help, or the world popup only dismiss that surface; the entire contact stays UI-owned through release. This prevents closing a blocking panel from issuing a concealed world order. Ordinary world taps retain their established selection and command meanings.

Escape first closes the active secondary surface, then follows the existing placement, armed-command, Area, and selection cancellation order on subsequent presses. When Pause/results close, transient menus stay collapsed.

## Hold information and the first command shortcut

**Hold to inspect:** Train, research, Build, Repeat, and refund controls show full names, effects, costs, requirements, and refund rules. A consumed hold never trains, researches, toggles Repeat, refunds, or enters placement on release. Ordinary short taps keep their current behavior. A labeled Info handle in the selection summary opens the same explanations for players who prefer tapping. A Build Info toggle makes locked and unaffordable cards inspectable by tapping, while preserving their purchase restrictions when inspection ends. Locked and unaffordable items should remain inspectable through a wrapper that owns the contact even if the action button is disabled.

**Hold More:** open a compact fan above the thumb dock, slide to an action, and release. Use the same actions as the normal More menu: Stop, Patrol, Stance, and Idle workers where relevant. Limit the chooser to four choices; keep labels, positions, and action identity fixed throughout a gesture. Display the prospective action above the finger. Return to the center or release outside a valid choice to cancel. Release on Patrol arms the existing destination mode; a separate world tap supplies the destination. Stop and Stance use their existing handlers. A tap on More continues to open the ordinary menu.

Start the new HUD hold prototype at 450 ms, with a small movement tolerance expressed in viewport logical pixels. This is a tuning hypothesis. Keep the existing world hold threshold at 350 ms during the ownership repair. Show a subtle hold-progress cue and a short first-use hint, with the explanation available again in Help. Offer a setting to disable hold shortcuts while retaining tap access.

Use a fan rather than requiring a full circle at the screen edge. Each choice and tap fallback should normally provide at least 48 logical pixels. Clamp the whole chooser inside the safe area before presenting it; freeze its geometry until the gesture ends. Register its actual visible bounds with the camera obstacle provider, as with the existing HUD cards. Opening a hold surface must not automatically move the camera or change zoom. See [obstacle provider](/Users/ben/Documents/1_Projects/aoem/scripts/ui/hud.gd:946).

## Touch ownership and implementation boundaries

Keep world ownership in SelectionManager, camera ownership in GameMap, and placement ownership in BuildingPlacement. Add a reusable HUD hold component for GUI controls, sharing timing and cancellation rules without feeding GUI presses into world input. Coordinate surface requests and dismissal through signals; route command choices through existing Main handlers.

For every new hold, retain the initiating contact ID, initial target/action, selection revision, start time, maximum displacement, and consumed/canceled state. A contact that starts on UI remains owned until release, even if its panel disappears or the finger moves over terrain. A second contact, OS cancellation, focus loss, resize, modal transition, or invalid selection cancels the pending choice. Avoid duplicate synthetic mouse actions. Once consumed or canceled, the original tap cannot execute later.

After the chooser opens, movement selects a choice instead of applying the pre-hold movement tolerance. Highlighting previews only; a valid release commits at most one action. Controls must survive routine reconciliation until input dispatch completes. If a queued item completes, a producer dies, or a selected unit disappears, cancel that control's pending action rather than transferring the hold to a replacement item.

Use the existing paid production, refund, fog legality, and placement paths. Previewing information creates no transaction. The selected action and eventual execution must agree with any armed Move/Attack/Patrol mode; the current world context labels need an audit before being reused.

## Implementation sequence and review gates

1. **Repair hold timing and cancellation.** Unify world activation and release on real time; latch maximum displacement; preserve GUI admission, arbitrary touch IDs, Area, pan, pinch, and placement. Add boundary regressions before changing presentation. Gate: identical hold timing at every game speed and no command after an out-and-back cancellation.
2. **Unify disclosure lifecycle.** Add the surface coordinator and a selection identity revision. Connect View/More/Queue/Help/world popup and modal transitions; apply the dismissal table. Preserve queue scroll and live button identity. Gate: one secondary surface, predictable Escape/outside behavior, and no lost selection or duplicate world action.
3. **Add hold information.** Start with Train and Build cards, then Repeat, research, and refunds. Add the tap Info alternative and support disabled-action explanations. Gate: all previews leave resources and queues unchanged, including release, cancellation, and refresh during a hold.
4. **Prototype hold More.** Use a reusable chooser with the existing handlers and normal tap menu. Tune geometry on the smallest Large-scale phone first. Gate: every choice is reachable, center/outside cancellation is reliable, primary tap paths retain their tap count, and no action occurs before valid release.
5. **Validate and deliver the milestone.** Compare collapsed, expanded, held, armed, and placement states with the current redesign. Run the focused regressions, paid journeys, broader suite, Python checks, boot, and diff check in an isolated validation copy. Produce a separate local Web build and evidence directory. Keep the current preview available for comparison.
6. **Evaluate optional world chooser expansion.** Only after the first milestone, consider replacing the existing multi-action popup with the same touch-sized chooser. Preserve single-action world hold meanings and producer rallies. Decide any change to threshold-time execution separately. Full dock auto-hide, two-finger UI toggles, automatic deselection, and command slowdown are later experiments because they affect existing interaction or gameplay.

## Validation and acceptance

Use real `Input.parse_input_event` dispatch, not direct handler calls alone. Extend the existing [world touch](/Users/ben/Documents/1_Projects/aoem/tools/test_phone_world_touch_dispatch.gd), [hold context](/Users/ben/Documents/1_Projects/aoem/tools/test_touch_long_press_context.gd), [Train input](/Users/ben/Documents/1_Projects/aoem/tools/test_touch_train_button_input.gd), [modal lifecycle](/Users/ben/Documents/1_Projects/aoem/tools/test_camera_modal_touch_lifecycle.gd), and [redesign journey](/Users/ben/Documents/1_Projects/aoem/tools/test_ux_redesign_journey.gd) harnesses.

- Test just below, at, and above the hold threshold; all four game speeds; tolerance boundaries; out-and-back movement; rapid taps; and release outside.
- Exercise arbitrary and reused contact IDs, GUI-consumed releases, mouse emulation, second/third fingers, cancellation, focus loss, resizing, selection changes, death, and affordability/queue refresh during a hold.
- Prove one gesture produces at most one command or transaction. Inspecting paid or refundable controls must produce zero transactions. Touch placement still purchases only through Place.
- Render and interact at 844×390 and 932×430, every UI scale, ordinary/notched safe areas, and overview/default/detail zoom. Cover workers, armies, producers, queues, Build, placement, armed commands, notifications, Help, Pause, and results.
- Recheck Center with every new visible surface. Preserve manual zoom where the selected content fits and keep rings, HP, cargo, and building bounds clear of actual obstacles.
- Complete the existing skirmish, training/building, gathering/drop-off, AI, Sacred Site, and game-over checks. Keep earlier R4 and redesign evidence immutable; use a fresh output path and bind new source/build/evidence identities.

Physical-phone testing determines the final hold duration, dead zone, finger occlusion, reach, and usefulness. The milestone is ready for that review when ordinary actions remain as fast to reach, repeated production/refunds stay stable, cancellations are dependable, and secondary menus reliably clear after battlefield interaction. Simulated touch and screenshots alone cannot establish thumb comfort.

The starting source and review evidence are recorded in [the current redesign report](/Users/ben/Documents/1_Projects/aoem/docs/ux_redesign.md) and [its frozen source manifest](/Users/ben/Documents/1_Projects/aoem/output/evolution/ux-redesign-20261011/final-source-manifest.json). Preserve that dirty checkout when creating implementation or validation copies.
