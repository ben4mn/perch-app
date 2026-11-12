FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates openssh-client && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
COPY test ./test
COPY bridge ./bridge
RUN npx tsc -p . && npm prune --omit=dev
ENV PERCH_RELAY_CONFIG=/data/relay.config.json
USER node
EXPOSE 8787
CMD ["node", "dist/src/index.js", "serve"]
