-module(heap_limit_ffi).
-export([limit/2]).

%% Sets the calling process's heap ceiling: killed when it needs more than
%% `Words`, and the runtime logs the kill. The ceiling counts the process's own
%% heap, its stack and its waiting messages, and the binaries the process shares
%% with others only when `IncludeSharedBinaries` is true.
-spec limit(pos_integer(), boolean()) -> nil.
limit(Words, IncludeSharedBinaries) ->
    process_flag(max_heap_size,
                 #{size => Words, kill => true, error_logger => true,
                   include_shared_binaries => IncludeSharedBinaries}),
    nil.
