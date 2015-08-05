-module(data_platform_global_state_test).
-compile(export_all).
-include_lib("eunit/include/eunit.hrl").

-define(CONFIG_NAME, abcde).
-define(SERVICE, fake_service).
-define(SERVICE2, fake_service2).
-define(SERVICE_ATTR, [{fake_setting, 12345}]).
-define(SERVICE_ATTR2, [{fake_setting, 54321}]).
-define(GROUP, fake_group).
-define(NODE, 'not_a_node@127.0.0.1').

run_test_() ->
    {setup,
     fun data_platform_test_util:setup/0,
     fun(_) -> data_platform_test_util:teardown() end,
     {timeout, 30, [
                    fun clear_state/0,
                    fun start_service/0,
                    fun start_nonexistent/0,
                    fun start_duplicate/0,
                    fun add_duplicate/0,
                    fun set_and_remove_service_attribute/0,
                    fun stop_service/0,
                    fun stop_nonexistent/0,
                    fun remove_service/0
                   ]}}.

clear_state() ->
    data_platform_global_state:clear_state(),
    ?assertEqual({[], []}, data_platform_global_state:services()),
    ok.

start_service() ->
    data_platform_global_state:clear_state(),

    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),
    test_start_service_config(?GROUP, ?CONFIG_NAME, ?NODE),
    ok.

start_nonexistent() ->
    data_platform_global_state:clear_state(),

    ?assertEqual({error, config_not_found}, data_platform_global_state:start_service(
                                              ?GROUP, ?CONFIG_NAME, ?NODE)),
    ?assertEqual({[], []}, data_platform_global_state:services()),

    ok.

start_duplicate() ->
    data_platform_global_state:clear_state(),

    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),
    test_start_service_config(?GROUP, ?CONFIG_NAME, ?NODE),

    ?assertEqual({error, already_running}, data_platform_global_state:start_service(
                                             ?GROUP, ?CONFIG_NAME, ?NODE)),
    ServiceDefinition = {?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR},
    RunningServiceDefinition = {?GROUP, ?CONFIG_NAME, ?NODE},
    ExpectedServices = {[RunningServiceDefinition], [ServiceDefinition]},
    ?assertEqual(ExpectedServices, data_platform_global_state:services()),

    ok.

add_duplicate() ->
    data_platform_global_state:clear_state(),

    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),
    ?assertEqual({error, config_already_exists}, data_platform_global_state:add_service_config(
                                                   ?CONFIG_NAME, ?SERVICE2, ?SERVICE_ATTR2, false)),
    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR, true).

set_and_remove_service_attribute() ->
    Key = "testkey",
    Value = "testvalue",

    data_platform_global_state:clear_state(),

    FakeRunningService = {?GROUP, ?CONFIG_NAME, ?NODE},
    ?assertEqual(ok, data_platform_global_state:set_service_attribute(
                       FakeRunningService, Key, Value)),
    ?assertEqual([{FakeRunningService, [{Key, Value}]}],
                 data_platform_global_state:get_service_attributes()),

    ?assertEqual(ok, data_platform_global_state:remove_service_attribute(FakeRunningService)),
    ?assertEqual([], data_platform_global_state:get_service_attributes()),

    ok.

stop_service() ->
    data_platform_global_state:clear_state(),

    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),
    test_start_service_config(?GROUP, ?CONFIG_NAME, ?NODE),
    test_stop_service_config(?GROUP, ?CONFIG_NAME, ?NODE),
    ok.

stop_nonexistent() ->
    data_platform_global_state:clear_state(),

    ?assertEqual({error, service_not_found},
                 data_platform_global_state:stop_service(?GROUP, ?CONFIG_NAME, ?NODE)),
    ?assertEqual({[], []}, data_platform_global_state:services()),
    ok.

remove_service() ->
    data_platform_global_state:clear_state(),

    test_add_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),
    test_remove_service_config(?CONFIG_NAME, ?SERVICE, ?SERVICE_ATTR),

    ok.

test_add_service_config(ConfigName, Service, ServiceAttr) ->
    test_add_service_config(ConfigName, Service, ServiceAttr, false).

test_add_service_config(ConfigName, Service, ServiceAttr, ForceReplaceExisting) ->
    ?assertEqual(ok, data_platform_global_state:add_service_config(
                       ConfigName, Service, ServiceAttr, ForceReplaceExisting)),
    ServiceDefinition = {ConfigName, Service, ServiceAttr},
    {_Running, Available} = data_platform_global_state:services(),
    ?assert(lists:member(ServiceDefinition, Available)).

test_start_service_config(Group, ConfigName, Node) ->
    ?assertEqual(ok, data_platform_global_state:start_service(Group, ConfigName, Node)),
    RunningServiceDefinition = {Group, ConfigName, Node},
    {Running, _Available} = data_platform_global_state:services(),
    ?assert(lists:member(RunningServiceDefinition, Running)).

test_stop_service_config(Group, ConfigName, Node) ->
    ?assertEqual(ok, data_platform_global_state:stop_service(Group, ConfigName, Node)),
    RunningServiceDefinition = {Group, ConfigName, Node},
    {Running, _Available} = data_platform_global_state:services(),
    ?assertNot(lists:member(RunningServiceDefinition, Running)).

test_remove_service_config(ConfigName, Service, ServiceAttr) ->
    ?assertEqual(ok, data_platform_global_state:remove_service(ConfigName)),
    ServiceDefinition = {ConfigName, Service, ServiceAttr},
    {_Running, Available} = data_platform_global_state:services(),
    ?assertNot(lists:member(ServiceDefinition, Available)).
