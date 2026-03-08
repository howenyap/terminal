import cache
import gleam/erlang/process
import gleam/option
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn lookup_missing_key_returns_none_test() {
  let c = cache.init()
  let assert option.None = cache.lookup(c, "nonexistent")
}

pub fn store_then_lookup_returns_value_test() {
  let c = cache.init()
  cache.store(c, "key1", "hello", 10_000)
  let assert option.Some(entry) = cache.lookup(c, "key1")
  let assert "hello" = entry.value
}

pub fn store_overwrites_previous_value_test() {
  let c = cache.init()
  cache.store(c, "key1", "first", 10_000)
  cache.store(c, "key1", "second", 10_000)
  let assert option.Some(entry) = cache.lookup(c, "key1")
  let assert "second" = entry.value
}

pub fn is_fresh_returns_true_for_future_expiry_test() {
  let c = cache.init()
  cache.store(c, "key1", "value", 10_000)
  let assert option.Some(entry) = cache.lookup(c, "key1")
  let assert True = cache.is_fresh(entry)
}

pub fn is_fresh_returns_false_after_ttl_elapses_test() {
  let c = cache.init()
  cache.store(c, "key1", "value", 5)
  process.sleep(10)
  let assert option.Some(entry) = cache.lookup(c, "key1")
  let assert False = cache.is_fresh(entry)
}

pub fn clear_removes_all_entries_test() {
  let c = cache.init()
  cache.store(c, "a", "1", 10_000)
  cache.store(c, "b", "2", 10_000)
  cache.clear(c)
  let assert option.None = cache.lookup(c, "a")
  let assert option.None = cache.lookup(c, "b")
}

pub fn sweep_removes_expired_but_keeps_fresh_test() {
  let c = cache.init()
  cache.store(c, "expired", "old", 5)
  cache.store(c, "fresh", "new", 10_000)
  process.sleep(10)
  cache.sweep(c)
  let assert option.None = cache.lookup(c, "expired")
  let assert option.Some(entry) = cache.lookup(c, "fresh")
  let assert "new" = entry.value
}

pub fn sweep_keeps_all_when_none_expired_test() {
  let c = cache.init()
  cache.store(c, "a", "1", 10_000)
  cache.store(c, "b", "2", 10_000)
  cache.sweep(c)
  let assert option.Some(_) = cache.lookup(c, "a")
  let assert option.Some(_) = cache.lookup(c, "b")
}
