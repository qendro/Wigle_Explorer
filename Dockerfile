FROM node:22.16.0-bookworm-slim AS node

FROM hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20250428-slim AS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates curl inotify-tools \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
RUN mix local.hex --force && mix local.rebar --force \
    && mix archive.install hex phx_new 1.8.15 --force
WORKDIR /app

FROM toolchain AS development
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get && mix deps.compile
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix assets
COPY . .
RUN mix assets.setup && mix assets.build && mix compile
EXPOSE 4000
CMD ["sh", "-c", "mix deps.get && npm ci --prefix assets --no-audit --no-fund && mix assets.build && exec mix phx.server"]
