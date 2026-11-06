import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

function runtimeConfigPlugin() {
  return {
    name: 'runtime-config',
    configureServer(server) {
      server.middlewares.use('/runtime-config.json', (request, response, next) => {
        if (request.method !== 'GET') {
          next();
          return;
        }

        const backendApiUrl = process.env.VITE_BACKEND_API_URL ?? 'http://staging.localhost:8080';
        try {
          const parsed = new URL(backendApiUrl);
          if (!['http:', 'https:'].includes(parsed.protocol) || parsed.username || parsed.password) {
            throw new Error('invalid backend URL');
          }
          response.statusCode = 200;
          response.setHeader('Cache-Control', 'no-store');
          response.setHeader('Content-Type', 'application/json; charset=utf-8');
          response.end(JSON.stringify({ backendApiUrl: parsed.origin }));
        } catch {
          response.statusCode = 500;
          response.end('invalid VITE_BACKEND_API_URL\n');
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [vue(), runtimeConfigPlugin()],
});
