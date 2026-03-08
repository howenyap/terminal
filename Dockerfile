ARG ERLANG_VERSION=28
ARG GLEAM_VERSION=1.14.0

FROM ghcr.io/gleam-lang/gleam:v${GLEAM_VERSION}-scratch AS gleam

FROM erlang:${ERLANG_VERSION}-alpine AS build
COPY --from=gleam /bin/gleam /bin/gleam

WORKDIR /app

COPY gleam.toml manifest.toml ./
COPY src ./src
COPY packages ./packages

RUN gleam export erlang-shipment

FROM erlang:${ERLANG_VERSION}-alpine AS runtime

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/build/erlang-shipment ./build/erlang-shipment

USER app

EXPOSE 8000

CMD ["./build/erlang-shipment/entrypoint.sh", "run"]
