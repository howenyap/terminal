import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

pub type Message(a) {
  Request(key: String, work: fn() -> a, reply_with: Subject(a))
  Done(key: String, result: a)
}

type State(a) {
  State(in_flight: Dict(String, List(Subject(a))), self: Subject(Message(a)))
}

pub fn child_spec(
  name: process.Name(Message(a)),
) -> supervision.ChildSpecification(Subject(Message(a))) {
  supervision.worker(fn() { start(name) })
}

pub fn start(
  name: process.Name(Message(a)),
) -> actor.StartResult(Subject(Message(a))) {
  actor.new_with_initialiser(1000, fn(self) {
    actor.initialised(State(in_flight: dict.new(), self: self))
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

pub fn fetch(
  subject: Subject(Message(a)),
  key: String,
  work: fn() -> a,
  timeout_ms: Int,
) -> a {
  actor.call(subject, timeout_ms, fn(reply) {
    Request(key: key, work: work, reply_with: reply)
  })
}

fn handle_message(
  state: State(a),
  message: Message(a),
) -> actor.Next(State(a), Message(a)) {
  case message {
    Request(key, work, caller) ->
      case dict.get(state.in_flight, key) {
        Ok(waiters) ->
          actor.continue(
            State(
              ..state,
              in_flight: dict.insert(state.in_flight, key, [caller, ..waiters]),
            ),
          )

        Error(Nil) -> {
          let self = state.self
          process.spawn(fn() {
            let result = work()
            actor.send(self, Done(key: key, result: result))
          })
          actor.continue(
            State(
              ..state,
              in_flight: dict.insert(state.in_flight, key, [caller]),
            ),
          )
        }
      }

    Done(key, result) -> {
      case dict.get(state.in_flight, key) {
        Ok(waiters) ->
          list.each(waiters, fn(waiter) { process.send(waiter, result) })
        Error(Nil) -> Nil
      }
      actor.continue(
        State(..state, in_flight: dict.delete(state.in_flight, key)),
      )
    }
  }
}
