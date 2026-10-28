# Coral MSP action board: one small Node container, data in SQLite on a volume
FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=8080 \
    DB_PATH=/data/board.db

WORKDIR /app
COPY server/ ./server/
COPY app/index.html ./app/index.html

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "--experimental-sqlite", "--disable-warning=ExperimentalWarning", "server/server.js"]
