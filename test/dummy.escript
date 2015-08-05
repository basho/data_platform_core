#! /usr/bin/env escript

-export([main/1]).

%% these defines must match those in ../src/data_platform_service_sup_tests.erl
-define(PORT, 5658).
-define(GET_PRECIOUS, <<"get precious">>).
-define(VAR1, "shambler").

main([]) ->
    {ok, Socket} = gen_udp:open(?PORT, [binary, {active, true}]),
    loop(Socket, ?PORT).

loop(Socket, ListenPort) ->
    receive
        {udp, Socket, _IP, _InPortNo, <<"stop ", _/binary>>} ->
            ok;
        {udp, Socket, _IP, _InPortNo, <<"crash ", Why/binary>>} ->
            halt(binary_to_integer(Why));
        {udp, Socket, IP, InPortNo, <<"echo ", What/binary>>} ->
            ok = gen_udp:send(Socket, IP, InPortNo, What),
            loop(Socket, ListenPort);
        {udp, Socket, IP, InPortNo, ?GET_PRECIOUS} ->
            Precious = list_to_binary(os:getenv(?VAR1)),
            ok = gen_udp:send(Socket, IP, InPortNo, Precious),
            loop(Socket, ListenPort)
    end.
