import { defineConfig,devices } from '@playwright/test';
export default defineConfig({
 testDir:'./tests/integration',workers:1,retries:0,timeout:90000,reporter:'list',
 use:{baseURL:'http://127.0.0.1:3100',trace:'retain-on-failure'},
 projects:[{name:'authenticated-chromium',use:{...devices['Desktop Chrome']}}],
 webServer:{command:'npm run start -- --port 3100',url:'http://127.0.0.1:3100',timeout:120000,reuseExistingServer:false}
});
