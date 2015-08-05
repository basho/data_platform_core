-module(data_platform_service_sup_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%% @ignore
%% Try starting a non-existing service, make sure SM survives
enoexist_test() ->
    NoFile = "nexistepas",
    false = filelib:is_file(NoFile),
    ServiceName = "enoexist_test",
    ForTearDown = setup(),
    ExistingServices0 = data_platform_service_sup:services(),
    {error, _Reason} =
        data_platform_service_sup:start_service(
          ServiceName, NoFile, []),
    ExistingServices1 = data_platform_service_sup:services(),
    ?assertEqual(ExistingServices0, ExistingServices1),
    teardown(ForTearDown).

-define(SCRIPT, "../test/dummy.escript").
%% these defines must match those in ../test/dummy.escript
-define(VAR1, "shambler").
-define(VAL1, "100").
-define(ENV, [{?VAR1, ?VAL1}]).
-define(PORT, 5658).
-define(GET_PRECIOUS, <<"get precious">>).

%% @ignore
%% Check start/stop of a service by SM
simple_start_test() ->
    true = filelib:is_file(?SCRIPT),
    ServiceName = "simple_start_test",
    ForTearDown = setup(),
    Got = data_platform_service_sup:start_service(ServiceName, ?SCRIPT, []),
    ?assertMatch({ok, _Pid}, Got),
    {ok, Pid} = Got,
    ?assert(is_pid(Pid)),
    ok = data_platform_service_sup:stop_service(ServiceName),
    teardown(ForTearDown).

%% @ignore
%% Start a service with a precious var in its env, check it is seen
%% from there
comm_env_test() ->
    true = filelib:is_file(?SCRIPT),
    ServiceName = "comm_env_test",
    ForTearDown = setup(),
    {ok, _Pid} =
        data_platform_service_sup:start_service(
          ServiceName, ?SCRIPT, [{env, ?ENV}]),
    Precious = get_service_env(),
    ?assertEqual(Precious, ?VAL1),
    ok = data_platform_service_sup:stop_service(ServiceName),
    teardown(ForTearDown).

get_service_env() ->
    {ok, Socket} = gen_udp:open(0, [binary, {active, true}]),
    ok = gen_udp:send(Socket, "127.0.0.1", ?PORT, ?GET_PRECIOUS),
    Env = recv_loop(Socket),
    ok = gen_udp:close(Socket),
    Env.
recv_loop(Socket) ->
    receive
        {udp, Socket, _Localhost, ?PORT, Env} ->
            binary_to_list(Env);
        Garbage ->
            ?debugFmt("Not expecting this spurious message: ~p\b", [Garbage]),
            ?assert(false)
    after 2 ->
            ?debugFmt("No response from process\b", []),
            []
    end.


start_redis_test() ->
    Redis = "../priv/redis/bin/redis-server",
    maybe_redis_test(filelib:is_file(Redis), Redis).

maybe_redis_test(false, _File) ->
    ?debugMsg("Skipping redis test as it's not installed."),
    skipped;

maybe_redis_test(true, Redis) ->
    ForTearDown = setup(),
    Self = self(),
    Got = data_platform_service_sup:start_service("redis", Redis, [{stdout, Self}]),
    ?assertMatch({ok, _SupBridgePid}, Got),
    {ok, SupBridgePid} = Got,
    %% The start_service call returns the pid of the supervisor bridge being used to run
    %% the erlexec process that's running the actual OS process. This next bit of code
    %% is the best way I've been able to come up with for extracting the relevant pid.
    %% It's ugly, but...c'est la vie in this case :(
    %% The pattern match is more specific than it really needs to be, but I'd rather
    %% fail fast in the event that this undocumented state structure ever changes.
    {state, data_platform_service, ErlExecPid, _,
     {SupBridgePid, data_platform_service}} = sys:get_state(SupBridgePid),
    OsPid = exec:ospid(ErlExecPid),
    ok = ?debugFmt("Consuming for ~p", [OsPid]),
    _ = consume_stdout(OsPid),
    PingRes = os:cmd("../priv/redis/bin/redis-cli ping"),
    ?assertEqual("PONG\n", PingRes),
    teardown(ForTearDown).

% This is here for a naive attempt to avoid race conditions. A prime example
% is redis. In attmpting to ensure that redis is up and running, a ping is
% attempted. However, if the ping is tried too soon, redis' listen port will
% not be open, thus getting a false failure. By waiting until there's a gap
% in the stdout data, we can reliably try the ping.
consume_stdout(OsPid) ->
    receive
        {stdout, OsPid, _Data} ->
            consume_stdout(OsPid)
    after
        10 ->
            ok
    end.

setup() ->
    _ = application:ensure_all_started(exec),
    {ok, Pid} = data_platform_service_sup:start_link(),
    Pid.

teardown(SupPid) ->
    IdKids = data_platform_service_sup:services(),
    % if we don't wait for the kids, exec ends up killing the test process.
    % this will wait only as long as needed, as opposed to a timer:sleep/1
    % call, so yays there.
    Kids = [Pid || {_Id, Pid} <- IdKids],
    _ = unlink(SupPid),
    exit_anad_wait([SupPid | Kids], shutdown).

exit_anad_wait(Pids, Why) ->
    MonPids = lists:map(fun(Pid) ->
        _ = unlink(Pid),
        Mon = erlang:monitor(process, Pid),
        _ = exit(Pid, Why),
        {Mon, Pid}
    end, Pids),
    lists:foreach(fun({Mon, Pid}) ->
        receive
            {'DOWN', Mon, process, Pid, _} ->
                ok
        end
    end, MonPids).

-endif.
