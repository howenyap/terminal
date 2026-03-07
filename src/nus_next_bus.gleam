import dot_env
import gleam/erlang/process
import mist
import nus_next_bus/config
import nus_next_bus/proxy
import nus_next_bus/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  dot_env.load_default()

  let assert Ok(config) = config.from_env()
  let context =
    router.Context(config: config, fetch: proxy.live_fetcher(config))

  let assert Ok(_) =
    fn(request) { router.handle_request(request, context) }
    |> wisp_mist.handler(config.secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(config.port)
    |> mist.start

  process.sleep_forever()
}
