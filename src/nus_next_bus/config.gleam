import dot_env/env
import gleam/int
import gleam/option
import gleam/result
import gleam/string

pub type Config {
  Config(
    port: Int,
    base_url: String,
    username: String,
    password: String,
    request_timeout_ms: Int,
    cache_ttl_ms: Int,
    cors_allow_origin: String,
    secret_key_base: String,
  )
}

pub type StartupError {
  MissingPassword
  MissingSecretKeyBase
}

const default_port = 8000

const default_base_url = "https://nnextbus.nus.edu.sg"

const default_username = "NUSnextbus"

const default_request_timeout_ms = 5000

const default_cache_ttl_ms = 5000

const default_cors_allow_origin = "*"

pub fn from_env() -> Result(Config, StartupError) {
  new(
    port: option.unwrap(get_int_env("PORT"), default_port),
    base_url: default_base_url,
    username: default_username,
    password: get_string_env("NUS_NEXTBUS_PASSWORD"),
    request_timeout_ms: default_request_timeout_ms,
    cache_ttl_ms: default_cache_ttl_ms,
    cors_allow_origin: default_cors_allow_origin,
    secret_key_base: get_string_env("SECRET_KEY_BASE"),
  )
}

pub fn new(
  port port: Int,
  base_url base_url: String,
  username username: String,
  password password: option.Option(String),
  request_timeout_ms request_timeout_ms: Int,
  cache_ttl_ms cache_ttl_ms: Int,
  cors_allow_origin cors_allow_origin: String,
  secret_key_base secret_key_base: option.Option(String),
) -> Result(Config, StartupError) {
  use password <- result.try(option.to_result(password, MissingPassword))
  use secret_key_base <- result.try(option.to_result(
    secret_key_base,
    MissingSecretKeyBase,
  ))

  Ok(Config(
    port: port,
    base_url: base_url,
    username: username,
    password: password,
    request_timeout_ms: request_timeout_ms,
    cache_ttl_ms: cache_ttl_ms,
    cors_allow_origin: cors_allow_origin,
    secret_key_base: secret_key_base,
  ))
}

fn get_string_env(name: String) -> option.Option(String) {
  env.get_string(name)
  |> option.from_result
  |> option.then(fn(value) {
    case string.is_empty(value) {
      True -> option.None
      False -> option.Some(value)
    }
  })
}

fn get_int_env(name: String) -> option.Option(Int) {
  get_string_env(name)
  |> option.then(fn(value) {
    int.parse(value)
    |> option.from_result
  })
}
