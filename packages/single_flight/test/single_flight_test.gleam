import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleeunit
import single_flight

pub fn main() {
  gleeunit.main()
}

pub fn same_key_executes_work_once_test() {
  let sf = start_sf()
  let counter = start_counter()

  let work = fn() {
    increment(counter, "a")
    process.sleep(50)
    "result_a"
  }

  let subjects =
    list.repeat(Nil, 5)
    |> list.map(fn(_) {
      let subj = process.new_subject()
      process.spawn(fn() {
        let result = single_flight.fetch(sf, "a", work, 5000)
        process.send(subj, result)
      })
      subj
    })

  list.each(subjects, fn(subj) {
    let assert "result_a" = process.receive(subj, 5000) |> unwrap
  })

  let counts = get_counts(counter)
  let assert Ok(1) = dict.get(counts, "a")
}

pub fn different_keys_execute_independently_test() {
  let sf = start_sf()
  let counter = start_counter()

  let make_work = fn(key, value) {
    fn() {
      increment(counter, key)
      process.sleep(50)
      value
    }
  }

  let subj_a = process.new_subject()
  let subj_b = process.new_subject()

  process.spawn(fn() {
    let r = single_flight.fetch(sf, "a", make_work("a", "val_a"), 5000)
    process.send(subj_a, r)
  })
  process.spawn(fn() {
    let r = single_flight.fetch(sf, "b", make_work("b", "val_b"), 5000)
    process.send(subj_b, r)
  })

  let assert "val_a" = process.receive(subj_a, 5000) |> unwrap
  let assert "val_b" = process.receive(subj_b, 5000) |> unwrap

  let counts = get_counts(counter)
  let assert Ok(1) = dict.get(counts, "a")
  let assert Ok(1) = dict.get(counts, "b")
}

pub fn sequential_calls_re_execute_work_test() {
  let sf = start_sf()
  let counter = start_counter()

  let work = fn() {
    increment(counter, "a")
    "done"
  }

  let assert "done" = single_flight.fetch(sf, "a", work, 5000)
  let assert "done" = single_flight.fetch(sf, "a", work, 5000)

  let counts = get_counts(counter)
  let assert Ok(2) = dict.get(counts, "a")
}

type CounterMsg {
  Increment(key: String)
  GetCounts(reply_with: Subject(Dict(String, Int)))
}

fn start_counter() -> Subject(CounterMsg) {
  let assert Ok(actor.Started(data: subject, ..)) =
    actor.new(dict.new())
    |> actor.on_message(fn(state, msg) {
      case msg {
        Increment(key) -> {
          let count = case dict.get(state, key) {
            Ok(n) -> n + 1
            Error(Nil) -> 1
          }
          actor.continue(dict.insert(state, key, count))
        }
        GetCounts(reply) -> {
          process.send(reply, state)
          actor.continue(state)
        }
      }
    })
    |> actor.start

  subject
}

fn increment(counter: Subject(CounterMsg), key: String) {
  actor.send(counter, Increment(key))
}

fn get_counts(counter: Subject(CounterMsg)) -> Dict(String, Int) {
  actor.call(counter, 1000, GetCounts)
}

fn start_sf() -> Subject(single_flight.Message(String)) {
  let name = process.new_name(prefix: "sf_test")
  let assert Ok(actor.Started(data: subject, ..)) = single_flight.start(name)

  subject
}

fn unwrap(result: Result(a, b)) -> a {
  let assert Ok(value) = result

  value
}
