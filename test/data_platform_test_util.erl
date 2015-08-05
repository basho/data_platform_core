-module(data_platform_test_util).

-export([setup/0, teardown/0]).

setup() ->
    lager:info("starting setup~n"),
    application:load(crypto),
    application:load(riak_ensemble),
    os:cmd("rm -rf test-tmp"),
    application:set_env(riak_ensemble, data_root, "test-tmp"),
    {ok, _} = application:ensure_all_started(riak_ensemble),
    riak_ensemble_manager:enable(),
    Node = node(),
    [{root, Node}] = riak_ensemble_manager:get_members(root),
    wait_stable(root), 
    lager:info("setup complete~n"),
    ok.

teardown() ->
    application:stop(riak_ensemble).

wait_stable(Ensemble) ->
    case check_stable(Ensemble) of
        true ->
            ok;
        false ->
            wait_stable(Ensemble)
    end.

check_stable(Ensemble) ->
    case riak_ensemble_manager:check_quorum(Ensemble, 1000) of
        true ->
            case riak_ensemble_peer:stable_views(Ensemble, 1000) of
                {ok, true} ->
                    true;
                _Other ->
                    false
            end;
        false ->
            false
    end.
