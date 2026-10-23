# Construction information — 22 October 2026

Native baseline inspection of locked Town Center Info said “Tap to preview” despite an age lock. Hover also retained its original generic text after resource changes, whereas accessibility text partially refreshed.

Build cards now name the required age. Hover, accessible text and tap/hold Info share the current status: locked age, exact resource deficit, or ready. Info only offers placement instructions when currently available; tap-Info mode explains returning to building. The Place/Cancel payment rule remains explicit. Existing palette filtering, price data, touch targets and placement code are unchanged.

The extended `test_build_menu_age_ownership` passes human/AI age isolation, age-up/shortage/recovery updates, matching hover/accessibility, and truthful Info actions. Root replayed native Info at701×324: the close target stays visible and the longer body scrolls. Captures in `output/polish-2026-10-22/{before,after}-locked-info.png` differ in viewport size, so are behavior evidence rather than a pixel-aligned comparison.
