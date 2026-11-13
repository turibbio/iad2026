const { defineConfig } = require('@playwright/test');
const path = require('node:path');
module.exports = defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  workers: 1,
  retries: 0,
  use: { baseURL: 'http://127.0.0.1:5089', trace: 'retain-on-failure' },
  outputDir: '../../artifacts/browser-results',
  reporter: [['list'], ['junit', { outputFile: '../../artifacts/test-results/browser.xml' }]],
  webServer: {
    command: 'dotnet run --project src/Orders.Web -c Release --no-build --no-launch-profile --urls http://127.0.0.1:5089',
    cwd: path.resolve(__dirname, '../..'),
    url: 'http://127.0.0.1:5089',
    reuseExistingServer: false,
    env: { ASPNETCORE_ENVIRONMENT: 'Development' }
  }
});
