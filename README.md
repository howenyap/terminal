# Gleam
Install [Gleam](https://gleam.run/install/)

# Environment
- `NUS_NEXTBUS_PASSWORD`: password for NUS NextBus
- `SECRET_KEY_BASE`: secret key for Wisp

# Commands 
- run: `gleam run`
- test: `gleam test`

# Packages
## Cache
Uses [ets](https://www.erlang.org/doc/apps/stdlib/ets.html) for caching via Erlang FFI bindings.

## Single Flight
Uses [actors](https://hexdocs.pm/gleam_otp/gleam/otp/actor.html) to ensure only one request of the same key exists at a time.
