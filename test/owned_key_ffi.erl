-module(owned_key_ffi).
-export([new/0, own/2, left_behind/1, erase_left/1, terms_under/1, erase/1]).

%% A new reference, remembered in the calling process's dictionary as made by it
%% and to be erased by it.
new() ->
    Reference = make_ref(),
    remember(Reference, erased_by_the_test),
    Reference.

%% The store's load key {load_key, Reference} remembered the same way, with
%% Kind: erased_by_the_test, or erased_with_the_test. The server's own key is no
%% one's and is given back as it is.
own({load_key, Reference} = Key, Kind) ->
    remember(Reference, Kind),
    Key;
own(Key, _Kind) ->
    Key.

remember(Reference, Kind) ->
    put({owned_key, Reference}, Kind),
    ok.

%% The references a process made through new/0 and own/2, with their kinds. A
%% process that has ended has none: its dictionary is gone.
owned_by(Owner) ->
    case process_info(Owner, dictionary) of
        {dictionary, Dictionary} -> [{Reference, Kind} || {{owned_key, Reference}, Kind} <- Dictionary];
        undefined -> []
    end.

%% The persistent terms stored under the load keys of these references: each
%% {{load_key, Reference}, Name} the store wrote (genesis_prime/table/loader/store).
stored_under([]) ->
    [];
stored_under(References) ->
    Wanted = maps:from_keys(References, true),
    [Stored || {{{load_key, Reference}, _Name} = Stored, _Term} <- persistent_term:get(),
               maps:is_key(Reference, Wanted)].

%% How many persistent terms are stored under the keys the owner made to be
%% erased by the test; the keys erased with the test are not counted.
left_behind(Owner) ->
    Mine = [Reference || {Reference, erased_by_the_test} <- owned_by(Owner)],
    length(stored_under(Mine)).

%% Erases every persistent term stored under the keys the owner made.
erase_left(Owner) ->
    erase_each(stored_under([Reference || {Reference, _Kind} <- owned_by(Owner)])).

%% How many persistent terms are stored under one load key.
terms_under({load_key, Reference}) ->
    length(stored_under([Reference]));
terms_under(_ServerKey) ->
    0.

%% Erases every persistent term stored under one load key.
erase({load_key, Reference}) ->
    erase_each(stored_under([Reference]));
erase(_ServerKey) ->
    nil.

erase_each(Stored) ->
    lists:foreach(fun persistent_term:erase/1, Stored),
    nil.
