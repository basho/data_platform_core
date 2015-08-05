-module(data_platform_service).
-behavior(supervisor_bridge).

-export([start_link/2]).
-export([init/1, terminate/2]).


-define(STABILITY_TIME, 3000).

start_link(Exec, Options) ->
    supervisor_bridge:start_link(?MODULE, {Exec, Options}).

init({Exec, Options}) ->
    block_until_stable(Exec, Options).

terminate(_Why, OsPid) ->
    exec:stop(OsPid).

%% @ignore
% erl exec starts the process, and as long as the os can start it, exec sees 
% that as a success. However, services (like redis) can exit out shortly after
% starting, like if they try to bind to port already in use. If we just took
% the raw return from exec to supervisor, we would then get restarted, and
% likely result in hitting the restart intensity. So, we start as usual, but 
% catch any exits within the first few arbitrary length time segments. In short,
% we try to ensure the service we ask exec to start is 'stable'.
block_until_stable(Exec, Options) ->
    block_until_stable(exec:run_link(Exec, Options)).

block_until_stable({ok, Pid, OsPid} = Out) ->
    lager:info("Blocking..."),
    receive
        {'EXIT', Pid, Why} ->
            lager:warning("Failure to remain up for ~p ms", [?STABILITY_TIME]),
            {error, {Pid, OsPid, Why}}
    after
        ?STABILITY_TIME ->
            Out
    end.