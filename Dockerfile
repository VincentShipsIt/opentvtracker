FROM oven/bun:1.3.14-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY --chown=bun:bun server/package.json server/bun.lock ./
RUN bun install --frozen-lockfile --production

COPY --chown=bun:bun server/src ./src

USER bun
EXPOSE 8787

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD bun -e 'const port = Bun.env.PORT ?? "8787"; const response = await fetch(`http://127.0.0.1:${port}/health`); if (!response.ok) process.exit(1)'

CMD ["bun", "run", "start"]
