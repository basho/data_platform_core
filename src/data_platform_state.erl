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

-module(data_platform_state).

-export([services/2,
         service_nodes/2,
         group_services/2,
         group_services/3,
         get_service_attribute/3,
         get_service_attributes/2
        ]).

services(AllServices, Node) ->
    [Service || Service={_Group, _Name, ServiceNode} <- AllServices,
                ServiceNode == Node].

service_nodes(AllServices, Service) ->
    NodesWithService = [Node || {_Group, Name, Node} <- AllServices, Name =:= Service],
    lists:usort(NodesWithService).

group_services(AllServices, Group) ->
    [Service || Service={ServiceGroup, _Name, _ServiceNode} <- AllServices,
                ServiceGroup == Group].

group_services(AllServices, Group, Name) ->
    [Service || Service={ServiceGroup, ServiceName, _ServiceNode} <- AllServices, 
                ServiceGroup == Group,
                ServiceName == Name].

get_service_attribute(Attributes, Service, Key) ->
    case orddict:find(Service, Attributes) of
        {ok, NodeAttributes} ->
            case orddict:find(Key, NodeAttributes) of
                {ok, Value} ->
                    {ok, Value};
                _ ->
                    {error, attribute_notfound}
            end;
        _ ->
            {error, service_notfound}
    end.

get_service_attributes(Attributes, Service) ->
    case orddict:find(Service, Attributes) of
        {ok, ServiceAttributes} ->
            {ok, ServiceAttributes};
        _ ->
            {error, service_notfound}
    end.
