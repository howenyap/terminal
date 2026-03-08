-module(nus_next_bus_test_support_ffi).

-export([counter/0, increment_counter/0, reset_counter/0]).

-define(TABLE, nus_next_bus_test_counter).
-define(KEY, counter).

reset_counter() ->
  case ets:info(?TABLE) of
    undefined ->
      ets:new(?TABLE, [named_table, public, set]);
    _ ->
      ok
  end,
  ets:insert(?TABLE, {?KEY, 0}),
  nil.

increment_counter() ->
  ets:update_counter(?TABLE, ?KEY, 1).

counter() ->
  case ets:lookup(?TABLE, ?KEY) of
    [{?KEY, Value}] -> Value;
    [] -> 0
  end.
