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

-module(data_platform_console).
-compile(export_all).

-behavior(clique_handler).
-export([register_cli/0]).

-define(CMD, "data-platform-admin").

-spec start() -> ok.
start() ->
    application:set_env(data_platform, standalone, true),
    ok = application:start(data_platform).

-spec register_cli() -> ok.
register_cli() ->
    register_cli_usage(),
    register_cli_cmds(),
    ok.

-spec console([string()]) -> ok | {error, term()}.
console(Cmd) ->
    clique:run(Cmd).

register_cli_cmds() ->
    lists:foreach(fun(Args) -> apply(clique, register_command, Args) end,
                  [join_register(),
                   leave_register(),
                   cluster_status_register(),
                   add_service_config_register(),
                   remove_service_config_register(),
                   start_service_register(),
                   stop_service_register(),
                   services_register(),
                   node_services_register(),
                   service_nodes_register()
                  ]).

join_register() ->
    [
     [?CMD, "join", '*'], %% Cmd
     [],                  %% KeySpecs
     [],                  %% FlagSpecs
     fun join/3           %% Callback
    ].

leave_register() ->
    [
     [?CMD, "leave"], %% Cmd
     [],              %% KeySpecs
     [],              %% FlagSpecs
     fun leave/3       %% Callback
    ].

cluster_status_register() ->
    [
     [?CMD, "cluster-status"], %% Cmd
     [],                          %% KeySpecs
     [],                          %% FlagSpecs
     fun cluster_status/3         %% Callback
    ].

add_service_config_register() ->
    ForceFlag = {force, [{shortname, "f"}, {longname, "force"}]},
    [
     [?CMD, "add-service-config", '*', '*'], %% Cmd
     '_',                                    %% KeySpecs
     [ForceFlag],                            %% FlagSpecs
     fun add_service_config/3                %% Callback
    ].

remove_service_config_register() ->
    [
     [?CMD, "remove-service-config", '*'], %% Cmd
     [],                            %% KeySpecs
     [],                            %% FlagSpecs
     fun remove_service_config/3           %% Callback
    ].

start_service_register() ->
    IpFlag = {output_ip, [{shortname, "i"}, {longname, "output-ip"}]},
    PortFlag = {output_port, [{shortname, "p"}, {longname, "output-port"}]},
    [
     [?CMD, "start-service", '*', '*', '*'], %% Cmd
     [],                                     %% KeySpecs
     [IpFlag, PortFlag],                     %% FlagSpecs
     fun start_service/3                     %% Callback
    ].

stop_service_register() ->
    [
     [?CMD, "stop-service", '*', '*', '*'], %% Cmd
     [],                                    %% KeySpecs
     [],                                    %% FlagSpecs
     fun stop_service/3                     %% Callback
    ].

services_register() ->
    [
     [?CMD, "services"], %% Cmd
     [],                 %% KeySpecs
     [],                 %% FlagSpecs
     fun services/3      %% Callback
    ].

node_services_register() ->
    [
     [?CMD, "node-services", '*'], %% Cmd
     [],                           %% KeySpecs
     [],                           %% FlagSpecs
     fun node_services/3           %% Callback
    ].

service_nodes_register() ->
    [
     [?CMD, "service-nodes", '*'], %% Cmd
     [],                           %% KeySpecs
     [],                           %% FlagSpecs
     fun service_nodes/3           %% Callback
    ].

join([?CMD, "join", NodeStr], [], []) ->
    case list_to_existing_node(NodeStr) of
        Err = {error, _} ->
            Err;
        Node when Node =:= node() ->
            alert([clique_status:text("Cannot join a node to itself")]);
        Node ->
            case check_riak_node(Node) of
                true ->
                    case riak_ensemble_manager:join(Node, node()) of
                        ok ->
                            [clique_status:text("Node joined")];
                        remote_not_enabled ->
                            Output = ["Ensemble not enabled on node ", NodeStr],
                            alert([clique_status:text(Output)]);
                        Error ->
                            Output = io_lib:format("Join failed! Reason: ~p", [Error]),
                            alert([clique_status:text(Output)])
                    end;
                false ->
                    alert([clique_status:text([NodeStr, " is not a Riak node"])])
            end
    end.

leave([?CMD, "leave"], [], []) ->
    case maybe_leave() of
        ok ->
            [clique_status:text("Node successfully removed")];
        {error, riak_cluster_member} ->
            Output = ["This node is a member of a Riak cluster.\n",
                      "Please remove it from the cluster using\n",
                      "the riak-admin cluster commands instead.\n"],
            alert([clique_status:text(Output)]);
        {error, services_running} ->
            Output = ["There are still services running on this node!\n",
                      "Please stop them before removing this node from the cluster.\n"],
            alert([clique_status:text(Output)]);
        Error ->
            Output = io_lib:format("Unable to leave cluster! Reason: ~p", [Error]),
            alert([clique_status:text(Output)])
    end.

maybe_leave() ->
    case is_riak_cluster_member() of
        true ->
            {error, riak_cluster_member};
        false ->
            case data_platform_global_state:services() of
                Err = {error, _} ->
                    Err;
                {RunningServices, _Packages} ->
                    IsLocal = fun({_GroupName, _ConfigName, Node}) -> Node =:= node() end,
                    case lists:any(IsLocal, RunningServices) of
                        true ->
                            {error, services_running};
                        false ->
                            do_leave()
                    end
            end
    end.

is_riak_cluster_member() ->
    {ok, Ring} = riak_core_ring_manager:get_my_ring(),
    Members = riak_core_ring:all_members(Ring),
    length(Members) > 1.

do_leave() ->
    RootLeader = riak_ensemble_manager:rleader_pid(),
    case riak_ensemble_peer:update_members(RootLeader, [{del, {root, node()}}], 10000) of
        ok ->
            case wait_for_root_leave(30) of
                ok ->
                    NewRootLeader = riak_ensemble_manager:rleader_pid(),
                    case riak_ensemble_manager:remove(node(NewRootLeader), node()) of
                        ok ->
                            ok;
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        Error ->
                Error
    end.

wait_for_root_leave(Timeout) ->
    wait_for_root_leave(0, Timeout).

wait_for_root_leave(RetryCount, RetryLimit) when RetryCount =:= RetryLimit ->
    {error, timeout_waiting_to_leave_root_ensemble};
wait_for_root_leave(RetryCount, RetryLimit) ->
    case in_root_ensemble(node()) of
        true ->
            timer:sleep(1000),
            wait_for_root_leave(RetryCount + 1, RetryLimit);
        false ->
            ok
    end.

in_root_ensemble(Node) ->
    RootNodes = [N || {root, N} <- riak_ensemble_manager:get_members(root)],
    lists:member(Node, RootNodes).

cluster_status([?CMD, "cluster-status"], [], []) ->
    case riak_ensemble_manager:enabled() of
        false ->
            Output = ["Strong consistency is not enabled on this node.\n",
                      "To create a Data Platform cluster, strong consistency must first be enabled."
                     ],
            alert([clique_status:text(Output)]);
        true ->
            HeaderStr = ["--- Cluster Status ---\n",
                         "Strong Consistency: enabled\n"],
            Header = clique_status:text(HeaderStr),
            Nodes = lists:sort(riak_ensemble_manager:cluster()),
            LeaderNode = node(riak_ensemble_manager:get_leader_pid(root)),
            LeaderAnnotation = fun(N) ->
                                       case N of
                                           LeaderNode -> true;
                                           _ -> ""
                                       end
                               end,
            NodeTableData = [[{"Node", N}, {"Leader", LeaderAnnotation(N)}] || N <- Nodes],
            NodeTable = clique_status:table(NodeTableData),
            [Header, NodeTable]
    end.

-define(VALID_SERVICES, ["redis", "cache-proxy", "spark-worker", "spark-master"]).

add_service_config([?CMD, "add-service-config", ConfigName, ServiceType], Config, Flags) ->
    ForceReplaceExisting = case Flags of
                               [] -> false;
                               [{force, _}] -> true
                           end,
    case lists:member(ServiceType, ?VALID_SERVICES) of
        true ->
            case data_platform_global_state:add_service_config(ConfigName, ServiceType, Config, ForceReplaceExisting) of
                ok ->
                    [clique_status:text("Service configuration added")];
                {error, config_already_exists} ->
                    Output1 = "Unable to add service config - configuration name already in use\n",
                    Output2 = "Use -f or --force to overwrite any existing config with that name",
                    alert([clique_status:text([Output1, Output2])]);
                {error, Error} ->
                    Output = io_lib:format("Add service configuration failed! Reason: ~p", [Error]),
                    alert([clique_status:text(Output)])
            end;
        false ->
            alert([clique_status:text(["Invalid service \"", ServiceType, "\""])])
    end.

remove_service_config([?CMD, "remove-service-config", ConfigName], [], []) ->
    case data_platform_global_state:remove_service(ConfigName) of
        ok ->
            [clique_status:text("Service configuration removed")];
        {error, config_not_found} ->
            Output = ["Unable to find any existing service configuration named \"",
                      ConfigName, "\""],
            alert([clique_status:text(Output)]);
        {error, config_in_use} ->
            Output = "Oops! It appears this configuration is currently in use by a running service",
            alert([clique_status:text(Output)]);
        {error, Error} ->
            Output = io_lib:format("Failed to remove service configuration ~p! Reason: ~p", [ConfigName, Error]),
            alert([clique_status:text([Output])])
    end.

start_service([?CMD, "start-service", NodeStr, Group, ConfigName], [], Flags) ->
    case clique_typecast:to_node(NodeStr) of
        Err = {error, _} ->
            Err;
        Node ->
            case data_platform_global_state:start_service(Group, ConfigName, Node) of
                ok ->
                    case Flags of
                        [] ->
                            [clique_status:text("Service started")];
                        _ ->
                            AddrOutput = case lists:keyfind(output_ip, 1, Flags) of
                                           false -> "";
                                           _ -> [get_service_host(NodeStr), "\n"]
                                       end,
                            PortOutput = case lists:keyfind(output_port, 1, Flags) of
                                             false -> "";
                                             _ -> [get_service_port(ConfigName), "\n"]
                                         end,
                            [clique_status:text([AddrOutput, PortOutput])]
                    end;
                {error, config_not_found} ->
                    Output = ["Unable to start service - configuration \"",
                              ConfigName, "\" does not exist"],
                    alert([clique_status:text(Output)]);
                {error, already_running} ->
                    Output = [Group, "/", ConfigName, " already running on node ", NodeStr, "!"],
                    alert([clique_status:text(Output)]);
                {error, Error} ->
                    Output = io_lib:format("Failed to start service! Reason: ~p", [Error]),
                    alert([clique_status:text([Output])])
            end
    end.

get_service_host(NodeStr) ->
    [_AtChar | Host] = lists:dropwhile(fun(C) -> C =/= $@ end, NodeStr),
    {ok, Addr} = inet:getaddr(Host, inet),
    inet:ntoa(Addr).

get_service_port(ConfigName) ->
    %% This is definitely hacky, but we have no standardized way of configuring a services port,
    %% so we need to check the configuration differently for each different service we support.
    %% If we want to support arbitrary custom services, we'll need to come up with some sort
    %% of standardized way of handling this kind of thing, but for now it should be okay to punt
    %% on it.
    {_, Packages} = data_platform_global_state:services(),
    case lists:keyfind(ConfigName, 1, Packages) of
        false ->
            "-1";
        {ConfigName, ServiceType, ServiceConfig} ->
            NormalizedConfig = [{string:to_upper(K), V} || {K, V} <- ServiceConfig],
            case ServiceType of
                "redis" ->
                    proplists:get_value("REDIS_PORT", NormalizedConfig, "6379");
                "cache-proxy" ->
                    proplists:get_value("CACHE_PROXY_PORT", NormalizedConfig, "22122");
                "spark-master" ->
                    proplists:get_value("SPARK_MASTER_PORT", NormalizedConfig, "7077");
                "spark-worker" ->
                    proplists:get_value("SPARK_WORKER_PORT", NormalizedConfig, "7078")
            end
    end.

stop_service([?CMD, "stop-service", NodeStr, Group, ConfigName], [], []) ->
    case clique_typecast:to_node(NodeStr) of
        Err = {error, _} ->
            Err;
        Node ->
            case data_platform_global_state:stop_service(Group, ConfigName, Node) of
                ok ->
                    [clique_status:text("Service stopped")];
                {error, service_not_found} ->
                    Output = [Group, "/", ConfigName, " is not running on node ", NodeStr, "!"],
                    alert([clique_status:text(Output)]);
                {error, Error} ->
                    Output = io_lib:format("Failed to stop service ~p! Reason: ~p",
                                           [ConfigName, Error]),
                    alert([clique_status:text([Output])])
            end
    end.

services(_, [], []) ->
    RunningServices = plumtree_metadata:get({data_platform, state}, services, [{default, []}]),
    Packages = plumtree_metadata:get({data_platform, state}, service_packages, [{default, []}]),

    RunHeader = clique_status:text("Running Services:"),
    RunTableData = [[{"Group", Group}, {"Service", Name}, {"Node", Node}] ||
                    {Group, Name, Node} <- RunningServices],
    RunTable = clique_status:table(RunTableData),

    AvailableHeader = clique_status:text("Available Services:"),
    AvailableTableData = [[{"Service", Name}, {"Type", Type}] ||
                          {Name, Type, _} <- Packages],
    AvailableTable = clique_status:table(AvailableTableData),
    [RunHeader, RunTable, AvailableHeader, AvailableTable].

%% There are two kinds of 'services' to list.
%% The services on the specified node and the services
%% available in the global state.
%% For now, these are the same thing.
node_services([?CMD, "node-services", NodeStr], [], []) ->
    case clique_typecast:to_node(NodeStr) of
        Err = {error, _} ->
            Err;
        Node ->
            AllServices = plumtree_metadata:get({data_platform, state}, services, [{default, []}]),
            case data_platform_state:services(AllServices, Node) of
                [] ->
                    [clique_status:text("No services\n")];
                Services ->
                    Header = clique_status:text(["Services running on node ", NodeStr, ":"]),
                    ServiceTableData = [[{"Group", Group}, {"Service", Name}, {"Node", ServiceNode}]
                                        || {Group, Name, ServiceNode} <- Services],
                    ServiceTable = clique_status:table(ServiceTableData),
                    [Header, ServiceTable]
            end
    end.

service_nodes([?CMD, "service-nodes", ConfigName], [], []) ->
    AllServices = plumtree_metadata:get({data_platform, state}, services, [{default, []}]),
    Nodes = data_platform_state:service_nodes(AllServices, ConfigName),
    case Nodes of
        [] ->
            [clique_status:text(["No nodes running service config \"", ConfigName, "\""])];
        _ ->
            NodeStrings = lists:map(fun atom_to_list/1, Nodes),
            [clique_status:list("Nodes Running Service", NodeStrings)]
    end.

register_cli_usage() ->
    clique:register_usage([?CMD], base_usage()),
    clique:register_usage([?CMD, "join"], join_usage()),
    clique:register_usage([?CMD, "leave"], leave_usage()),
    clique:register_usage([?CMD, "cluster-status"], cluster_status_usage()),
    clique:register_usage([?CMD, "add-service-config"], add_service_config_usage()),
    clique:register_usage([?CMD, "remove-service-config"], remove_service_config_usage()),
    clique:register_usage([?CMD, "start-service"], start_service_usage()),
    clique:register_usage([?CMD, "stop-service"], stop_service_usage()),
    clique:register_usage([?CMD, "services"], services_usage()),
    clique:register_usage([?CMD, "node-services"], node_services_usage()),
    clique:register_usage([?CMD, "service-nodes"], service_nodes_usage()).

base_usage() ->
    [
     "data-platform-admin <command>\n\n",
     "  Commands:\n",
     "    join                      Join a node to the Basho Data Platform cluster\n",
     "    leave                     Remove a node from the cluster\n",
     "    cluster-status            Display a summary of the status of nodes in the cluster\n",
     "    add-service-config        Add a new service to cluster\n",
     "    remove-service-config     Remove an existing service from the cluster\n",
     "    start-service             Start a service on an the designated platform instance\n",
     "    stop-service              Stop a service on the designated instance\n",
     "    services                  Display services available on the cluster\n",
     "    node-services             Display all running services for the given node\n",
     "    service-nodes             Display all instances running the designated service\n\n",
     "Use --help after a sub-command for more details.\n"
    ].

join_usage() ->
    [
     "data-platform-admin join <node>\n",
     " Join a node to the Basho Data Platform cluster\n"
    ].

leave_usage() ->
    [
     "data-platform-admin leave\n",
     " Remove a node from the Basho Data Platform cluster\n"
    ].

cluster_status_usage() ->
    [
     "data-platform-admin cluster-status\n",
     " Display a summary of the status of nodes in the cluster\n"
    ].

add_service_config_usage() ->
    [
     "data-platform-admin add-service-config <service-name> <service>\n",
     "                                        [-f | --force] [<service-configuration>]\n",
     " Add a new service configuration to cluster\n\n",
     " Valid services are: ",
     string:join(?VALID_SERVICES, ", "),
     "\n\n",
     " <service-configuration> is specified as key value pairs, e.g.\n",
     "   my_config=42 other_config=blub\n"
    ].

remove_service_config_usage() ->
    [
     "data-platform-admin remove-service-config <service>\n",
     " Remove an existing service configuration from the cluster\n"
    ].

start_service_usage() ->
    [
     "data-platform-admin start-service <node> <group> <service>\n",
     "                     [-i | --output-ip] [-p | --output-port]\n",
     " Start a service on an the designated platform instance\n\n",
     " The -i/--output-ip flag will cause the IP address of <node>\n",
     " to be printed back out on the console in lieu of the normal output.\n\n",
     " The -p/--output-port flag will similarly cause the configured port\n",
     " of the service to be printed out on the console.\n"
    ].

stop_service_usage() ->
    [
     "data-platform-admin stop-service <node> <group> <service>\n",
     " Stop a service on the designated instance\n"
    ].

services_usage() ->
    [
     "data-platform-admin services\n",
     " Display services available on the cluster\n"
    ].

node_services_usage() ->
    [
     "data-platform-admin node-services <node>\n",
     " Display all running services for the given node\n"
    ].

service_nodes_usage() ->
    [
     "data-platform-admin service-nodes <service>\n",
     " Display all nodes running the designated service\n"
    ].

alert(Status) ->
    {exit_status, 1, [clique_status:alert(Status)]}.

check_riak_node(Node) ->
    case net_adm:ping(Node) of
        pong ->
            case rpc:call(Node, erlang, whereis, [riak_core_sup]) of
                Pid when is_pid(Pid) ->
                    true;
                _ ->
                    false
            end;
        _ ->
            false
    end.

%% We can't use clique_typecast:to_node for the join command because that function
%% checks the string against existing nodes in the cluster, but when we're joining
%% a node it isn't in the cluster yet. Instead of checking whether there's a matching
%% node in the list of cluster members, we pull apart the node string into a name and
%% a host, and check what epmd can tell us about existing nodes at that host. Then
%% if we can confirm that the node actually exists, we can go ahead and convert to an
%% atom and return the result.
list_to_existing_node(NodeStr) ->
    {NodeName, AtNodeHost} = lists:splitwith(fun(C) -> C =/= $@ end, NodeStr),
    case AtNodeHost of
        [$@ | NodeHost] ->
            list_to_existing_node(NodeName, NodeHost, NodeStr);
        _ ->
            {error, bad_node}
    end.

list_to_existing_node(NodeName, NodeHost, NodeStr) ->
    case net_adm:names(NodeHost) of
        {ok, NodeList} ->
            case lists:keyfind(NodeName, 1, NodeList) of
                false ->
                    {error, bad_node};
                _ ->
                    list_to_atom(NodeStr)
            end;
        _ ->
            {error, bad_node}
    end.
