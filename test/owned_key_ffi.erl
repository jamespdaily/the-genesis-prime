-module(owned_key_ffi).
-export([own/2, left_behind/1, erase_left/1, terms_under/1, erase/1, wait_until_dead/1]).

%% The references each process made, kept in a table that outlives the
%% processes: {Owner, Reference, Kind}. A body that crashes, is killed by a
%% linked process or returns is dead when its terms are counted,
%% so a process dictionary would be gone with it.
-define(TABLE, owned_key_references).

%% The store's load key {load_key, Reference} remembered the same way, with
%% Kind: erased_by_the_test, or erased_with_the_test. The server's own key is no
%% one's and is given back as it is.
own({load_key, Reference} = Key, Kind) ->
    remember(Reference, Kind),
    Key;
own(Key, _Kind) ->
    Key.

remember(Reference, Kind) ->
    ensure_table(),
    ets:insert(?TABLE, {self(), Reference, Kind}),
    ok.

%% The tables are made by a process that stays for the life of the VM, by the
%% first caller; a caller that loses the race finds them made.
ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined ->
            Caller = self(),
            Made = make_ref(),
            spawn(fun() ->
                try
                    ets:new(?TABLE, [named_table, public, bag, {write_concurrency, true}])
                of
                    _ ->
                        Caller ! {Made, made},
                        receive stop -> ok end
                catch
                    error:badarg -> Caller ! {Made, made}
                end
            end),
            receive {Made, made} -> ok end;
        _ ->
            ok
    end.

%% The references a process made through own/2, with their kinds.
owned_by(Owner) ->
    case ets:whereis(?TABLE) of
        undefined -> [];
        _ -> [{Reference, Kind} || {_Owner, Reference, Kind} <- ets:lookup(?TABLE, Owner)]
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

%% Erases every persistent term stored under the keys the owner made, of either
%% kind, and forgets the owner's keys.
erase_left(Owner) ->
    erase_each(stored_under([Reference || {Reference, _Kind} <- owned_by(Owner)])),
    case ets:whereis(?TABLE) of
        undefined ->
            ok;
        _ ->
            ets:delete(?TABLE, Owner)
    end,
    nil.

%% How many persistent terms are stored under one load key. The planted tables'
%% count of a load's terms is this one (planted_table_ffi).
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

%% Returns when the process has ended, at once if it has.
wait_until_dead(Pid) ->
    Monitor = erlang:monitor(process, Pid),
    receive
        {'DOWN', Monitor, process, Pid, _Reason} -> nil
    end.
