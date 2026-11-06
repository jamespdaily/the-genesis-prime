-module(owned_key_ffi).
-export([new/0, own/2, left_behind/1, erase_left/1, terms_under/1, erase/1, wait_until_dead/1,
         loads_held/0, loads_held_limit/0, waiting_for_room/0, waited_ms/1]).

%% The references each process made, kept in a table that outlives the
%% processes: {Owner, Reference, Kind}. A body that crashes, is killed by a
%% linked process or runs past its deadline is dead when its terms are counted,
%% so a process dictionary would be gone with it.
-define(TABLE, owned_key_references).

%% What the keys wait for, {Key, Value} in one set: {{slot, N}, Pid} is the place
%% N among the loads held, {{admitting, Pid}, StartMs} a process inside admit/0,
%% {{waiting, Pid}, true} a process waiting for a place, and {{waited, Pid}, Ms}
%% what the process has waited in all. A process that is killed leaves its rows
%% behind, so a row counts only while its process lives.
-define(ADMISSION, owned_key_admission).

%% The most processes that hold a place among the loads at once. A process holds
%% one from its first key to its end (or erase_left/1).
-define(LOADS_HELD_LIMIT, 2).

%% A new reference, remembered as made by the calling process and to be erased
%% by it.
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
    ensure_table(),
    admit(),
    ets:insert(?TABLE, {self(), Reference, Kind}),
    ok.

loads_held_limit() ->
    ?LOADS_HELD_LIMIT.

%% What a key waits for before it is made: the literal area's released, and, for
%% a process that holds no place and is not making a shared load, a place among
%% the loads held (see owned_key.gleam). The time spent here is what
%% waited_ms/1 reports, so a test's deadline can leave it out.
admit() ->
    Start = erlang:monotonic_time(millisecond),
    ets:insert(?ADMISSION, {{admitting, self()}, Start}),
    try
        literal_area_ffi:wait_until_released(),
        case erlang:get(owned_key_unlimited) =:= true orelse holds_a_place(self()) of
            true -> ok;
            false -> take_a_place()
        end
    after
        ets:delete(?ADMISSION, {admitting, self()}),
        ets:update_counter(?ADMISSION, {waited, self()},
                           erlang:monotonic_time(millisecond) - Start,
                           {{waited, self()}, 0})
    end.

take_a_place() ->
    case try_to_take_a_place() of
        true ->
            ok;
        false ->
            ets:insert(?ADMISSION, {{waiting, self()}, true}),
            try
                literal_area_ffi:wait_until(fun try_to_take_a_place/0, fun describe_places/0)
            after
                ets:delete(?ADMISSION, {waiting, self()})
            end
    end.

describe_places() ->
    io_lib:format("waited ~p ms for a place among the loads; held by ~p",
                  [literal_area_ffi:wait_bound_ms(), places_held_by()]).

%% Takes the first free place, or one whose process has ended; one insert_new
%% decides between processes that ask at once.
try_to_take_a_place() ->
    lists:any(fun take_slot/1, lists:seq(1, ?LOADS_HELD_LIMIT)).

take_slot(Number) ->
    Key = {slot, Number},
    case ets:lookup(?ADMISSION, Key) of
        [{Key, Holder} = Row] ->
            case is_process_alive(Holder) of
                true ->
                    false;
                false ->
                    ets:delete_object(?ADMISSION, Row),
                    ets:insert_new(?ADMISSION, {Key, self()})
            end;
        [] ->
            ets:insert_new(?ADMISSION, {Key, self()})
    end.

holds_a_place(Pid) ->
    ets:match(?ADMISSION, {{slot, '_'}, Pid}) =/= [].

%% The processes that hold a place now.
places_held_by() ->
    [Pid || [Pid] <- ets:match(?ADMISSION, {{slot, '_'}, '$1'}), is_process_alive(Pid)].

%% How many processes hold a place among the loads now.
loads_held() ->
    ensure_table(),
    length(places_held_by()).

%% How many processes wait now for a place.
waiting_for_room() ->
    ensure_table(),
    length([Pid || [Pid] <- ets:match(?ADMISSION, {{waiting, '$1'}, true}), is_process_alive(Pid)]).

%% How many milliseconds the process has waited in admit/0 in all, the wait it is
%% in now included.
waited_ms(Pid) ->
    ensure_table(),
    Done = case ets:lookup(?ADMISSION, {waited, Pid}) of
               [{_, Ms}] -> Ms;
               [] -> 0
           end,
    Ongoing = case ets:lookup(?ADMISSION, {admitting, Pid}) of
                  [{_, Start}] -> erlang:monotonic_time(millisecond) - Start;
                  [] -> 0
              end,
    Done + Ongoing.

%% The tables are made by a process that stays for the life of the VM, by the
%% first caller; a caller that loses the race finds them made.
ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined ->
            Caller = self(),
            Made = make_ref(),
            spawn(fun() ->
                try
                    ets:new(?ADMISSION, [named_table, public, set, {write_concurrency, true}]),
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

%% The references a process made through new/0 and own/2, with their kinds.
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
%% kind, and forgets the owner's keys and its place among the loads.
erase_left(Owner) ->
    erase_each(stored_under([Reference || {Reference, _Kind} <- owned_by(Owner)])),
    case ets:whereis(?TABLE) of
        undefined ->
            ok;
        _ ->
            ets:delete(?TABLE, Owner),
            ets:match_delete(?ADMISSION, {{slot, '_'}, Owner}),
            ets:delete(?ADMISSION, {waited, Owner}),
            ets:delete(?ADMISSION, {admitting, Owner}),
            ets:delete(?ADMISSION, {waiting, Owner})
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
