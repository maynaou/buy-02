import { expect, test } from '@playwright/test';

test('a seller can register, log in, and create a product', async ({ page }) => {
  const username = process.env['E2E_USERNAME'] ?? `seller${Date.now()}`;
  const email = `${username}@example.test`;
  const password = 'password123';
  const productName = process.env['E2E_PRODUCT_NAME'] ?? `E2E Product ${Date.now()}`;
  const gatewayPort = process.env['E2E_GATEWAY_PORT'] ?? '8888';

  await page.route('https://localhost:8888/**', (route) => {
    const url = new URL(route.request().url());
    url.port = gatewayPort;
    return route.continue({ url: url.toString() });
  });

  await page.goto('/register');
  await page.getByLabel('Username').fill(username);
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByLabel('Account type').selectOption('SELLER');

  const registrationResponse = page.waitForResponse((response) =>
    response.request().method() === 'POST' &&
    new URL(response.url()).pathname === '/api/auth/register'
  );
  await page.getByRole('button', { name: 'Register' }).click();
  expect((await registrationResponse).status()).toBe(201);
  await expect(page).toHaveURL(/\/login$/);

  await page.getByLabel('Username or Email').fill(username);
  await page.getByLabel('Password').fill(password);

  const loginResponse = page.waitForResponse((response) =>
    response.request().method() === 'POST' &&
    new URL(response.url()).pathname === '/api/auth/login'
  );
  await page.getByRole('button', { name: 'Login' }).click();
  expect((await loginResponse).status()).toBe(200);
  await expect(page).toHaveURL(/\/$/);

  await page.goto('/dashboard');
  await page.getByRole('button', { name: 'New product' }).click();
  await page.getByLabel('Name').fill(productName);
  await page.getByLabel('Description').fill('A simple product for the E2E test.');
  await page.getByLabel('Category').selectOption('TRAINING');
  await page.getByLabel('Price').fill('29.99');
  await page.getByLabel('Quantity').fill('12');

  const productResponse = page.waitForResponse((response) =>
    response.request().method() === 'POST' &&
    new URL(response.url()).pathname === '/api/products/product'
  ).then((response) => response.status());
  await page.getByRole('button', { name: 'Create product' }).click();
  expect(await productResponse).toBe(201);
  await expect(page.locator('.row__name', { hasText: productName })).toBeVisible();
});
