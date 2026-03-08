import cache
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/option
import gleam/result
import gleam/string
import nus_next_bus/config.{type Config}
import single_flight

pub type BuildRequestError {
  InvalidBaseUrl
}

pub type FetchError {
  UpstreamRequestFailed(httpc.HttpError)
  SingleFlightWorkerFailed
}

pub type UpstreamFetcher =
  fn(Request(String)) -> Result(Response(BitArray), FetchError)

pub fn build_request(
  config: Config,
  path: String,
  query: List(#(String, String)),
) -> Result(Request(String), BuildRequestError) {
  request.to(config.base_url)
  |> result.replace_error(InvalidBaseUrl)
  |> result.map(fn(base_request) {
    base_request
    |> request.set_path(join_paths(base_request.path, path))
    |> set_query(query)
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "application/json")
    |> request.set_header(
      "authorization",
      "Basic " <> basic_auth(config.username, config.password),
    )
  })
}

type FetchResult =
  Result(Response(BitArray), FetchError)

pub fn live_fetcher(
  config: Config,
  single_flight_worker: Subject(single_flight.Message(FetchResult)),
) -> UpstreamFetcher {
  let client_config =
    httpc.configure()
    |> httpc.timeout(config.request_timeout_ms)

  with_cache(
    config.cache_ttl_ms,
    config.request_timeout_ms,
    single_flight_worker,
    fn(request) {
      httpc.dispatch(client_config, request)
      |> result.map(fn(response) {
        response.Response(
          ..response,
          body: bit_array.from_string(response.body),
        )
      })
      |> result.map_error(UpstreamRequestFailed)
    },
  )
}

pub fn with_cache(
  ttl_ms: Int,
  timeout_ms: Int,
  single_flight_worker: Subject(single_flight.Message(FetchResult)),
  do_fetch: fn(Request(String)) -> FetchResult,
) -> UpstreamFetcher {
  fn(request) {
    let key = cache_key(request)
    let cached_entry = cache.lookup(key)

    case cached_entry |> option.then(fresh_value) {
      option.Some(response) -> Ok(response)
      option.None -> {
        let result =
          single_flight.fetch(
            single_flight_worker,
            key,
            fn() { do_fetch(request) },
            timeout_ms,
          )

        result
        |> result.map(fn(response) {
          case should_cache(response) {
            True -> cache.store(key, response, ttl_ms)
            False -> Nil
          }

          response
        })
      }
    }
  }
}

fn cache_key(request: Request(String)) -> String {
  let request.Request(path:, query:, ..) = request

  case query {
    option.Some(query) if query != "" -> path <> "?" <> query
    _ -> path
  }
}

pub fn basic_auth(username: String, password: String) -> String {
  { username <> ":" <> password }
  |> bit_array.from_string
  |> bit_array.base64_encode(False)
}

fn join_paths(base_path: String, path: String) -> String {
  case base_path, path {
    "", p | "/", p -> p
    b, "" -> b
    b, p ->
      case string.starts_with(p, "/") {
        True -> b <> p
        False -> b <> "/" <> p
      }
  }
}

fn set_query(
  request: Request(String),
  query: List(#(String, String)),
) -> Request(String) {
  case query {
    [] -> request
    _ -> request.set_query(request, query)
  }
}

fn fresh_value(entry: cache.CacheEntry(a)) -> option.Option(a) {
  case cache.is_fresh(entry) {
    True -> option.Some(entry.value)
    False -> option.None
  }
}

fn should_cache(response: Response(BitArray)) -> Bool {
  case response.status {
    404 -> True
    status if status >= 200 && status < 300 -> True
    _ -> False
  }
}
