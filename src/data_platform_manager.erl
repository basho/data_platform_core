%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(data_platform_manager).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {last_prefix_hash :: term()
               }).

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    schedule_tick(),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(tick, State) ->
    State2 = tick(State),
    schedule_tick(),
    {noreply, State2};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

schedule_tick() ->
    erlang:send_after(2000, self(), tick).

maybe_tick_global_state() ->
    case riak_ensemble_manager:enabled() of
        false ->
            ok;
        true ->
            Pid = riak_ensemble_manager:rleader_pid(),
            if is_pid(Pid), node(Pid) == node() ->
                   data_platform_global_state:send_tick(),
                   ok;
               true ->
                   ok
            end
    end.

tick(State) ->
    maybe_join_root_ensemble(),
    maybe_tick_global_state(),
    State2 = check_global_state(State),
    State2.

maybe_join_root_ensemble() ->
    case riak_ensemble_manager:enabled() of
        false ->
            ok;
        true ->
            CurrentMembers = riak_ensemble_manager:get_members(root),
            case lists:member({root, node()}, CurrentMembers) of
                true ->
                    ok;
                false ->
                    case riak_ensemble_manager:rleader_pid() of
                        undefined ->
                            ok;
                        Pid ->
                            riak_ensemble_peer:update_members(Pid, [{add, {root, node()}}], 10000)
                    end
            end
    end.

check_global_state(State=#state{last_prefix_hash=OldHash}) ->
    CurrentHash = plumtree_metadata:prefix_hash({data_platform, state}),
    case OldHash of
        CurrentHash ->
            State;
        _ ->
            reconcile_global_state(),
            State#state{last_prefix_hash=CurrentHash}
    end.

reconcile_global_state() ->
    Running = data_platform_service_sup:services(),
    AllServices = plumtree_metadata:get({data_platform, state}, services, [{default, []}]),
    Packages = plumtree_metadata:get({data_platform, state}, service_packages, [{default, []}]),
    Attributes = plumtree_metadata:get({data_platform, state}, service_attributes, [{default, []}]),

    case data_platform_state:services(AllServices, node()) of
        [] ->
            ok;
        Services ->
            Current = [{Service, true} || {Service, _} <- Running],
            Desired = [{Service, true} || Service <- Services],
            Delta = riak_ensemble_util:orddict_delta(lists:sort(Current),
                                                     lists:sort(Desired)),
            lists:foreach(fun({Service, Diff}) ->
                                case Diff of
                                    {'$none', _} ->
                                        maybe_start_service(Service, Packages, Attributes);
                                    {_, '$none'} ->
                                        lager:info("Removing Old Service ~p~n", [Service]),
                                        data_platform_service_sup:stop_service(Service)
                                end
                        end, Delta)
    end.

get_attributes_for_service(Service, Attributes) ->
    case lists:keyfind(Service, 1, Attributes) of
        false ->
            [];
        {Service, ServAttr} ->
            ServAttr
    end.

%% Right now, this is looking for ports, however this could include all kinds of service validation.
maybe_start_service(Service, PackageList, AllAttributes) ->
    %% ADd check here for existenz
    %% should remove?
    
    {_, ConfigName, _} = Service,
    case lists:keyfind(ConfigName, 1, PackageList) of
        false ->
            lager:warning("No such service config: ~p", [ConfigName]);
        {ConfigName, ServiceType, ServiceConfig} ->
            case sanity_check(ServiceType) of
                true ->
                    ServiceModule = data_platform_service_sup,
                    Definition = ServiceModule:app_definition(),

                    data_platform_service_config:assign_service_config(Service, ServiceConfig,
                                                                       Definition, AllAttributes),
                    ServiceAttributes = get_attributes_for_service(Service, AllAttributes),
                    add_service(Service, ServiceType, ServiceAttributes);
                false ->
                    lager:warning("Service does not exist locally: ~p", [Service])
            end
    end.

%%This is where the service attributes are added
    %% case data_platform_service_config:check_ports(Service, Definition, Attributes, State) of
    %% true ->
    %%     add_service(Service, State);
    %% false ->
    %%     io:format("~p: unable to start service: not all ports valid~n", [Service]),
    %%     State
    %% end.

add_service(Service, ServiceType, Attributes) ->
    lager:info("Adding New Service ~p ~p", [ServiceType, Service]),
    WorkingDir = code:priv_dir(data_platform) ++ "/" ++ ServiceType,
    ExecPath = WorkingDir ++ "/run.sh",
    Env = [{string:to_upper(Key), Value} || {Key, Value} <- Attributes, is_list(Key), is_list(Value)],
    RunAttributes = [
        {cd, WorkingDir},
        {env, Env},
        {stdout, whereis(data_platform_service_logger)}
    ],
    lager:info("Run attributes are ~p", [RunAttributes]),
    Out = data_platform_service_sup:start_service(Service, ExecPath, RunAttributes),
    lager:info("Result of trying to start the service: ~p", [Out]),
    Out.

sanity_check(ServiceType) ->
    ExecPath = code:priv_dir(data_platform) ++ "/" ++ ServiceType,
    filelib:is_dir(ExecPath).
