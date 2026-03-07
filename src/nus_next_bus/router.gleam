import gleam/bytes_tree
import gleam/http
import gleam/http/response
import gleam/int
import gleam/json
import nus_next_bus/config
import nus_next_bus/proxy
import wisp

pub type Context {
  Context(config: config.Config, fetch: proxy.UpstreamFetcher)
}

pub fn handle_request(request: wisp.Request, context: Context) -> wisp.Response {
  let response = case request.method {
    http.Options -> preflight()
    _ -> route(request, context)
  }

  with_cors(response, context.config)
}

fn route(request: wisp.Request, context: Context) -> wisp.Response {
  case wisp.path_segments(request) {
    ["healthz"] -> get_only(request, fn() { healthz() })
    ["publicity"] -> proxy_endpoint(request, context, "/publicity")
    ["bus-stops"] -> proxy_endpoint(request, context, "/BusStops")
    ["pickup-point"] -> proxy_endpoint(request, context, "/PickupPoint")
    ["shuttle-service"] -> proxy_endpoint(request, context, "/ShuttleService")
    ["active-bus"] -> proxy_endpoint(request, context, "/ActiveBus")
    ["bus-location"] -> proxy_endpoint(request, context, "/BusLocation")
    ["route-min-max-time"] ->
      proxy_endpoint(request, context, "/RouteMinMaxTime")
    ["service-description"] ->
      proxy_endpoint(request, context, "/ServiceDescription")
    ["announcements"] -> proxy_endpoint(request, context, "/Announcements")
    ["ticker-tapes"] -> proxy_endpoint(request, context, "/TickerTapes")
    ["check-point"] -> proxy_endpoint(request, context, "/CheckPoint")
    _ -> wisp.not_found()
  }
}

fn get_only(
  request: wisp.Request,
  handler: fn() -> wisp.Response,
) -> wisp.Response {
  case request.method {
    http.Get -> handler()
    _ -> wisp.method_not_allowed([http.Get])
  }
}

fn proxy_endpoint(
  request: wisp.Request,
  context: Context,
  upstream_path: String,
) -> wisp.Response {
  get_only(request, fn() {
    case
      proxy.build_request(
        context.config,
        upstream_path,
        wisp.get_query(request),
      )
    {
      Ok(upstream_request) -> {
        case context.fetch(upstream_request) {
          Ok(upstream_response) -> proxy_response(upstream_response)
          Error(proxy.UpstreamRequestFailed(_)) ->
            bad_gateway("Upstream request failed")
        }
      }
      Error(proxy.InvalidBaseUrl) -> invalid_base_url()
    }
  })
}

fn proxy_response(
  upstream_response: response.Response(BitArray),
) -> wisp.Response {
  case upstream_response.status {
    401 -> bad_gateway("Upstream authentication failed")
    404 -> passthrough_response(upstream_response)
    status if status >= 200 && status < 300 ->
      passthrough_response(upstream_response)
    status -> {
      wisp.log_error(
        "Unhandled upstream response status: " <> int.to_string(status),
      )
      wisp.internal_server_error()
    }
  }
}

fn passthrough_response(
  upstream_response: response.Response(BitArray),
) -> wisp.Response {
  let base = wisp.response(upstream_response.status)
  let base = case response.get_header(upstream_response, "content-type") {
    Ok(content_type) -> wisp.set_header(base, "content-type", content_type)
    Error(_) -> base
  }

  base
  |> response.set_body(
    wisp.Bytes(bytes_tree.from_bit_array(upstream_response.body)),
  )
}

fn healthz() -> wisp.Response {
  json.object([
    #("status", json.string("ok")),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}

fn json_error(status: Int, error: String, message: String) -> wisp.Response {
  json.object([
    #("error", json.string(error)),
    #("message", json.string(message)),
  ])
  |> json.to_string
  |> wisp.json_response(status)
}

fn bad_gateway(message: String) -> wisp.Response {
  wisp.log_warning(message)
  json_error(502, "bad_gateway", message)
}

fn invalid_base_url() -> wisp.Response {
  wisp.log_warning("Invalid upstream base URL")
  wisp.internal_server_error()
}

fn preflight() -> wisp.Response {
  wisp.no_content()
  |> wisp.set_header("access-control-allow-methods", "GET, OPTIONS")
  |> wisp.set_header("access-control-allow-headers", "content-type")
  |> wisp.set_header("access-control-max-age", "86400")
}

fn with_cors(response: wisp.Response, config: config.Config) -> wisp.Response {
  response
  |> wisp.set_header("access-control-allow-origin", config.cors_allow_origin)
}
