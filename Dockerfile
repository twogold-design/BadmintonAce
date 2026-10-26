FROM node:24-alpine
WORKDIR /app
COPY server/package*.json ./server/
RUN npm ci --prefix server --omit=dev
COPY server/ ./server/
COPY build/web/ ./build/web/
RUN mkdir -p /app/data && chown node:node /app/data
ENV PORT=8766
EXPOSE 8766
USER node
CMD ["node", "server/server.js"]
