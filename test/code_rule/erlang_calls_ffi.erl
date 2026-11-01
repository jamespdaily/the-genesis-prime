%% Finds where Erlang source calls or refers to named functions, read with
%% Erlang's own scanner, so comments, strings and whitespace are what the
%% compiler sees. Each target is {target, Module, Function}; it counts when
%% Function is qualified by Module, or unqualified when Module is erlang (an
%% auto-imported BIF), and is called (followed by `(`) or referred to as a fun
%% (followed by `/`). Gives the line of each, or the line where the text stops
%% scanning.
-module(erlang_calls_ffi).
-export([lines/2, atom_lines/2]).

%% The line of each atom the text writes that is Name or starts with Name and
%% an underscore (`pgo` and `pgo_pool_sup` for Name `pgo`), read with the same
%% scanner, so a comment or a string is not one; text that does not scan gives
%% the line where it stops.
atom_lines(Text, Name) ->
    Whole = binary_to_atom(Name),
    Prefix = binary_to_list(Name) ++ "_",
    case erl_scan:string(unicode:characters_to_list(Text)) of
        {ok, Tokens, _End} ->
            [erl_anno:line(Anno) || {atom, Anno, Atom} <- Tokens,
                                    Atom =:= Whole orelse
                                        lists:prefix(Prefix, atom_to_list(Atom))];
        {error, {Anno, _Module, _Reason}, _} -> [erl_anno:line(Anno)]
    end.

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
