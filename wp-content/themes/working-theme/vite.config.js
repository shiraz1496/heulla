import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite';
import laravel from 'laravel-vite-plugin'
import { wordpressPlugin, wordpressThemeJson } from '@roots/vite-plugin';

// Set APP_URL if it doesn't exist for Laravel Vite plugin
if (! process.env.APP_URL) {
  process.env.APP_URL = 'http://example.test';
}

// Host-published port (the port your browser uses). Vite always listens on the
// fixed port 5173 *inside* the container; Docker maps the host port to it.
const hostPort = parseInt(process.env.VITE_PORT || '5173', 10);

export default defineConfig({
  base: '/wp-content/themes/working-theme/public/build/',
  // Bind to all interfaces so the dev server is reachable from the host browser
  // when Vite runs inside the Docker `node` container. `origin` pins the
  // hot-file URL that Blade's @vite directive points the browser at.
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
    cors: true,
    origin: `http://localhost:${hostPort}`,
    hmr: {
      host: 'localhost',
      clientPort: hostPort,
    },
  },
  plugins: [
    tailwindcss(),
    laravel({
      input: [
        'resources/css/app.css',
        'resources/js/app.js',
        'resources/css/editor.css',
        'resources/js/editor.js',
      ],
      refresh: true,
      assets: ['resources/images/**', 'resources/fonts/**'],
    }),

    wordpressPlugin(),

    // Generate the theme.json file in the public/build/assets directory
    // based on the Tailwind config and the theme.json file from base theme folder
    wordpressThemeJson({
      disableTailwindColors: false,
      disableTailwindFonts: false,
      disableTailwindFontSizes: false,
      disableTailwindBorderRadius: false,
    }),
  ],
  resolve: {
    alias: {
      '@scripts': '/resources/js',
      '@styles': '/resources/css',
      '@fonts': '/resources/fonts',
      '@images': '/resources/images',
    },
  },
})
