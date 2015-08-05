-type group() :: binary().
-type group_id() :: binary().
-type peer() :: binary().
-type epoch() :: integer().
-type seq() :: integer().

-define(LEADER_TICK, 100).
-define(FOLLOW_TICK, 10*?LEADER_TICK).
-define(JANITOR_TICK, 300*?LEADER_TICK).
