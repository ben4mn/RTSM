# Beta9.1 startup, controls and placement follow-up

Candidate for the reported immediate "Game reported an error" notice. Public acceptance will be recorded after publication.

Two recent anonymous beta9 records from Safari/iOS standalone windows contain paired `Importing a module script failed.` rejections at 1.39–1.44 seconds, after Godot session initialization. Loaded and served source identities both match `e6735a63b536`. The only module imports in the unchanged engine are its two AudioWorklet processors. Neither a ResizeObserver nor a WebGL error appears in those records. No corresponding worklet request reached the origin at those times. The exact WebKit/cache failure is not directly observable in the saved records; the fix targets the failing module transport without suppressing the error notice.

The page fetches both stock worklets through its own release-bound cache and verifies SHA-256 values embedded during packaging. It passes those bytes to the native AudioWorklet loader as JavaScript Blob URLs. Only the two exact game module URLs are redirected; native receiver/options and rejection behavior are retained. Blobs survive later audio contexts and back-forward restoration, and are released on final page departure. Failed preparation remains a visible startup failure; actual import failures still reach the existing recovery notice. No engine binary, processor source or browser security policy changes.

The menu's Solo and Online glyphs now use a pennant and paired kingdoms. The browser-owned What's new/Full screen buttons reserve space beside Settings and align with its actual bounds, accounting for Godot interface scaling and browser pixels. Fullscreen stays inside its real browser click handler. Leaving the menu restores the pause toolbar's safe-area fallback.

Battlefield setup starts with a single selected-map preview and disclosure arrow. Opening it reveals the existing choices; selection closes it, and online guest/host permissions remain intact. Camera/navigation tools above the minimap start collapsed behind one View control. Existing actions remain available inside that tray.

Validation includes byte/hash/loading failure cases, retained real exceptions, native module arguments and Blob lifetime, package reproducibility/closure, native menu layout, and exported browser startup/menu/settings/resize checks. Physical Safari acceptance remains separately identified; Chrome or viewport tests are not a substitute for an iOS device.

## Movement and map scope

Panning/pinching clears the previous tap sequence. A touch can retain its visible unit target from finger-down, with ownership/liveness/visibility revalidation at release; panning cancels that target. Selected-unit reselection uses the same visible silhouette rule. A newly requested route skips only its redundant starting-cell center when the next segment passes the existing navigation clearance test. Recovered escape waypoints, later turns, endpoints, costs, movement speed and attack timing remain unchanged.

The opening grove and two guaranteed side expansions each grow from eight to twelve 200-food bushes. Per player this is 7,200 guaranteed food instead of 4,800 (+2,400), with equal mirrored placement, existing routes and five-by-five expansion pads preserved. Random/contested deposits and harvesting rates are unchanged. This deterministic terrain change advances generator/catalog to4 and online protocol to7; old clients must reload so both sides simulate the same resources.

Placement now draws above world objects and below fog, using canonical map projection. The actual occupied footprint has one boundary; blocked terrain and the one-tile owned-building access clearance have different marks. The validation and payment rules are unchanged.

## Worker order Undo

An accepted deliberate Move/Gather/Build involving at least two eligible Villagers saves one previous-intent record per player for ten real-time seconds. The temporary Undo control restores ordinary work/move/idle orders for surviving workers, with current target availability and visibility checks. Invalid former work stops safely and reports why; cargo, banked resources, construction progress, health, position and combat are never rewound. A subsequent deliberate worker order supersedes the record. Automatic gathering/delivery progress does not erase it. Time continues to expire while Solo is paused.

Online authority keeps the record and validates its per-player identifier; clients receive only availability/count/lifetime and submit that identifier. They cannot supply previous jobs or another player's record. The protocol7 release also binds these new snapshot/command fields.
