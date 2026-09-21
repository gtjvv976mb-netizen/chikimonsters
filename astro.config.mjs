import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

// Swap `site` for the domain you register. It feeds the sitemap and canonical URLs.
export default defineConfig({
  site: 'https://flossify.ph',
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
});
