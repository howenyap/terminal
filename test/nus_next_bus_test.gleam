import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/option
import gleam/result
import gleeunit
import gleeunit/should
import nus_next_bus/config
import nus_next_bus/proxy
import nus_next_bus/router
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
      cors_allow_origin: "*",
      secret_key_base: option.Some("dummy-secret-key"),
    )
  config
}

fn context_with(
  fetch: proxy.UpstreamFetcher,
  password password: String,
) -> router.Context {
  let config = config.Config(..base_config(), password: password)
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
  let response = perform(http.Get, path, context_with(inspect_fetch, "pw"))
  let body = simulate.read_body(response)

  should.equal(response.status, 200)
  should.equal(
    body,
    json.to_string(
      json.object([
        #("path", json.string(expected_upstream_path)),
        #("query", json.string(expected_query)),
        #(
          "authorization",
          json.string("Basic " <> proxy.basic_auth(dummy_username, "pw")),
        ),
        #("accept", json.string("application/json")),
        #("content_type", json.string("application/json")),
      ]),
    ),
  )
}

pub fn healthz_test() {
  let response =
    perform(http.Get, "/healthz", context_with(inspect_fetch, "pw"))

  should.equal(response.status, 200)
  should.equal(simulate.read_body(response), "{\"status\":\"ok\"}")
}

pub fn validate_config_test() {
  let config.Config(
    port: port,
    base_url: base_url,
    username: username,
    password: password,
    request_timeout_ms: request_timeout_ms,
    cors_allow_origin: cors_allow_origin,
    secret_key_base: secret_key_base,
  ) = base_config()

  should.equal(
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.Some(password),
      request_timeout_ms: request_timeout_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.Some(secret_key_base),
    ),
    Ok(base_config()),
  )

  should.equal(
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.None,
      request_timeout_ms: request_timeout_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.Some(secret_key_base),
    ),
    Error(config.MissingPassword),
  )

  should.equal(
    config.new(
      port: port,
      base_url: base_url,
      username: username,
      password: option.Some(password),
      request_timeout_ms: request_timeout_ms,
      cors_allow_origin: cors_allow_origin,
      secret_key_base: option.None,
    ),
    Error(config.MissingSecretKeyBase),
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
    perform(http.Get, "/bus-stops", context_with(inspect_fetch, "pw"))

  should.equal(
    response.get_header(response, "access-control-allow-origin"),
    Ok("*"),
  )
}

pub fn options_preflight_returns_cors_metadata_test() {
  let response =
    perform(http.Options, "/bus-stops", context_with(inspect_fetch, "pw"))

  should.equal(response.status, 204)
  should.equal(
    response.get_header(response, "access-control-allow-methods"),
    Ok("GET, OPTIONS"),
  )
  should.equal(
    response.get_header(response, "access-control-allow-headers"),
    Ok("content-type"),
  )
}

pub fn upstream_401_returns_502_test() {
  let fetch = fn(_request) {
    Ok(
      response.Response(401, [#("content-type", "text/plain")], <<
        "Unauthorized",
      >>),
    )
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, "pw"))

  should.equal(response.status, 502)
  should.equal(
    simulate.read_body(response),
    "{\"error\":\"bad_gateway\",\"message\":\"Upstream authentication failed\"}",
  )
}

pub fn upstream_404_is_passed_through_test() {
  let fetch = fn(_request) {
    Ok(
      response.Response(404, [#("content-type", "text/html; charset=utf-8")], <<
        "Service not found!",
      >>),
    )
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, "pw"))

  should.equal(response.status, 404)
  should.equal(simulate.read_body(response), "Service not found!")
  should.equal(
    response.get_header(response, "content-type"),
    Ok("text/html; charset=utf-8"),
  )
}

pub fn upstream_timeout_returns_502_test() {
  let fetch = fn(_request) {
    Error(proxy.UpstreamRequestFailed(httpc.ResponseTimeout))
  }
  let response = perform(http.Get, "/bus-stops", context_with(fetch, "pw"))

  should.equal(response.status, 502)
  should.equal(
    simulate.read_body(response),
    "{\"error\":\"bad_gateway\",\"message\":\"Upstream request failed\"}",
  )
}

pub fn unknown_route_returns_404_test() {
  let response =
    perform(http.Get, "/unknown", context_with(inspect_fetch, "pw"))

  should.equal(response.status, 404)
}

pub fn wrong_method_returns_405_test() {
  let response =
    perform(http.Post, "/bus-stops", context_with(inspect_fetch, "pw"))

  should.equal(response.status, 405)
  should.equal(response.get_header(response, "allow"), Ok("GET"))
}
