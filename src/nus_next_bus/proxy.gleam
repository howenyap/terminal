import gleam/bit_array
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/result
import gleam/string
import nus_next_bus/config.{type Config}

pub type BuildRequestError {
  InvalidBaseUrl
}

pub type FetchError {
  UpstreamRequestFailed(httpc.HttpError)
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

pub fn live_fetcher(config: Config) -> UpstreamFetcher {
  let client_config =
    httpc.configure()
    |> httpc.timeout(config.request_timeout_ms)

  fn(request) {
    httpc.dispatch(client_config, request)
    |> result.map(fn(response) {
      response.Response(..response, body: bit_array.from_string(response.body))
    })
    |> result.map_error(UpstreamRequestFailed)
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
