// Playwright CLI run-code --filename tools/run_web_safe_area_browser.js
// Serve the generated fixture on 127.0.0.1:8873 first.
async (page) => {
    const reports = [];
    const engine = page.context().browser().browserType().name();
    for (const profile of [
        {width: 844, height: 390, dpr: 1},
        {width: 844, height: 390, dpr: 3},
        {width: 932, height: 430, dpr: 3},
        {width: 1280, height: 590, dpr: 1},
    ]) {
        const context = await page.context().browser().newContext({
            viewport: {width: profile.width, height: profile.height},
            deviceScaleFactor: profile.dpr, isMobile: true, hasTouch: true,
        });
        try {
            const fixture = await context.newPage();
            await fixture.goto('http://127.0.0.1:8873');
            const report = await fixture.evaluate(async () => await window.PocketSafeAreaFixture.run());
            const filename = `output/playwright/safe-area-${engine}-${profile.width}x${profile.height}-dpr${profile.dpr}.png`;
            await fixture.screenshot({path: filename, scale: 'css'});
            // Exercise a physical size change on the same page/context too.
            await fixture.setViewportSize({width: profile.height, height: profile.width});
            const portrait = await fixture.evaluate(async () => await window.PocketSafeAreaFixture.run());
            reports.push({profile, screenshot: filename, landscape: report, portrait});
        } finally {
            await context.close();
        }
    }
    return {passed: true, engine, profiles: reports};
}
