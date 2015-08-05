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

-module(data_platform_global_state).

%% Exported internal callback functions
-export([do_handle_call/3, 
         do_handle_cast/3]).

%% API
-export([add_service_config/4,
	 remove_service/1,
	 services/0,
	 start_service/3,
	 stop_service/3,
	 set_service_attribute/3,
	 remove_service_attribute/1,
	 send_tick/0]).

-export([get_state/0,
         get_service_attributes/0,
         clear_state/0]). %% DEV/DEBUG Use

%% Types
-type group_name() :: string().
-type config_name() :: string().
-type service_type() :: string().
-type service_config() :: [{string(), string()}].

-type service() :: {group_name(), config_name(), node()}.
-type package() :: {config_name(), service_type(), service_config()}.

%% There should actually be exactly one of each of these elements in the proplist
%% that makes up our global state, but there might also be additional stuff added
%% in in a future version, so this type spec is more of a hint than a rigid spec.
%% It should (may?) still be helpful for dialyzer though, even if it's "incomplete".
-type state() :: [{active_services, ordsets:ordset(service())} |
                  {service_packages, ordsets:ordset(package())} |
                  {service_attributes, orddict:orddict(string(), string())} |
                  {last_error, atom() | undefined}
                 ].

%%%===================================================================
%%% API
%%%===================================================================

-spec add_service_config(config_name(), service_type(), service_config(), boolean()) ->
    ok | {error, _}.
add_service_config(ConfigName, ServiceType, Config, ForceReplaceExisting) ->
    call({add_service_config, ConfigName, ServiceType, Config, ForceReplaceExisting}).

%% This is a tricky one, because it can leave orphaned services.
-spec remove_service(config_name()) -> ok | {error, _}.
remove_service(ConfigName) ->
    call({remove_service, ConfigName}).

-spec start_service(group_name(), config_name(), node()) -> ok | {error, _}.
start_service(Group, ConfigName, Node) ->
    call({start_service, Group, ConfigName, Node}).

-spec stop_service(group_name(), config_name(), node()) -> ok | {error, _}.
stop_service(Group, ConfigName, Node) ->
    call({stop_service, Group, ConfigName, Node}).

-spec services() -> {[service()], [package()]} | {error, atom()}.
services() ->
    case get_state() of
        {ok, State} ->
            {active_services(State), service_packages(State)};
        Error ->
            {error, Error}
    end.

clear_state() ->
    riak_ensemble_peer:kdelete(node(), root, platform_state, 5000).

get_state() ->
    Result = riak_ensemble_peer:kget(node(), root, platform_state, 5000),
    case Result of
        {ok, Obj} ->
            case riak_ensemble_basic_backend:obj_value(Obj) of
                notfound ->
                    {ok, default_state()};
                State ->
                    {ok, State}
            end;
        Error ->
            Error
    end.

-spec get_service_attributes() -> [{term(), term()}].
get_service_attributes() ->
    {ok, State} = get_state(),
    AttributeDict = service_attributes(State),
    orddict:to_list(AttributeDict).

-spec send_tick() -> _.
send_tick() ->
    cast(tick).


-spec set_service_attribute(service(), term(), term()) -> ok | {error, _}.
set_service_attribute(Service, Key, Value) ->
    call({set_service_attribute, Service, Key, Value}).

-spec remove_service_attribute(service()) -> ok | {error, _}.
remove_service_attribute(Service) ->
    call({remove_service_attribute, Service}).

%%%===================================================================

call(Cmd) ->
    call(node(), Cmd, 5000).

call(Node, Cmd, Timeout) ->
    Default = default_state(),
    Result = riak_ensemble_peer:kmodify(Node,
                                        root,
                                        platform_state,
                                        {?MODULE, do_handle_call, Cmd},
                                        Default,
                                        Timeout),
    case Result of
        {ok, StateObj} ->
            State = riak_ensemble_basic_backend:obj_value(StateObj),
            case last_error(State) of
                undefined ->
                    ok;
                Error ->
                    {error, Error}
            end;
        Error ->
            {error, Error}
    end.

cast(Cmd) ->
    cast(node(), Cmd).

cast(Node, Cmd) ->
    cast(Node, root, Cmd).

cast(Node, Target, Cmd) ->
    Default = default_state(),
    spawn(fun() ->
                  riak_ensemble_peer:kmodify(Node,
                                             Target,
                                             platform_state,
                                             {?MODULE, do_handle_cast, Cmd},
                                             Default,
                                             5000)
          end),
    ok.

do_handle_call(Seq, State, Cmd) ->
    State2 = state_set(last_error, undefined, State),
    handle_call(Cmd, Seq, State2).

do_handle_cast(Seq, State, Cmd) ->
    handle_cast(Cmd, Seq, State).

%%%===================================================================

-spec default_state() -> state().
default_state() ->
    [{active_services, ordsets:new()},
     {service_packages, ordsets:new()},
     {service_attributes, orddict:new()},
     {last_error, undefined}].

active_services(State) ->
    get_state_val(active_services, State).
service_packages(State) ->
    get_state_val(service_packages, State).
service_attributes(State) ->
    get_state_val(service_attributes, State).
last_error(State) ->
    get_state_val(last_error, State).

get_state_val(Key, State) ->
    case lists:keyfind(Key, 1, State) of
        false ->
            undefined;
        {Key, Val} ->
            Val
    end.

%%state_set(Values, State) when is_list(Values) ->
    %%lists:foldl(fun state_set/2, State, Values);
%%state_set({Key, Val}, State) ->
    %%state_set(Key, Val, State).

state_set(Key, Val, State) ->
    lists:keystore(Key, 1, State, {Key, Val}).

%%%===================================================================

handle_call({add_service_config, ConfigName, ServiceType, Config, ForceReplaceExisting},
            _Vsn, State) ->
    NewPackage = {ConfigName, ServiceType, Config},
    Packages = service_packages(State),
    case lists:keyfind(ConfigName, 1, Packages) of
        false ->
            NewPackages = ordsets:add_element(NewPackage, Packages),
            state_set(service_packages, NewPackages, State);
        ExistingConfig when ForceReplaceExisting =:= true ->
            Packages2 = ordsets:del_element(ExistingConfig, Packages),
            Packages3 = ordsets:add_element(NewPackage, Packages2),
            state_set(service_packages, Packages3, State);
        _ExistingConfig ->
            state_set(last_error, config_already_exists, State)
    end;

handle_call({remove_service, ConfigName}, _Vsn, State) ->
    Packages = service_packages(State),
    Services = active_services(State),

    case lists:keyfind(ConfigName, 2, Services) of
        false ->
            case lists:keyfind(ConfigName, 1, Packages) of
                false ->
                    state_set(last_error, config_not_found, State);
                OldPackage ->
                    NewPackages = ordsets:del_element(OldPackage, Packages),
                    state_set(service_packages, NewPackages, State)
            end;
        _ ->
            state_set(last_error, config_in_use, State)
    end;

handle_call({start_service, Group, ConfigName, Node}, _Vsn, State) ->
    Services = active_services(State),
    Packages = service_packages(State),

    ConfigDef = [Package || Package={Name, _ServiceType, _Config} <- Packages,
                             Name == ConfigName],

    case ConfigDef of
        [] ->
            state_set(last_error, config_not_found, State);
        _ ->
            NewService = {Group, ConfigName, Node},
            case ordsets:is_element(NewService, Services) of
                false ->
                    NewServices = ordsets:add_element(NewService, Services),
                    state_set(active_services, NewServices, State);
                true ->
                    state_set(last_error, already_running, State)
            end
    end;

handle_call({stop_service, Group, ConfigName, Node}, _Vsn, State) ->
    Services = active_services(State),

    shutdown_service({Group, ConfigName, Node}),
    OldService = {Group, ConfigName, Node},

    case ordsets:is_element(OldService, Services) of
        false ->
            state_set(last_error, service_not_found, State);
        true ->
            NewServices = ordsets:del_element(OldService, Services),
            state_set(active_services, NewServices, State)
    end;

handle_call({set_service_attribute, Service, Key, Value}, _Vsn, State) ->
    Attributes = service_attributes(State),

    Default = orddict:store(Key, Value, orddict:new()),
    NewAttributes = orddict:update(Service,
                                   fun(ServiceAttributes) ->
                                           orddict:store(Key, Value, ServiceAttributes)
                                   end,
                                   Default,
                                   Attributes),

    state_set(service_attributes, NewAttributes, State);

handle_call({remove_service_attribute, Service}, _Vsn, State) ->
    Attributes = service_attributes(State),
    NewAttributes = orddict:erase(Service, Attributes),
    state_set(service_attributes, NewAttributes, State);

handle_call(_Msg, _Vsn, _State) ->
    failed.

handle_cast(tick, _Vsn, State) ->
    tick(State),
    failed;

handle_cast(_Msg, _Vsn, _State) ->
    failed.

%%%===================================================================

tick(State) ->
    Services = active_services(State),
    Packages = service_packages(State),
    Attributes = service_attributes(State),
    plumtree_metadata:put({data_platform, state}, services, Services),
    plumtree_metadata:put({data_platform, state}, service_packages, Packages),
    plumtree_metadata:put({data_platform, state}, service_attributes, Attributes).

shutdown_service(Service = {_Group, _ConfigName, Node})
  when Node =:= node() ->
    lager:debug("Stopping service ~p on local node", [Service]),
    spawn(fun() ->
                  data_platform_service_sup:stop_service(Service)
          end),
    ok;
shutdown_service(Service = {_Group, _ConfigName, Node}) ->
    lager:debug("Stopping service ~p on remote node ~p", [Service, Node]),
    rpc:cast(Node, data_platform_service_sup, stop_service, [Service]),
    ok.
