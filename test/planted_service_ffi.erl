-module(planted_service_ffi).
-export([set_max_heap_size/1]).

-spec set_max_heap_size(pos_integer()) -> nil.
set_max_heap_size(Words) ->
    process_flag(max_heap_size,
                 #{size => Words, kill => true, error_logger => false}),
    nil.
