import cache
import dot_env
import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import mist
import nus_next_bus/config
import nus_next_bus/proxy
import nus_next_bus/router
import single_flight
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  dot_env.load_default()

  let assert Ok(config) = config.from_env()
  cache.init()

  let single_flight_worker_name = process.new_name("single_flight_worker")

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(cache.sweeper_child_spec())
    |> supervisor.add(single_flight.child_spec(single_flight_worker_name))
    |> supervisor.start

  let single_flight_worker = process.named_subject(single_flight_worker_name)
  let context =
    router.Context(
      config: config,
      fetch: proxy.live_fetcher(config, single_flight_worker),
    )

  let assert Ok(_) =
    fn(request) { router.handle_request(request, context) }
    |> wisp_mist.handler(config.secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(config.port)
    |> mist.start

  process.sleep_forever()
}
