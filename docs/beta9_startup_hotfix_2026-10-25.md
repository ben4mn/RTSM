# Beta9.1 startup and menu hotfix

Candidate for the reported immediate "Game reported an error" notice. Public acceptance will be recorded after publication.

Two recent anonymous beta9 records from Safari/iOS standalone windows contain paired `Importing a module script failed.` rejections at 1.39–1.44 seconds, after Godot session initialization. Loaded and served source identities both match `e6735a63b536`. The only module imports in the unchanged engine are its two AudioWorklet processors. Neither a ResizeObserver nor a WebGL error appears in those records. No corresponding worklet request reached the origin at those times. The exact WebKit/cache failure is not directly observable in the saved records; the fix targets the failing module transport without suppressing the error notice.

The page fetches both stock worklets through its own release-bound cache and verifies SHA-256 values embedded during packaging. It passes those bytes to the native AudioWorklet loader as JavaScript Blob URLs. Only the two exact game module URLs are redirected; native receiver/options and rejection behavior are retained. Blobs survive later audio contexts and back-forward restoration, and are released on final page departure. Failed preparation remains a visible startup failure; actual import failures still reach the existing recovery notice. No engine binary, processor source, browser security policy or multiplayer protocol changes.

The menu's Solo and Online glyphs now use a pennant and paired kingdoms. The browser-owned What's new/Full screen buttons reserve space beside Settings and align with its actual bounds, accounting for Godot interface scaling and browser pixels. Fullscreen stays inside its real browser click handler. Leaving the menu restores the pause toolbar's safe-area fallback.

Validation includes byte/hash/loading failure cases, retained real exceptions, native module arguments and Blob lifetime, package reproducibility/closure, native menu layout, and exported browser startup/menu/settings/resize checks. Physical Safari acceptance remains separately identified; Chrome or viewport tests are not a substitute for an iOS device.
