import gleam/erlang/process
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision

pub type CacheEntry(a) {
  CacheEntry(expires_at_ms: Int, value: a)
}

const sweep_interval_ms = 60_000

pub fn init() -> Nil {
  ensure_table()
}

pub type SweepMsg {
  Sweep
}

pub fn sweeper_child_spec() -> supervision.ChildSpecification(Nil) {
  supervision.worker(start_sweeper)
  |> supervision.map_data(fn(_) { Nil })
}

fn start_sweeper() -> actor.StartResult(process.Subject(SweepMsg)) {
  actor.new_with_initialiser(sweep_interval_ms, fn(self) {
    schedule_sweep(self)
    actor.initialised(self)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(fn(self, msg) {
    case msg {
      Sweep -> {
        sweep_expired()
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

pub fn clear() -> Nil {
  clear_table()
}

pub fn lookup(key: String) -> Option(CacheEntry(a)) {
  lookup_raw(key)
  |> option.map(fn(entry) { CacheEntry(expires_at_ms: entry.0, value: entry.1) })
}

pub fn store(key: String, value: a, ttl_ms: Int) -> Nil {
  insert_raw(key, now_ms() + ttl_ms, value)
}

pub fn is_fresh(entry: CacheEntry(a)) -> Bool {
  entry.expires_at_ms > now_ms()
}

@external(erlang, "cache_ffi", "init")
fn ensure_table() -> Nil

@external(erlang, "cache_ffi", "clear")
fn clear_table() -> Nil

@external(erlang, "cache_ffi", "lookup")
fn lookup_raw(key: String) -> Option(#(Int, a))

@external(erlang, "cache_ffi", "insert")
fn insert_raw(key: String, expires_at_ms: Int, value: a) -> Nil

pub fn sweep() -> Nil {
  sweep_expired()
}

@external(erlang, "cache_ffi", "sweep")
fn sweep_expired() -> Nil

@external(erlang, "cache_ffi", "now_ms")
fn now_ms() -> Int
