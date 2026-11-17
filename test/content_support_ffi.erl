%% The content terms a key holds: each content table's name and id, sorted, read from
%% the persistent terms the store writes them to (genesis_prime/table/loader/store,
%% `put_content`, whose key is `{Key, {content_term, Table, Id}}`).
-module(content_support_ffi).
-export([terms/1]).

terms(Key) ->
    lists:sort([{Table, Id}
                || {{Held, {content_term, Table, Id}}, _} <- persistent_term:get(),
                   Held =:= Key]).
