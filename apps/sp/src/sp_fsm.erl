%%%-------------------------------------------------------------------
%%% @author imartinez
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Mar 2018 18:19
%%%-------------------------------------------------------------------
-module(sp_fsm).
-author("imartinez").

-behaviour(gen_statem).

%% API
-export([start_link/6,
         caps_lock_changed/2]).

%% gen_statem callbacks
-export([
    init/1,
    state_name/3,
    handle_event/4,
    terminate/3,
    code_change/4,
    callback_mode/0
]).

-define(SPEED_HIGH, 100).
-define(SPEED_NORMAL, 50).
-define(SPEED_SLOW, 8).

-define(FIRST_CONTACT_TIMEOUT_SECONDS, 15).
-define(FIRST_CONTACT_AFTER_BYE_SECONDS, 3).

-define(LEVEL1_TIMEOUT_SECONDS, application:get_env(sp, level1_timeout_seconds, 40)).
-define(LEVEL1_AFTER_BYE_SECONDS, 1).
-define(LEVEL1_SUCCESS_TIMEOUT_SECONDS, 2).
-define(LEVEL1_TIMES, 8).

-define(LEVEL2_TIMEOUT_SECONDS, application:get_env(sp, level2_timeout_seconds, 100)).
-define(LEVEL2_MORSE_CODE, <<"-..-.-.-..---..">>).
%-define(LEVEL2_MORSE_CODE, <<"-.">>).
-define(LEVEL2_SUCCESS_TIMEOUT_SECONDS, 3).
-define(LEVEL2_DASH_TIME, application:get_env(sp, level2_dash_time_ms, 2000)).
-define(LEVEL2_AFTER_BYE_SECONDS, 1).

-define(LEVEL3_TIMEOUT_SECONDS, application:get_env(sp, level3_timeout_seconds, 30)).

-define(MAYHEM_TIMEOUT_SECONDS, 30).

-define(VIM_INITIAL, "73475cb40a568e8da8a045ced110137e159f890ac4da883b6b17dc651b3a8049").
-define(VIM_FINAL,   "73475Cb40a568e8dA9a045ced110137e160f890ac4da883b6b17dc651b3a8049").

-define(SERVER, ?MODULE).

-record(data, {id :: non_neg_integer(),
               ip_address :: inet:ip_address(),
               port :: inet:port_number(),

               device,

               server_pid :: pid(),
               caps_lock_enabled :: boolean(),
               level1_timer :: reference(),
               level1_counter = 0 :: non_neg_integer(),
               level1_success_timer = undefined :: reference() | undefined,

               level2_timer = undefined :: undefined | reference(),
               level2_buffer = <<>> :: binary(),
               level2_key_start_time = undefined :: undefined | integer(),
               level2_key_timer :: reference(),
               level2_success_timer = undefined :: reference() | undefined,

               level3_timer :: reference(),
               level3_half_timer :: reference()}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Device, KeyServer, IsCapsLockEnabled, Id, IpAddress, Port) ->
    gen_statem:start_link(?MODULE, [Device, KeyServer, IsCapsLockEnabled, Id, IpAddress, Port], []).

caps_lock_changed(undefined, _) ->
    ok;
caps_lock_changed(SrvRef, CapsLockEnabled) ->
    gen_statem:cast(SrvRef, {caps_lock_enabled, CapsLockEnabled}).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_statem is started using gen_statem:start/[3,4] or
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {CallbackMode, StateName, State} |
%%                     {CallbackMode, StateName, State, Actions} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------
init([Device, KeyServer, IsCapsLockEnabled, Id, IpAddress, Port]) ->
    _NewState = case IsCapsLockEnabled of
                   true ->
                       first_contact;
                   false ->
                       case Device of
                           first ->
                               level1;
                           second ->
                               level3
                       end
               end,
    NewState = _NewState,
    {ok, NewState, #data{server_pid = KeyServer, caps_lock_enabled = IsCapsLockEnabled,
        id = Id, ip_address = IpAddress, port = Port, device = Device}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Called (1) whenever sys:get_status/1,2 is called by gen_statem or
%% (2) when gen_statem terminates abnormally.
%% This callback is optional.
%%
%% @spec format_status(Opt, [PDict, StateName, State]) -> term()
%% @end
%%--------------------------------------------------------------------
%format_status(_Opt, [_PDict, _StateName, _State]) ->
%    Status = some_term,
%    Status.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name.  If callback_mode is statefunctions, one of these
%% functions is called when gen_statem receives and event from
%% call/2, cast/2, or as a normal process message.
%%
%% @spec state_name(Event, From, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Actions} |
%%                   {stop, Reason, NewState} |
%%    				 stop |
%%                   {stop, Reason :: term()} |
%%                   {stop, Reason :: term(), NewData :: data()} |
%%                   {stop_and_reply, Reason, Replies} |
%%                   {stop_and_reply, Reason, Replies, NewState} |
%%                   {keep_state, NewData :: data()} |
%%                   {keep_state, NewState, Actions} |
%%                   keep_state_and_data |
%%                   {keep_state_and_data, Actions}
%% @end
%%--------------------------------------------------------------------
state_name(_EventType, _EventContent, State) ->
    NextStateName = next_state,
    {next_state, NextStateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% If callback_mode is handle_event_function, then whenever a
%% gen_statem receives an event from call/2, cast/2, or as a normal
%% process message, this function is called.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Actions} |
%%                   {stop, Reason, NewState} |
%%    				 stop |
%%                   {stop, Reason :: term()} |
%%                   {stop, Reason :: term(), NewData :: data()} |
%%                   {stop_and_reply, Reason, Replies} |
%%                   {stop_and_reply, Reason, Replies, NewState} |
%%                   {keep_state, NewData :: data()} |
%%                   {keep_state, NewState, Actions} |
%%                   keep_state_and_data |
%%                   {keep_state_and_data, Actions}
%% @end
%%--------------------------------------------------------------------
handle_event(enter, _OldState, test, #data{server_pid = _SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, test)]),
  %sp_keyboard:debug(),
  %sp_keyboard:send_keys(SrvPid, [file, calculator, browser, email, eject, none, alt_f4, none]),
  %sp_keyboard:fix_caps_lock(SrvPid, true),
    %sp_keyboard:set_caps_lock(SrvPid, on),
    %sp_keyboard:send_keys(SrvPid, ["hola", caps_lock, none]),
    %timer:sleep(2000),
    %sp_keyboard:send_keys(SrvPid, ["ADIOS", none]),
    %sp_keyboard:set_caps_lock(SrvPid, false),
  keep_state_and_data;


%% FIRST CONTACT
handle_event(enter, _OldState, first_contact, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, first_contact)]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:send_keys(SrvPid, ["echo IT IS NOT POLITE TO ENTER IN A SERVER SHOUTING LIKE THAT\n", none]),
    sp_keyboard:send_keys(SrvPid, ["echo PLEASE DISABLE CAPS LOCK ", none]),
    timer:sleep(1000),
    sp_keyboard:send_keys(SrvPid, ["GO OUT AND COME BACK IN AGAIN\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    {stop, normal};


%% LEVEL 1
handle_event(enter, _OldState, level1, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, level1)]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:send_keys(SrvPid, ["echo Starting the 2-factor authentication challenge\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:send_keys(SrvPid, ["echo Lets check if you are able to follow simple hidden instructions in the next lines. Wait for Go to start\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_HIGH),
    sp_keyboard:send_keys(SrvPid, ["stty -echo\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    HiddenText = binary_to_list(iolist_to_binary(io_lib:format(" Highlight CAPS LOCK LED ~p times   ", [?LEVEL1_TIMES]))),
    sp_keyboard:send_keys(SrvPid, [HiddenText, ctrl_c, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(500),
    sp_keyboard:send_keys(SrvPid, ["stty echo\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:send_caps_lock_messages(SrvPid, true),
    Text = binary_to_list(iolist_to_binary(io_lib:format("echo You have ~p seconds to do it\n", [?LEVEL1_TIMEOUT_SECONDS]))),
    sp_keyboard:send_keys(SrvPid, ["\n", Text, none]),
    sp_keyboard:send_keys(SrvPid, ["echo Go"]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    Timer = erlang:start_timer(?LEVEL1_TIMEOUT_SECONDS * 1000, self(), level1_timeout),
    {keep_state, Data#data{level1_timer = Timer}};
handle_event(cast, {caps_lock_enabled, false}, level1, #data{}) ->
    keep_state_and_data;
handle_event(cast, {caps_lock_enabled, true}, level1, #data{level1_counter = Counter, level1_timer = Level1Timer} = Data) ->
    NewCounter = Counter + 1,
    lager:debug("## CAPS LOCK ENABLED, NewCounter = ~p~n", [NewCounter]),
    case NewCounter == ?LEVEL1_TIMES orelse NewCounter == (?LEVEL1_TIMES * 2) of
        true ->
            % We achieved the correct number of times
            RestTime = case cancel_timer(Level1Timer) of
                           Time when is_integer(Time) ->
                               Time;
                           _ ->
                               0
                       end,

            SuccessTimer = erlang:start_timer((?LEVEL1_SUCCESS_TIMEOUT_SECONDS * 1000), self(), level1_success_timeout),
            NewLevel1Timer = erlang:start_timer((?LEVEL1_SUCCESS_TIMEOUT_SECONDS * 1000) + RestTime + 1, self(), level1_timeout),
            {keep_state, Data#data{level1_counter = NewCounter, level1_timer = NewLevel1Timer, level1_success_timer = SuccessTimer}};
        _ ->
            cancel_timer(Data#data.level1_success_timer),
            {keep_state, Data#data{level1_counter = NewCounter, level1_success_timer = undefined}}
    end;
handle_event(info, {timeout, _, level1_success_timeout}, level1, #data{server_pid = SrvPid, level1_timer = Level1Timer} = Data) ->
    lager:info("~s completed", [log_prefix(Data, level1)]),
    cancel_timer(Level1Timer),
    receive
        {timeout, _, level1_timeout} -> ok
    after 0 ->
        ok
    end,
    sp_keyboard:send_caps_lock_messages(SrvPid, false),
    sp_keyboard:send_keys(SrvPid, ["\n\necho LEVEL 1 COMPLETED\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    {next_state, level2, Data};
handle_event(info, {timeout, _, level1_timeout}, level1, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s failed with counter = ~p", [log_prefix(Data, level1), Data#data.level1_counter]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_SLOW),
    sp_keyboard:send_keys(SrvPid, [none, interleave_none("NON MI CAPisci"), none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(?LEVEL1_AFTER_BYE_SECONDS * 1000),
    {next_state, mayhem, Data};


%% LEVEL 2
handle_event(enter, _Oldstate, level2, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, level2)]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:set_caps_lock(SrvPid, off),
    sp_keyboard:send_keys(SrvPid, ["echo Welcome to level 2\n", none]),
    sp_keyboard:send_keys(SrvPid, ["echo Write TUENTI8 in Morse using CAPS LOCK, no errors allowed. I will let you know what I am detecting with - and o characters\n", none]),
    TimeText = binary_to_list(iolist_to_binary(io_lib:format("echo You have ~p seconds to do it\n", [?LEVEL2_TIMEOUT_SECONDS]))),
    sp_keyboard:send_keys(SrvPid, [TimeText, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    DashText = binary_to_list(iolist_to_binary(io_lib:format("echo A dash should be at least ~p milliseconds long\n", [?LEVEL2_DASH_TIME]))),
    sp_keyboard:send_keys(SrvPid, [DashText, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    TimeoutTimer = erlang:start_timer(?LEVEL2_TIMEOUT_SECONDS * 1000, self(), level2_timeout),
    sp_keyboard:send_caps_lock_messages(SrvPid, true),
    {keep_state, Data#data{level2_timer = TimeoutTimer}};
handle_event(cast, {caps_lock_enabled, true}, level2, Data) ->
    receive
        {timeout, _, dash_timeout} ->
            ok
    after 0 ->
        ok
    end,
    KeyStartTime = erlang:monotonic_time(millisecond),
    KeyTimer = erlang:start_timer(?LEVEL2_DASH_TIME, self(), dash_timeout),
    {keep_state, Data#data{level2_key_start_time = KeyStartTime, level2_key_timer = KeyTimer}};
handle_event(cast, {caps_lock_enabled, false}, level2, #data{level2_key_start_time = undefined}) ->
    keep_state_and_data;
handle_event(cast, {caps_lock_enabled, false}, level2, #data{server_pid = SrvPid, level2_buffer = Buffer} = Data) ->
    cancel_timer(Data#data.level2_key_timer),
    sp_keyboard:send_keys(SrvPid, ["o", none]),
    NewBuffer = <<Buffer/binary, ".">>,
    NewData = level2_check_success(NewBuffer, Data),
    {keep_state, NewData#data{level2_key_start_time = undefined, level2_key_timer = undefined}};
handle_event(info, {timeout, _, dash_timeout}, level2, #data{server_pid = SrvPid, level2_buffer = Buffer} = Data) ->
    sp_keyboard:send_keys(SrvPid, ["-", none]),
    NewBuffer = <<Buffer/binary, "-">>,
    NewData = level2_check_success(NewBuffer, Data),
    {keep_state, NewData#data{level2_key_start_time = undefined}};
handle_event(info, {timeout, _, level2_success_timeout}, level2, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s completed", [log_prefix(Data, level2)]),
    sp_keyboard:send_caps_lock_messages(SrvPid, false),
    cancel_timer(Data#data.level2_timer),
    cancel_timer(Data#data.level2_key_timer),
    sp_keyboard:send_keys(SrvPid, ["\n\necho CONGRATULATIONS\n", none]),
    sp_keyboard:send_keys(SrvPid, ["echo You have passed the 2-factor authentication system\n", none]),
    case application:get_env(sp, two_entries, false) of
        false ->
            {next_state, level3, Data};
        true ->
            DeviceName = application:get_env(sp, second_device, <<"vip-access">>),
            Text = binary_to_list(iolist_to_binary(io_lib:format("echo To continue, connect to the ~s device instead of 8-tuenti\n", [DeviceName]))),
            sp_keyboard:send_keys(SrvPid, [Text, none]),
            sp_keyboard:wait_for_empty_buffer(SrvPid),
            {stop, normal}
    end;
handle_event(info, {timeout, _, level2_timeout}, level2, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s failed with \"~s\"", [log_prefix(Data, level2), Data#data.level2_buffer]),
    sp_keyboard:send_caps_lock_messages(SrvPid, false),
    sp_keyboard:send_keys(SrvPid, [ctrl_c, "\necho SEE YOU SOON\necho NO REMORSE\n", none]),
    timer:sleep(?LEVEL2_AFTER_BYE_SECONDS * 1000),
    {next_state, mayhem, Data};


%% LEVEL 3
handle_event(enter, _OldState, level3, #data{server_pid = SrvPid} = Data) ->
    case application:get_env(sp, two_entries, false) of
        true ->
            lager:info("~s enter VIP-access", [log_prefix(Data, level3)]);
        _ ->
            lager:info("~s enter", [log_prefix(Data, level3)])
    end,
    sp_keyboard:send_caps_lock_messages(SrvPid, false),
    sp_keyboard:send_keys(SrvPid, ["\n\necho Is anybody there\n", none]),
    sp_keyboard:send_keys(SrvPid, ["echo To say YES activate CAPS LOCK\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:send_caps_lock_messages(SrvPid, true),
    Level3HalfTimer = erlang:start_timer(?LEVEL3_TIMEOUT_SECONDS * 500, self(), level3_half_timeout),
    Level3Timer = erlang:start_timer(?LEVEL3_TIMEOUT_SECONDS * 1000, self(), level3_timeout),
    {keep_state, Data#data{level3_timer = Level3Timer, level3_half_timer = Level3HalfTimer}};
handle_event(cast, {caps_lock_enabled, true}, level3, #data{server_pid = SrvPid, level3_timer = Level3Timer, level3_half_timer = Level3HalfTimer} = Data) ->
    lager:info("~s failed", [log_prefix(Data, level3)]),
    cancel_timer(Level3HalfTimer),
    cancel_timer(Level3Timer),
    sp_keyboard:send_caps_lock_messages(SrvPid, false),
    %sp_keyboard:set_caps_lock(SrvPid, off),
    sp_keyboard:send_keys(SrvPid, ["echo You should not be there\n", none]),
    {next_state, mayhem, Data};
handle_event(info, {timeout, _, level3_half_timeout}, level3, #data{server_pid = SrvPid} = Data) ->
    sp_keyboard:send_keys(SrvPid, ["\n\necho Nobody\n\n", none]),
    {keep_state, Data#data{level3_half_timer = undefined}};
handle_event(info, {timeout, _, level3_timeout}, level3, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s completed", [log_prefix(Data, level3)]),
    sp_keyboard:send_keys(SrvPid, ["\n\necho Coast is clear\n\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(2000),
    {next_state, vim, Data};



%% VIM
handle_event(enter, _OldState, vim, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, vim)]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:send_keys(SrvPid, ["xset r off\n", none]),
    sp_keyboard:send_keys(SrvPid, ["vi solution-super-secret-password", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(2000),
    sp_keyboard:send_keys(SrvPid, ["\n", none]),
    sp_keyboard:send_keys(SrvPid, ["i", "start with sha256sum of 42", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(2000),
    sp_keyboard:send_keys(SrvPid, [escape, "dd", none]),
    sp_keyboard:send_keys(SrvPid, ["i", ?VIM_INITIAL]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(250),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_HIGH),
    sp_keyboard:send_keys(SrvPid, [escape, "05lgUl", none]),
    sp_keyboard:send_keys(SrvPid, ["11lgUl", none]),
    sp_keyboard:send_keys(SrvPid, ["l", ctrl_a, none]),
    sp_keyboard:send_keys(SrvPid, ["17l", ctrl_a, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:send_keys(SrvPid, ["ZQ", none]),
    sp_keyboard:send_keys(SrvPid, [ctrl_a, "\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(1000),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    sp_keyboard:send_keys(SrvPid, ["echo I typed fast I hope nobody saw it\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_HIGH),
    sp_keyboard:send_keys(SrvPid, [ctrl_s, "\n\n", none]),
    sp_keyboard:send_keys(SrvPid, ["xset r on\n", none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    lager:info("~s completed", [log_prefix(Data, vim)]),
    {stop, normal};

handle_event(enter, _OldState, mayhem, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s enter", [log_prefix(Data, mayhem)]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_NORMAL),
    self() ! loop,
    erlang:send_after(?MAYHEM_TIMEOUT_SECONDS * 1000, self(), mayhem_timeout),
    keep_state_and_data;
handle_event(info, loop, mayhem, #data{server_pid = SrvPid}) ->
    Apps = generate_random_keys(keys_apps, 20),
    sp_keyboard:send_keys(SrvPid, [Apps, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(5000),
    sp_keyboard:send_keys(SrvPid, [sleep, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    sp_keyboard:send_keys(SrvPid, [power, "\n", none]),
    sp_keyboard:set_keys_per_second(SrvPid, ?SPEED_HIGH),
    Keys = generate_random_keys(keys, 200),
    sp_keyboard:send_keys(SrvPid, [Keys, none]),
    sp_keyboard:wait_for_empty_buffer(SrvPid),
    timer:sleep(1000),
    self() ! loop,
    keep_state_and_data;
handle_event(info, mayhem_timeout, mayhem, #data{server_pid = SrvPid} = Data) ->
    lager:info("~s stopping", [log_prefix(Data, mayhem)]),
    sp_keyboard:send_keys(SrvPid, ["BYE\n"]),
    {stop, normal};

handle_event(_EventType, _EventContent, _StateName, _State) ->
    keep_state_and_data.


level2_check_success(?LEVEL2_MORSE_CODE, Data) ->
    SuccessTimer = erlang:start_timer(?LEVEL2_SUCCESS_TIMEOUT_SECONDS * 1000, self(), level2_success_timeout),
    Data#data{level2_success_timer = SuccessTimer, level2_buffer = ?LEVEL2_MORSE_CODE};
level2_check_success(Buffer, #data{level2_success_timer = Level2SuccessTimer} = Data) ->
    cancel_timer(Level2SuccessTimer),
    receive
        {timeout, _, level2_success_timeout} -> ok
    after 0 -> ok
    end,
    Data#data{level2_success_timer = undefined, level2_buffer = Buffer}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_statem when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_statem terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.


callback_mode() ->
    [handle_event_function, state_enter].


%%%===================================================================
%%% Internal functions
%%%===================================================================

cancel_timer(undefined) ->
    0;
cancel_timer(Ref) ->
    case catch erlang:cancel_timer(Ref) of
        N when is_integer(N) ->
            N;
        _ ->
            0
    end.

generate_random_keys(Ets, Count) ->
    EtsSize = ets:info(Ets, size),
    generate_random_keys(Ets, EtsSize, Count, []).

generate_random_keys(_Ets, _EtsSize, 0, Acc) ->
    Acc;
generate_random_keys(Ets, EtsSize, Count, Acc) ->
    N = rand:uniform(EtsSize),
    [{_, Key}] = ets:lookup(Ets, N),
    generate_random_keys(Ets, EtsSize, Count - 1, [Key | Acc]).


log_prefix(#data{id = Id, ip_address = IpAddressString, port = Port}) ->
    io_lib:format("fsm ID ~B ~p ~s:~B", [Id, self(), IpAddressString, Port]).

log_prefix(Data, StateName) ->
    io_lib:format("~s ~s", [log_prefix(Data), StateName]).

interleave_none(String) ->
    lists:reverse(lists:foldl(fun(X, Acc) -> [none, X | Acc] end, [], String)).