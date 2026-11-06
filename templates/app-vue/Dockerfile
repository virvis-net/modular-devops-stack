FROM node:22-alpine AS frontend-build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runtime

ENV NODE_ENV=production \
    PORT=8080 \
    METRICS_PORT=9090
WORKDIR /app
COPY --from=frontend-build --chown=node:node /app/dist ./dist
COPY --chown=node:node server.mjs ./server.mjs
USER node
EXPOSE 8080 9090
CMD ["node", "server.mjs"]
