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

-module(data_platform_service_config).
-export([assign_service_config/4,
         check_ports/4
        ]).

assign_service_config(Service, Config, _Definition, _Attributes) ->
    lists:foreach(fun({Key, Val}) ->
                          data_platform_global_state:set_service_attribute(Service, Key, Val)
                  end, Config),
    true.

%% This isn't used for the demo.
check_ports(Service, Definition, Attributes, _State) ->
    case proplists:get_value(ports, Definition) of
        undefined ->
            true;
        Ports ->
            Missing = [Port || Port <- Ports,
                               check_port(Attributes, Service, Port) == false],
            case Missing of
                [] ->
                    true;
                _ ->
                    lager:info("Missing ports: ~p", [Missing]),
                    assign_ports(Service, Missing),
                    false
            end
    end.

%%%===================================================================
%% Internal Functions
%%%===================================================================

check_port(Attributes, Service, Port) ->
    case data_platform_state:get_service_attribute(Attributes, Service, {port, Port}) of
        {ok, _} ->
            true;
        _ ->
            false
    end.

assign_ports(Service, PortNames) ->
    Ports = find_ports(length(PortNames)),
    Assignments = lists:zip(PortNames, Ports),
    _ = [data_platform_global_state:set_service_attribute(Service, {port, Name}, Port)
         || {Name, Port} <- Assignments],
    ok.

find_ports(N) ->
    %% TODO: Make port starting/ending range configurable
    find_ports(N, 5000, []).

find_ports(0, _Port, Ports) ->
    lists:reverse(Ports);

find_ports(N, Port, Ports) ->
    case test_port(Port) of
        true ->
            find_ports(N-1, Port+1, [Port|Ports]);
        false ->
            find_ports(N, Port+1, Ports)
    end.

test_port(Port) ->
    case gen_tcp:listen(Port, []) of
        {ok, Socket} ->
            ok = gen_tcp:close(Socket),
            true;
        _ ->
            false
    end.
