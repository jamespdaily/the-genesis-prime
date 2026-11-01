%% Finds where Erlang source calls or refers to named functions, read with
%% Erlang's own scanner, so comments, strings and whitespace are what the
%% compiler sees. Each target is {target, Module, Function}; it counts when
%% Function is qualified by Module, or unqualified when Module is erlang (an
%% auto-imported BIF), and is called (followed by `(`) or referred to as a fun
%% (followed by `/`). Gives the line of each, or the line where the text stops
%% scanning.
-module(erlang_calls_ffi).
-export([lines/2, qualifier_lines/2]).

%% The line of each place the text qualifies a name by a module whose name
%% starts with Prefix (`Prefix...:`), read with the same scanner; text that does
%% not scan gives the line where it stops.
qualifier_lines(Text, Prefix) ->
    Wanted = binary_to_list(Prefix),
    case erl_scan:string(unicode:characters_to_list(Text)) of
        {ok, Tokens, _End} -> qualifiers(Tokens, Wanted, []);
        {error, {Anno, _Module, _Reason}, _} -> [erl_anno:line(Anno)]
    end.

qualifiers([], _, Found) ->
    lists:reverse(Found);
qualifiers([{atom, Anno, Name}, {':', _} | Rest], Wanted, Found) ->
    Next = case lists:prefix(Wanted, atom_to_list(Name)) of
               true -> [erl_anno:line(Anno) | Found];
               false -> Found
           end,
    qualifiers(Rest, Wanted, Next);
qualifiers([_ | Rest], Wanted, Found) ->
    qualifiers(Rest, Wanted, Found).

lines(Text, Targets) ->
    Wanted = [{binary_to_atom(M), binary_to_atom(F)} || {target, M, F} <- Targets],
    case erl_scan:string(unicode:characters_to_list(Text)) of
        {ok, Tokens, _End} -> walk(Tokens, none, none, Wanted, []);
        {error, {Anno, _Module, _Reason}, _} -> [erl_anno:line(Anno)]
    end.

%% Before is the token just before the current one, BeforeThat the one before.
walk([], _, _, _, Found) ->
    lists:reverse(Found);
walk([{atom, Anno, Name} = Token | Rest], Before, BeforeThat, Wanted, Found) ->
    Counts = lists:member({module_of(Before, BeforeThat), Name}, Wanted)
        andalso called_or_referred(Rest),
    Next = case Counts of
               true -> [erl_anno:line(Anno) | Found];
               false -> Found
           end,
    walk(Rest, Token, Before, Wanted, Next);
walk([Token | Rest], Before, _BeforeThat, Wanted, Found) ->
    walk(Rest, Token, Before, Wanted, Found).

%% The module a name is qualified by; an unqualified name is erlang's.
module_of({':', _}, {atom, _, Module}) -> Module;
module_of({':', _}, _) -> none;
module_of(_, _) -> erlang.

called_or_referred([{'(', _} | _]) -> true;
called_or_referred([{'/', _} | _]) -> true;
called_or_referred(_) -> false.
