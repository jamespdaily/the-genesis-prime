-module(heap_limit_ffi).
-export([limit/1]).

%% Sets the calling process's heap ceiling: killed when it needs more than
%% `Words`, and the runtime logs the kill. The ceiling counts the process's own
%% heap, its stack and its waiting messages, not binaries outside the heap.
-spec limit(pos_integer()) -> nil.
limit(Words) ->
    process_flag(max_heap_size,
                 #{size => Words, kill => true, error_logger => true}),
    nil.
