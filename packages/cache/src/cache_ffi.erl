-module(cache_ffi).

-export([init/0, clear/1, insert/4, lookup/2, sweep/1, now_ms/0]).

init() ->
    ets:new(cache, [public, set, {read_concurrency, true}, {write_concurrency, true}]).

clear(Table) ->
    true = ets:delete_all_objects(Table),
    nil.

lookup(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{_Key, ExpiresAtMs, Value}] ->
            {some, {ExpiresAtMs, Value}};
        [] ->
            none
    end.

insert(Table, Key, ExpiresAtMs, Value) ->
    true = ets:insert(Table, {Key, ExpiresAtMs, Value}),
    nil.

sweep(Table) ->
    Now = erlang:system_time(millisecond),
    ets:select_delete(Table, [{{'_', '$1', '_'}, [{'<', '$1', Now}], [true]}]),
    nil.

now_ms() ->
    erlang:system_time(millisecond).
