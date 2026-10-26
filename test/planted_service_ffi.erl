-module(planted_service_ffi).
-export([set_max_heap_size/1]).

-spec set_max_heap_size(pos_integer()) -> nil.
set_max_heap_size(_Words) ->
    erlang:error({todo, "body in the build commit"}).
