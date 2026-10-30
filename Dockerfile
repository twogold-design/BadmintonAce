FROM node:24-alpine
WORKDIR /app
COPY server/package*.json ./server/
RUN npm ci --prefix server --omit=dev
COPY server/ ./server/
COPY assets/challenges.json ./assets/challenges.json
RUN mkdir -p /app/data && chown node:node /app/data
ENV PORT=8766
ENV LAN_ONLY=0
ENV DATA_DIR=/app/data
ENV SERVE_WEB=0
EXPOSE 8766
USER node
CMD ["node", "server/server.js"]
