import gleam/erlang/process
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision

pub opaque type Cache {
  Cache(table: EtsTable)
}

pub type CacheEntry(a) {
  CacheEntry(expires_at_ms: Int, value: a)
}

type EtsTable

const sweep_interval_ms = 60_000

pub fn init() -> Cache {
  Cache(table: create_table())
}

pub type SweepMsg {
  Sweep
}

pub fn sweeper_child_spec(cache: Cache) -> supervision.ChildSpecification(Nil) {
  supervision.worker(fn() { start_sweeper(cache) })
  |> supervision.map_data(fn(_) { Nil })
}

fn start_sweeper(cache: Cache) -> actor.StartResult(process.Subject(SweepMsg)) {
  actor.new_with_initialiser(1000, fn(self) {
    schedule_sweep(self)
    actor.initialised(self)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(fn(self, msg) {
    case msg {
      Sweep -> {
        sweep_expired(cache.table)
        schedule_sweep(self)
        actor.continue(self)
      }
    }
  })
  |> actor.start
}

fn schedule_sweep(subject: process.Subject(SweepMsg)) -> Nil {
  process.send_after(subject, sweep_interval_ms, Sweep)
  Nil
}

pub fn clear(cache: Cache) -> Nil {
  clear_table(cache.table)
}

pub fn lookup(cache: Cache, key: String) -> Option(CacheEntry(a)) {
  lookup_raw(cache.table, key)
  |> option.map(fn(entry) { CacheEntry(expires_at_ms: entry.0, value: entry.1) })
}

pub fn store(cache: Cache, key: String, value: a, ttl_ms: Int) -> Nil {
  insert_raw(cache.table, key, now_ms() + ttl_ms, value)
}

pub fn is_fresh(entry: CacheEntry(a)) -> Bool {
  entry.expires_at_ms > now_ms()
}

@external(erlang, "cache_ffi", "init")
fn create_table() -> EtsTable

@external(erlang, "cache_ffi", "clear")
fn clear_table(table: EtsTable) -> Nil

@external(erlang, "cache_ffi", "lookup")
fn lookup_raw(table: EtsTable, key: String) -> Option(#(Int, a))

@external(erlang, "cache_ffi", "insert")
fn insert_raw(table: EtsTable, key: String, expires_at_ms: Int, value: a) -> Nil

pub fn sweep(cache: Cache) -> Nil {
  sweep_expired(cache.table)
}

@external(erlang, "cache_ffi", "sweep")
fn sweep_expired(table: EtsTable) -> Nil

@external(erlang, "cache_ffi", "now_ms")
fn now_ms() -> Int
