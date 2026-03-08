-module(cache_ffi).

-export([clear/0, init/0, insert/3, lookup/1, now_ms/0, sweep/0]).

-define(TABLE, cache).

init() ->
    case ets:info(?TABLE) of
        undefined ->
            _ = ets:new(?TABLE,
                        [named_table,
                         public,
                         set,
                         {read_concurrency, true},
                         {write_concurrency, true}]),
            nil;
        _ ->
            nil
    end.

clear() ->
    case ets:info(?TABLE) of
        undefined ->
            nil;
        _ ->
            true = ets:delete_all_objects(?TABLE),
            nil
    end.

lookup(Key) ->
    case ets:lookup(?TABLE, Key) of
        [{Key, ExpiresAtMs, Value}] ->
            {some, {ExpiresAtMs, Value}};
        [] ->
            none
    end.

insert(Key, ExpiresAtMs, Value) ->
    true = ets:insert(?TABLE, {Key, ExpiresAtMs, Value}),
    nil.

sweep() ->
    Now = erlang:system_time(millisecond),
    ets:select_delete(?TABLE, [{{'_', '$1', '_'}, [{'<', '$1', Now}], [true]}]),
    nil.

now_ms() ->
    erlang:system_time(millisecond).
