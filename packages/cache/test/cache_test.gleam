import cache
import gleam/erlang/process
import gleam/option
import gleeunit

pub fn main() {
  gleeunit.main()
}

fn setup() {
  cache.init()
  cache.clear()
}

pub fn lookup_missing_key_returns_none_test() {
  setup()
  let assert option.None = cache.lookup("nonexistent")
}

pub fn store_then_lookup_returns_value_test() {
  setup()
  cache.store("key1", "hello", 10_000)
  let assert option.Some(entry) = cache.lookup("key1")
  let assert "hello" = entry.value
}

pub fn store_overwrites_previous_value_test() {
  setup()
  cache.store("key1", "first", 10_000)
  cache.store("key1", "second", 10_000)
  let assert option.Some(entry) = cache.lookup("key1")
  let assert "second" = entry.value
}

pub fn is_fresh_returns_true_for_future_expiry_test() {
  setup()
  cache.store("key1", "value", 10_000)
  let assert option.Some(entry) = cache.lookup("key1")
  let assert True = cache.is_fresh(entry)
}

pub fn is_fresh_returns_false_after_ttl_elapses_test() {
  setup()
  cache.store("key1", "value", 5)
  process.sleep(10)
  let assert option.Some(entry) = cache.lookup("key1")
  let assert False = cache.is_fresh(entry)
}

pub fn clear_removes_all_entries_test() {
  setup()
  cache.store("a", "1", 10_000)
  cache.store("b", "2", 10_000)
  cache.clear()
  let assert option.None = cache.lookup("a")
  let assert option.None = cache.lookup("b")
}

pub fn sweep_removes_expired_but_keeps_fresh_test() {
  setup()
  cache.store("expired", "old", 5)
  cache.store("fresh", "new", 10_000)
  process.sleep(10)
  cache.sweep()
  let assert option.None = cache.lookup("expired")
  let assert option.Some(entry) = cache.lookup("fresh")
  let assert "new" = entry.value
}

pub fn sweep_keeps_all_when_none_expired_test() {
  setup()
  cache.store("a", "1", 10_000)
  cache.store("b", "2", 10_000)
  cache.sweep()
  let assert option.Some(_) = cache.lookup("a")
  let assert option.Some(_) = cache.lookup("b")
}
