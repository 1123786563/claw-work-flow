const { chromium } = require('playwright');

(async () => {
    const url = process.argv[2] || 'http://localhost:3000';
    const screenshotPath = process.argv[3] || 'screenshot.png';

    const browser = await chromium.launch();
    const page = await browser.newPage();
    
    try {
        console.log(`正在访问 ${url}...`);
        await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
        await page.screenshot({ path: screenshotPath, fullPage: true });
        console.log(`✅ 截图已保存至 ${screenshotPath}`);
    } catch (e) {
        console.error(`❌ 截图失败: ${e.message}`);
        process.exit(1);
    } finally {
        await browser.close();
    }
})();
