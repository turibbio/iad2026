const { test, expect } = require('@playwright/test');

test('Interactive Server applies a discount and rejects invalid inputs', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByTestId('total')).toContainText('100,00');
  await page.getByLabel('Codice sconto').fill('SAVE20');
  await page.getByLabel('Percentuale').fill('20');
  await page.getByRole('button', { name: 'Applica', exact: true }).click();
  await expect(page.getByRole('status')).toHaveText('Sconto applicato.');
  await expect(page.getByTestId('total')).toContainText('80,00');
  await page.screenshot({ path: '../../artifacts/discount-applied.png', fullPage: true });
  await page.getByLabel('Percentuale').fill('31');
  await page.getByRole('button', { name: 'Applica', exact: true }).click();
  await expect(page.getByText('Lo sconto deve essere tra 0 e 30%.')).toBeVisible();
  await expect(page.getByTestId('total')).toContainText('80,00');
  await expect(page.getByRole('status')).toHaveCount(0);
  await page.getByLabel('Codice sconto').fill('');
  await page.getByLabel('Percentuale').fill('20');
  await page.getByRole('button', { name: 'Applica', exact: true }).click();
  await expect(page.getByText('Il codice è obbligatorio.')).toBeVisible();
  await expect(page.getByTestId('total')).toContainText('80,00');
});

test('A new circuit starts with an independent order', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByTestId('total')).toContainText('100,00');
});

test('Prerendered form waits for an interactive circuit', async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto('/');
  await expect(page.getByTestId('total')).toContainText('100,00');
  await expect(page.getByLabel('Codice sconto')).toBeDisabled();
  await expect(page.getByLabel('Percentuale')).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Applica', exact: true })).toBeDisabled();
  await context.close();
});
