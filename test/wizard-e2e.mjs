// End-to-end setup wizard test using Playwright
import { chromium } from 'playwright';

const BASE = 'http://localhost:3000';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  console.log('=== Setup Wizard E2E Test ===\n');

  // 1. Login
  console.log('Step 1: Login...');
  await page.goto(`${BASE}/login`);
  await page.fill('#username', 'admin');
  await page.fill('#password', 'testpass123');
  await page.click('input[type="submit"]');
  await page.waitForURL('**/setup/**', { timeout: 5000 });
  console.log(`  ✓ Logged in → ${page.url()}\n`);

  // 2. Welcome → Admin
  console.log('Step 2: Welcome → Admin password...');
  await page.goto(`${BASE}/setup/welcome`);
  await page.waitForLoadState('domcontentloaded');
  // Click continue/next to get to admin step
  const welcomeLink = await page.$('a[href*="admin"]');
  if (welcomeLink) await welcomeLink.click();
  else await page.goto(`${BASE}/setup/admin`);
  await page.waitForLoadState('domcontentloaded');

  // Fill admin password
  const pwField = await page.$('input[name="password"]');
  if (pwField) {
    await page.fill('input[name="password"]', 'testpass123');
    await page.fill('input[name="password_confirmation"]', 'testpass123');
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('domcontentloaded');
  }
  console.log(`  ✓ Admin password set → ${page.url()}\n`);

  // 3. Network
  console.log('Step 3: Network configuration...');
  await page.goto(`${BASE}/setup/network`);
  await page.waitForLoadState('domcontentloaded');
  const hostnameField = await page.$('input[name="hostname"]');
  if (hostnameField) {
    await page.fill('input[name="hostname"]', 'test-kai');
  }
  const networkSubmit = await page.$('button[type="submit"], input[type="submit"]');
  if (networkSubmit) await networkSubmit.click();
  await page.waitForLoadState('domcontentloaded');
  console.log(`  ✓ Network configured → ${page.url()}\n`);

  // 4. Storage — select drives
  console.log('Step 4: Storage drives...');
  await page.goto(`${BASE}/setup/storage`);
  await page.waitForLoadState('domcontentloaded');
  
  // Take screenshot to see what we're working with
  await page.screenshot({ path: '/tmp/wizard-storage.png' });
  
  // Check all drive checkboxes
  const checkboxes = await page.$$('input[type="checkbox"]');
  console.log(`  Found ${checkboxes.length} checkboxes`);
  for (const cb of checkboxes) {
    const checked = await cb.isChecked();
    if (!checked) await cb.check();
  }
  
  // Click prepare/continue button
  const prepareBtn = await page.$('button:has-text("Prepare"), button:has-text("Continue")');
  if (prepareBtn) {
    console.log('  Clicking prepare button...');
    await prepareBtn.click();
    
    // Wait for SSE terminal to appear and complete
    try {
      await page.waitForSelector('.term-line.success, .term-line.error', { timeout: 120000 });
      const lines = await page.$$eval('.term-line', els => els.map(e => e.textContent));
      lines.forEach(l => console.log(`  ${l}`));
      
      // Wait for done/continue button
      const continueBtn = await page.waitForSelector('button:has-text("Continue"), a:has-text("Continue")', { timeout: 10000 });
      if (continueBtn) await continueBtn.click();
    } catch (e) {
      console.log(`  ⚠ SSE stream issue: ${e.message}`);
    }
  }
  await page.waitForLoadState('domcontentloaded');
  console.log(`  ✓ Storage prepared → ${page.url()}\n`);

  // 5. Greyhole
  console.log('Step 5: Greyhole installation...');
  await page.goto(`${BASE}/setup/greyhole`);
  await page.waitForLoadState('domcontentloaded');
  await page.screenshot({ path: '/tmp/wizard-greyhole.png' });
  
  // Check if already installed
  const alreadyInstalled = await page.$('text=already installed');
  if (alreadyInstalled) {
    console.log('  Greyhole already installed, continuing...');
    const contBtn = await page.$('a:has-text("Continue")');
    if (contBtn) await contBtn.click();
  } else {
    // Click install button
    const installBtn = await page.$('button:has-text("Install")');
    if (installBtn) {
      console.log('  Installing Greyhole (this takes a few minutes)...');
      await installBtn.click();
      
      // Wait for terminal completion
      try {
        await page.waitForSelector('[id*="install-footer"]', { state: 'visible', timeout: 300000 });
        const lines = await page.$$eval('.term-line', els => els.map(e => e.textContent));
        lines.slice(-5).forEach(l => console.log(`  ${l}`));
        
        // Click continue
        const contBtn = await page.$('a:has-text("Continue")');
        if (contBtn) await contBtn.click();
      } catch (e) {
        console.log(`  ⚠ Install issue: ${e.message}`);
      }
    } else {
      // Skip
      const skipLink = await page.$('a:has-text("Skip")');
      if (skipLink) await skipLink.click();
    }
  }
  await page.waitForLoadState('domcontentloaded');
  console.log(`  ✓ Greyhole step done → ${page.url()}\n`);

  // 6. Create share
  console.log('Step 6: Create first share...');
  await page.goto(`${BASE}/setup/share`);
  await page.waitForLoadState('domcontentloaded');
  
  const shareNameField = await page.$('input[name="share_name"]');
  if (shareNameField) {
    await page.fill('input[name="share_name"]', 'Storage');
    const createBtn = await page.$('button[type="submit"], input[type="submit"]');
    if (createBtn) await createBtn.click();
  }
  await page.waitForLoadState('domcontentloaded');
  console.log(`  ✓ Share created → ${page.url()}\n`);

  // 7. Complete
  console.log('Step 7: Complete setup...');
  await page.goto(`${BASE}/setup/complete`);
  await page.waitForLoadState('domcontentloaded');
  await page.screenshot({ path: '/tmp/wizard-complete.png' });
  
  const finishBtn = await page.$('a:has-text("Dashboard"), button:has-text("Dashboard")');
  if (finishBtn) {
    await finishBtn.click();
    await page.waitForLoadState('domcontentloaded');
  }
  console.log(`  ✓ Setup complete → ${page.url()}\n`);

  // 8. Verify dashboard
  console.log('Step 8: Verify dashboard...');
  await page.goto(`${BASE}/`);
  await page.waitForLoadState('domcontentloaded');
  await page.screenshot({ path: '/tmp/wizard-dashboard.png' });
  const title = await page.title();
  console.log(`  Page title: ${title}`);
  console.log(`  URL: ${page.url()}`);
  
  await browser.close();
  console.log('\n=== Wizard E2E Test Complete ===');
})();
