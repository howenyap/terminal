import cache
import gleam/bit_array
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/option
import gleam/result
import gleeunit
import nus_next_bus/config
import nus_next_bus/proxy
import nus_next_bus/router
import single_flight
import wisp
import wisp/simulate

const dummy_username = "dummy-user"

const dummy_password = "dummy-password"

pub fn main() -> Nil {
  gleeunit.main()
}

fn base_config() -> config.Config {
  let assert Ok(config) =
    config.new(
      port: 8000,
      base_url: "https://dummy-url",
      username: dummy_username,
      password: option.Some(dummy_password),
      request_timeout_ms: 5000,
      cache_ttl_ms: 15_000,
      cors_allow_origin: "*",
      secret_key_base: option.Some("dummy-secret-key"),
    )
  config
}

fn context_with(
  fetch: proxy.UpstreamFetcher,
  cache_ttl_ms cache_ttl_ms: Int,
) -> router.Context {
  let config = config.Config(..base_config(), cache_ttl_ms: cache_ttl_ms)
  router.Context(config: config, fetch: fetch)
}

fn inspect_fetch(
  request: request.Request(String),
) -> Result(response.Response(BitArray), proxy.FetchError) {
  let request.Request(path:, query:, ..) = request
  let auth =
    request.get_header(request, "authorization")
    |> result.unwrap("")
  let accept =
    request.get_header(request, "accept")
    |> result.unwrap("")
  let content_type =
    request.get_header(request, "content-type")
    |> result.unwrap("")
  let body =
    json.object([
      #("path", json.string(path)),
      #("query", json.string(option.unwrap(query, ""))),
      #("authorization", json.string(auth)),
      #("accept", json.string(accept)),
      #("content_type", json.string(content_type)),
    ])
    |> json.to_string
    |> bit_array.from_string

  Ok(response.Response(
    200,
    [#("content-type", "application/json; charset=utf-8")],
    body,
  ))
}

fn perform(
  method: http.Method,
  path: String,
  context: router.Context,
) -> wisp.Response {
  router.handle_request(simulate.request(method, path), context)
}

fn expect_passthrough(
  path: String,
  expected_upstream_path: String,
  expected_query: String,
) -> Nil {
  let response = perform(http.Get, path, context_with(inspect_fetch, 15_000))
  let body = simulate.read_body(response)

  let assert 200 = response.status
  let expected =
    json.to_string(
      json.object([
        #("path", json.string(expected_upstream_path)),
        #("query", json.string(expected_query)),
        #(
          "authorization",
          json.string(
            "Basic " <> proxy.basic_auth(dummy_username, dummy_password),
          ),
        ),
        #("accept", json.string("application/json")),
        #("content_type", json.string("application/json")),
      ]),
    )
  case body == expected {
    True -> Nil
    False -> panic as { "Expected: " <> expected <> "\nGot:      " <> body }
  }
}

pub fn healthz_test() {
  let response =
    perform(http.Get, "/healthz", context_with(inspect_fetch, 15_000))

  let assert 200 = response.status
  let assert "{\"status\":\"ok\"}" = simulate.read_body(response)
}

pub fn validate_config_test() {
  let config.Config(
    port: port,
    base_url: base_url,
    username: username,
    password: password,
    request_timeout_ms: request_timeout_ms,
    cache_ttl_ms: cache_ttl_ms,
    cors_allow_origin: cors_allow_origin,
    secret_key_base: secret_key_base,
  ) = base_config()

  let assert Ok(_) =
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.Some(password),
      request_timeout_ms: request_timeout_ms,
      cache_ttl_ms: cache_ttl_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.Some(secret_key_base),
    )

  let assert Error(config.MissingPassword) =
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.None,
      request_timeout_ms: request_timeout_ms,
      cache_ttl_ms: cache_ttl_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.Some(secret_key_base),
    )

  let assert Error(config.MissingSecretKeyBase) =
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.Some(password),
      request_timeout_ms: request_timeout_ms,
      cache_ttl_ms: cache_ttl_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.None,
    )
}

pub fn mirrored_routes_forward_correct_paths_and_queries_test() {
  expect_passthrough("/publicity", "/publicity", "")
  expect_passthrough("/bus-stops", "/BusStops", "")
  expect_passthrough(
    "/pickup-point?route_code=A1",
    "/PickupPoint",
    "route_code=A1",
  )
  expect_passthrough(
    "/shuttle-service?busstopname=COM3",
    "/ShuttleService",
    "busstopname=COM3",
  )
  expect_passthrough(
    "/active-bus?route_code=A1&token=",
    "/ActiveBus",
    "route_code=A1&token=",
  )
  expect_passthrough(
    "/bus-location?veh_plate=PD554H",
    "/BusLocation",
    "veh_plate=PD554H",
  )
  expect_passthrough(
    "/route-min-max-time?route_code=A1",
    "/RouteMinMaxTime",
    "route_code=A1",
  )
  expect_passthrough("/service-description", "/ServiceDescription", "")
  expect_passthrough("/announcements", "/Announcements", "")
  expect_passthrough("/ticker-tapes", "/TickerTapes", "")
  expect_passthrough(
    "/check-point?route_code=A1",
    "/CheckPoint",
    "route_code=A1",
  )
}

pub fn get_requests_include_cors_headers_test() {
  let response =
    perform(http.Get, "/bus-stops", context_with(inspect_fetch, 15_000))

  let assert Ok("*") =
    response.get_header(response, "access-control-allow-origin")
}

pub fn options_preflight_returns_cors_metadata_test() {
  let response =
    perform(http.Options, "/bus-stops", context_with(inspect_fetch, 15_000))

  let assert 204 = response.status
  let assert Ok("GET, OPTIONS") =
    response.get_header(response, "access-control-allow-methods")
  let assert Ok("content-type") =
    response.get_header(response, "access-control-allow-headers")
}

pub fn upstream_401_returns_502_test() {
  let fetch = fn(_request) {
    Ok(
      response.Response(401, [#("content-type", "text/plain")], <<
        "Unauthorized",
      >>),
    )
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))

  let assert 502 = response.status
  let assert "{\"error\":\"bad_gateway\",\"message\":\"Upstream authentication failed\"}" =
    simulate.read_body(response)
}

pub fn upstream_404_is_passed_through_test() {
  let fetch = fn(_request) {
    Ok(
      response.Response(404, [#("content-type", "text/html; charset=utf-8")], <<
        "Service not found!",
      >>),
    )
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))

  let assert 404 = response.status
  let assert "Service not found!" = simulate.read_body(response)
  let assert Ok("text/html; charset=utf-8") =
    response.get_header(response, "content-type")
}

pub fn upstream_timeout_returns_502_test() {
  let fetch = fn(_request) {
    Error(proxy.UpstreamRequestFailed(httpc.ResponseTimeout))
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))

  let assert 502 = response.status
  let assert "{\"error\":\"bad_gateway\",\"message\":\"Upstream request failed\"}" =
    simulate.read_body(response)
}

pub fn unknown_route_returns_404_test() {
  let response =
    perform(http.Get, "/unknown", context_with(inspect_fetch, 15_000))

  let assert 404 = response.status
}

pub fn wrong_method_returns_405_test() {
  let response =
    perform(http.Post, "/bus-stops", context_with(inspect_fetch, 15_000))

  let assert 405 = response.status
  let assert Ok("GET") = response.get_header(response, "allow")
}

pub fn identical_requests_hit_upstream_once_within_ttl_test() {
  reset_counter()
  let #(_cache, fetch) = cached_fetcher(15_000, counting_success_fetch)

  let first = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))
  let second = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))

  let assert 200 = first.status
  let assert 200 = second.status
  let assert 1 = fetch_count()
}

pub fn cache_key_separates_distinct_queries_test() {
  reset_counter()
  let #(_cache, fetch) = cached_fetcher(15_000, counting_success_fetch)

  let first =
    perform(
      http.Get,
      "/pickup-point?route_code=A1",
      context_with(fetch, 15_000),
    )
  let second =
    perform(
      http.Get,
      "/pickup-point?route_code=A2",
      context_with(fetch, 15_000),
    )

  let assert 200 = first.status
  let assert 200 = second.status
  let assert 2 = fetch_count()
}

pub fn expired_entries_refetch_upstream_test() {
  reset_counter()
  let #(_cache, fetch) = cached_fetcher(50, counting_success_fetch)

  let first = perform(http.Get, "/bus-stops", context_with(fetch, 50))
  process.sleep(100)
  let second = perform(http.Get, "/bus-stops", context_with(fetch, 50))

  let assert 200 = first.status
  let assert 200 = second.status
  let assert 2 = fetch_count()
}

pub fn stale_cache_is_not_served_when_upstream_fails_test() {
  reset_counter()
  let #(_cache, fetch) = cached_fetcher(50, succeed_once_then_fail_fetch)

  let first = perform(http.Get, "/bus-stops", context_with(fetch, 50))
  process.sleep(100)
  let second = perform(http.Get, "/bus-stops", context_with(fetch, 50))

  let assert 200 = first.status
  let assert 502 = second.status
  let assert 2 = fetch_count()
}

pub fn transport_errors_are_not_cached_test() {
  reset_counter()
  let #(_cache, fetch) = cached_fetcher(15_000, fail_once_then_succeed_fetch)

  let first = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))
  let second = perform(http.Get, "/bus-stops", context_with(fetch, 15_000))

  let assert 502 = first.status
  let assert 200 = second.status
  let assert 2 = fetch_count()
}

fn cached_fetcher(
  ttl_ms: Int,
  mock_fetch: fn(request.Request(String)) ->
    Result(response.Response(BitArray), proxy.FetchError),
) -> #(cache.Cache, proxy.UpstreamFetcher) {
  let c = cache.init()
  let name = process.new_name("test_single_flight")
  let assert Ok(_) = single_flight.start(name)
  let single_flight_worker = process.named_subject(name)

  #(c, proxy.with_cache(c, ttl_ms, 5000, single_flight_worker, mock_fetch))
}

fn counting_success_fetch(
  _request: request.Request(String),
) -> Result(response.Response(BitArray), proxy.FetchError) {
  increment_counter()
  Ok(ok_response())
}

fn succeed_once_then_fail_fetch(
  _request: request.Request(String),
) -> Result(response.Response(BitArray), proxy.FetchError) {
  case increment_counter() {
    1 -> Ok(ok_response())
    _ -> Error(proxy.UpstreamRequestFailed(httpc.ResponseTimeout))
  }
}

fn fail_once_then_succeed_fetch(
  _request: request.Request(String),
) -> Result(response.Response(BitArray), proxy.FetchError) {
  case increment_counter() {
    1 -> Error(proxy.UpstreamRequestFailed(httpc.ResponseTimeout))
    _ -> Ok(ok_response())
  }
}

fn ok_response() -> response.Response(BitArray) {
  response.Response(200, [#("content-type", "application/json")], <<>>)
}

@external(erlang, "nus_next_bus_test_support_ffi", "reset_counter")
fn reset_counter() -> Nil

@external(erlang, "nus_next_bus_test_support_ffi", "increment_counter")
fn increment_counter() -> Int

@external(erlang, "nus_next_bus_test_support_ffi", "counter")
fn fetch_count() -> Int
