FROM oven/bun:1.3.14-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY --chown=bun:bun server/package.json ./package.json
COPY --chown=bun:bun server/src ./src

USER bun
EXPOSE 10000

CMD ["bun", "run", "start"]
