%%%-------------------------------------------------------------------
%%% @author imrivera
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. Mar 2018 16:47
%%%-------------------------------------------------------------------
-module(sp_keyboard).
-author("imrivera").

-behaviour(gen_server).

%% API
-export([start/1]).
-export([debug/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).


-export([send_keys/2,
         fix_caps_lock/2,
         wait_for_empty_buffer/1,
         set_caps_lock/2,
         send_caps_lock_messages/2,
         set_keys_per_second/2]).


-define(HIGH_PRIORITY, 0).
-define(NORMAL_PRIORITY, 1).


-define(SERVER, ?MODULE).

-define(USBIP_VERSION, 16#0111).
-define(USBIP_OP_CMD_SUBMIT, 16#0001).
-define(USBIP_OP_RET_SUBMIT, 16#0003).
-define(USBIP_OP_CMD_UNLINK, 16#0002).
-define(USBIP_OP_RET_UNLINK, 16#0004).
-define(USBIP_OP_REQ_IMPORT, 16#8003).
-define(USBIP_OP_REP_IMPORT, 16#0003).
-define(USBIP_OP_REQ_DEVLIST, 16#8005).
-define(USBIP_OP_REP_DEVLIST, 16#0005).

-define(DEVICE_SYSTEM_PATH, <<"/tuenti/challenge/8/victorias/secret">>).
-define(DEVICE_BUSID, <<"8-tuenti">>).
%-define(DEVICE_SYSTEM_PATH, <<"/sys/devices/pci0000:00/0000:00:14.0/usb1/1-14">>).
%-define(DEVICE_BUSID, <<"1-14">>).
-define(DEVICE_BUS_NUMBER, 1).
-define(DEVICE_NUMBER, 9).
-define(DEVICE_CONNECTED_SPEED, 1). % 1 = Low speed
-define(DEVICE_ID_VENDOR, 16#413C).
-define(DEVICE_ID_PRODUCT, 16#2003).
-define(DEVICE_BCD_DEVICE, 16#0306).
-define(DEVICE_BDEVICE_CLASS, 16#00).
-define(DEVICE_BDEVICE_SUB_CLASS, 16#00).
-define(DEVICE_BDEVICE_PROTOCOL, 16#00).
-define(DEVICE_BCONFIGURATION_VALUE, 16#00).
-define(DEVICE_BNUM_CONFIGURATIONS, 16#01).
-define(DEVICE_BNUM_INTERFACES, 16#00).


-define(INPUT_DATA_SIZE, 10).
-define(HID_REPORT, <<16#05, 16#01, 16#09, 16#06, 16#a1, 16#01, 16#05, 16#07, 16#19, 16#e0, 16#29, 16#e7, 16#15, 16#00, 16#25, 16#01,
  16#75, 16#01, 16#95, 16#08, 16#81, 16#02, 16#95, 16#01, 16#75, 16#08, 16#81, 16#01, 16#95, 16#03, 16#75, 16#01,
  16#05, 16#08, 16#19, 16#01, 16#29, 16#03, 16#91, 16#02, 16#95, 16#01, 16#75, 16#05, 16#91, 16#01, 16#95, 16#06,
  16#75, 16#08, 16#15, 16#00, 16#26, 16#ff, 16#00, 16#05, 16#07, 16#19, 16#00, 16#2a, 16#ff, 16#00, 16#81, 16#00,
  16#95, 16#01, 16#75, 16#01, 16#05, 16#01, 16#09, 16#81, 16#81, 16#02, % Power Down  1-bit
  16#95, 16#01, 16#75, 16#01, 16#05, 16#01, 16#09, 16#82, 16#81, 16#02, % Sleep 1-bit
  16#95, 16#01, 16#75, 16#06, 16#81, 16#01,  % 6-bit padding

  15#01, 25#01, 16#0B, 16#96, 16#01, 16#0C, 16#00, 16#95, 16#01, 16#75, 16#01, 16#81, 16#60,
  %16#95, 16#01, 16#75, 16#01, 16#05, 16#0C, 16#0B, 16#92, 16#01, 16#00, 16#81, 16#02,
  16#95, 16#01, 16#75, 16#07, 16#81, 16#01,


  16#c0>>).

-define(URB_VENDOR, <<"Dell"/utf16-little>>).
-define(URB_DESC, <<"Dell USB Keyboard"/utf16-little>>).

-record(state, {socket :: gen_tcp:socket(),
                pending_data = <<>> :: binary(),
                step :: undefined | imported,
                submit_sequence = undefined :: non_neg_integer() | undefined,
                timer_for_set = undefined :: reference() | undefined,
                pending_keys :: pqueue2:pqueue2(),
                ready_for_keys = false :: boolean(),
                caps_lock_fix = false :: boolean(),
                caps_lock_enabled = false :: boolean(),
                fsm_pid = undefined :: undefined | pid(),
                from_wait_for_empty_buffer = undefined,
                send_caps_lock_messages = false :: boolean(),
                keys_per_second = 50 :: number(),
                time_last_send :: integer(),
                waiting_for_caps_lock :: undefined | boolean(),
                from_waiting_for_caps_lock}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(gen_tcp:socket()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start(Socket) ->
  gen_server:start(?MODULE, [Socket], []).

debug() ->
  dbg:tracer(),
  dbg:tpl(?MODULE, x),
  dbg:tpl(gen_tcp, send, x),
  dbg:p(all, [c]).


send_keys(SrvRef, Keys) ->
    gen_server:call(SrvRef, {send_keys, Keys, ?NORMAL_PRIORITY}).

fix_caps_lock(SrvRef, Value) ->
    gen_server:call(SrvRef, {fix_caps_lock, Value == true}).

-spec set_caps_lock(pid(), on | off) -> ok.
set_caps_lock(SrvRef, Value) ->
    gen_server:call(SrvRef, {set_caps_lock, Value}).

wait_for_empty_buffer(SrvRef) ->
    gen_server:call(SrvRef, wait_for_empty_buffer, 30000).

send_caps_lock_messages(SrvRef, SendEnabled) ->
    gen_server:call(SrvRef, {send_caps_lock_messages, SendEnabled}).

set_keys_per_second(SrvRef, KeysPerSecond) when is_integer(KeysPerSecond) andalso KeysPerSecond > 0 ->
    gen_server:call(SrvRef, {set_keys_per_second, KeysPerSecond}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([Socket]) ->
    io:format("I'M ~p~n", [self()]),
  {ok, #state{socket = Socket, pending_data = <<>>, step = undefined, pending_keys = pqueue2:new(),
              time_last_send = erlang:monotonic_time(millisecond)}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call({send_keys, Keys, Priority}, _From, #state{pending_keys = PendingKeys} = State) ->
    Keys2 = filter_keys(lists:flatten(Keys)),
    % We can't send keys right now, enqueue them
    NewPendingKeys = lists:foldl(fun(Key, Queue) -> pqueue2:in(Key, Priority, Queue) end, PendingKeys, Keys2),
    State2 = State#state{pending_keys = NewPendingKeys},

    State3 = case State2#state.ready_for_keys of
                false ->
                    State2;
                true ->
                    check_and_send_key(State2)
             end,
    {reply, ok, State3};
handle_call({fix_caps_lock, Value}, _From, #state{caps_lock_enabled = true} = State) ->
    {reply, ok, State#state{caps_lock_fix = Value}};
handle_call({fix_caps_lock, true}, From, State) ->
    % We want to enable caps_lock and we know it's disabled
    handle_call({send_keys, [caps_lock, none], ?HIGH_PRIORITY}, From, State#state{caps_lock_fix = true});
handle_call(wait_for_empty_buffer, From, #state{pending_keys = PendingKeys} = State) ->
    case pqueue2:is_empty(PendingKeys) of
        true ->
            {reply, ok, State};
        false ->
            {noreply, State#state{from_wait_for_empty_buffer = From}}
    end;
handle_call({set_caps_lock, Value}, From, #state{caps_lock_enabled = IsCapsLockEnabled} = State) ->
    BoolValue = Value == on,
    case IsCapsLockEnabled == BoolValue of
        true ->
            % Already in required state
            {reply, ok, State#state{caps_lock_fix = false}};
        false ->
            NewState = State#state{waiting_for_caps_lock = BoolValue, from_waiting_for_caps_lock = From, caps_lock_fix = false},
            handle_call({send_keys, [caps_lock, none], ?HIGH_PRIORITY}, From, NewState)
    end;
handle_call({send_caps_lock_messages, SendEnabled}, _From, State) ->
    {reply, ok, State#state{send_caps_lock_messages = SendEnabled}};
handle_call({set_keys_per_second, KeysPerSecond}, _From, State) ->
    {reply, ok, State#state{keys_per_second = KeysPerSecond}};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info({tcp, Socket, Data}, #state{pending_data = PendingData} = State) ->
  FullBuffer = <<PendingData/binary, Data/binary>>,
  StateWithFullBuffer = State#state{pending_data = FullBuffer},
  case handle_command(FullBuffer, Socket, StateWithFullBuffer) of
    {need_more_data, NewState} ->
      inet:setopts(Socket, [{active, once}]),
      {noreply, NewState};
    close ->
      gen_tcp:close(Socket),
      {stop, normal, StateWithFullBuffer};
    {error, Reason} ->
      {stop, Reason, StateWithFullBuffer}
  end;
handle_info(waiting_for_set_configuration_timeout, #state{timer_for_set = undefined} = State) ->
    % This message arrived too late, SET REPORT already handled this case, just ignore it
    {noreply, State};
handle_info(waiting_for_set_configuration_timeout, State) ->
    io:format("## READY (TIMEOUT)~n"),
    NewState = check_and_send_key(State),
    {ok, FsmPid} = sp_fsm:start_link(self(), State#state.caps_lock_enabled),
    {noreply, NewState#state{timer_for_set = undefined, fsm_pid = FsmPid}};
handle_info(timeout_for_ready_keys, State) ->
    NewState = check_and_send_key(State),
    {noreply, NewState};
handle_info({tcp_closed, _}, State) ->
  % Connection closed
  {stop, normal, State};
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_command(<<?USBIP_VERSION:16/big, ?USBIP_OP_REQ_DEVLIST:16/big, _Status:32/big, _RestBinary/binary>>, Socket, #state{step = undefined}) ->
  io:format("USBIP_OP_REQ_DEVLIST~n"),
  Resp = [
    <<?USBIP_VERSION:16/big,
      ?USBIP_OP_REP_DEVLIST:16/big,
      0:32/big,          % Success
      1:32/big>>,        % Number of exported devices
    bin_zero_pad(?DEVICE_SYSTEM_PATH, 256),  % System path
    bin_zero_pad(?DEVICE_BUSID, 32),         % Bus Id
    <<?DEVICE_BUS_NUMBER:32/big>>,
    <<?DEVICE_NUMBER:32/big>>,
    <<?DEVICE_CONNECTED_SPEED:32/big>>,
    <<?DEVICE_ID_VENDOR:16/big>>,
    <<?DEVICE_ID_PRODUCT:16/big>>,
    <<?DEVICE_BCD_DEVICE:16/big>>,
    ?DEVICE_BDEVICE_CLASS,
    ?DEVICE_BDEVICE_SUB_CLASS,
    ?DEVICE_BDEVICE_PROTOCOL,
    ?DEVICE_BCONFIGURATION_VALUE,
    ?DEVICE_BNUM_CONFIGURATIONS,
    ?DEVICE_BNUM_INTERFACES],
  gen_tcp:send(Socket, Resp),
  close;
handle_command(<<?USBIP_VERSION:16/big, ?USBIP_OP_REQ_IMPORT:16/big, _Status:32/big, BusId:32/binary, RestBinary/binary>>, Socket, #state{step = undefined} = State) ->
  PaddedBusId = iolist_to_binary(bin_zero_pad(?DEVICE_BUSID, 32)),
  io:format("MyBus = #~s#~n", [PaddedBusId]),
  io:format("OtBus = #~s#~n", [BusId]),
  case PaddedBusId == BusId of
    false ->
      RespError = [
        <<?USBIP_VERSION:16/big>>,
        <<?USBIP_OP_REP_IMPORT:16/big>>,
        <<1:32/big>>],  % 1 = Error Status
      gen_tcp:send(Socket, RespError),
      close;
    true ->
      RespOk = [
        <<?USBIP_VERSION:16/big>>,
        <<?USBIP_OP_REP_IMPORT:16/big>>,
        <<0:32/big>>,   % 0 = Status ok,
        bin_zero_pad(?DEVICE_SYSTEM_PATH, 256),
        PaddedBusId,
        <<?DEVICE_BUS_NUMBER:32/big>>,
        <<?DEVICE_NUMBER:32/big>>,
        <<?DEVICE_CONNECTED_SPEED:32/big>>,
        <<?DEVICE_ID_VENDOR:16/big>>,
        <<?DEVICE_ID_PRODUCT:16/big>>,
        <<?DEVICE_BCD_DEVICE:16/big>>,
        ?DEVICE_BDEVICE_CLASS,
        ?DEVICE_BDEVICE_SUB_CLASS,
        ?DEVICE_BDEVICE_PROTOCOL,
        ?DEVICE_BCONFIGURATION_VALUE,
        ?DEVICE_BNUM_CONFIGURATIONS,
        ?DEVICE_BNUM_INTERFACES],
      gen_tcp:send(Socket, RespOk),
      handle_command(RestBinary, Socket, State#state{step = imported, pending_data = RestBinary})
  end;
handle_command(<<?USBIP_OP_CMD_SUBMIT:32/big, RestBinary/binary>>, Socket, #state{step = imported} = State) ->
  handle_cmd_submit(RestBinary, Socket, State);
handle_command(<<?USBIP_OP_CMD_UNLINK:32/big, SequenceNumber:32/big, ?DEVICE_BUS_NUMBER:16/big, ?DEVICE_NUMBER:16/big,
    _Direction:32/big,
    _Endpoint:32/big,
    UnlinkSequenceNumber:32/big,
    _:24/binary, % ???
    RestBinary/binary>>, Socket, #state{step = imported} = State) ->

  io:format ("## UNLINK ~p~n", [UnlinkSequenceNumber]),
  Resp = [<<?USBIP_OP_RET_UNLINK:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>],

  gen_tcp:send(Socket, Resp),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_command(Binary, _Socket, State) when size(Binary) =< 5120 ->
  %io:format("## UNRECOGNIZED COMMAND ~p~n",[Binary]),
  {need_more_data, State};
handle_command(_, _, _) ->
  {error, invalid_data}.

handle_cmd_submit(<<SequenceNumber:32/big, ?DEVICE_BUS_NUMBER:16/big, ?DEVICE_NUMBER:16/big,
  Direction:32/big,  % Direction
  0:32/big,  % Endpoint
  _:32/big, % Transfer flags
  _TransferBufferLength:32/big,
  0:32/big, % ISO start frame
  0:32/big, % Number of ISO descriptors
  0:32/big, % Interval
  RestBinary/binary>>, Socket, State) ->

  Op = case Direction band 1 of
          1 -> get;
          0 -> set
  end,
  handle_urb(Op, RestBinary, SequenceNumber, Socket, State);

handle_cmd_submit(<<SequenceNumber:32/big,
                    ?DEVICE_BUS_NUMBER:16/big,
                    ?DEVICE_NUMBER:16/big,
                    1:32/big,  % Direction
                    1:32/big,  % Endpoint
                    _:32/big, % Transfer flags
                    _TransferBufferLength:32/big,
                    _:32/big, % ISO start frame
                    _:32/big, % Number of ISO descriptors
                    _:32/big, % Interval
                    _:64/big,
                    RestBinary/binary>>,
                    Socket,
                    #state{submit_sequence = OldSubmitSequence} = State) ->

  io:format("## URB SUBMIT ~p~n", [SequenceNumber]),
  case OldSubmitSequence == undefined of
      true ->
          % This is the first submit, we are not ready yet, wait for a SET CONFIGURATION or timeout
          TimerRef = erlang:send_after(3000, self(), waiting_for_set_configuration_timeout),
          handle_command(RestBinary, Socket, State#state{pending_data = RestBinary, submit_sequence = SequenceNumber, timer_for_set = TimerRef});
      false ->
          io:format("## State#state.time_last_send = ~p~n", [State#state.time_last_send]),
        MonotonicTime = erlang:monotonic_time(millisecond),
          io:format("## MonotonicTime = ~p~n", [MonotonicTime]),
        ElapsedTime = MonotonicTime - State#state.time_last_send,
          io:format("## ElapsedTime = ~p~n", [ElapsedTime]),
          io:format("## Delay = ~p~n", [(1000 / State#state.keys_per_second)]),
          RemainingTime = (1000 / State#state.keys_per_second) - ElapsedTime,
          io:format("## RemainingTime = ~p~n", [RemainingTime]),
          case RemainingTime < 0 of
            true ->
              NewState = check_and_send_key(State#state{submit_sequence = SequenceNumber}),
              handle_command(RestBinary, Socket, NewState#state{pending_data = RestBinary});
            false ->
              io:format("## round(ceil(RemainingTime)) = ~p~n", [round(ceil(RemainingTime))]),
              erlang:send_after(round(ceil(RemainingTime)), self(), timeout_for_ready_keys),
              handle_command(RestBinary, Socket, State#state{pending_data = RestBinary, submit_sequence = SequenceNumber})
          end
  end;
handle_cmd_submit(_Binary, _, State) ->
  {ok, State}.


handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
             0,    % Descriptor Index
             1,    % Descriptor Type  (DEVICE)
             _Language:16/little,
             RequestedLength:16/little,
             RestBinary/binary>>,
             SequenceNumber,
             Socket,
             State) ->
  DeviceDescriptorIoList = [
    1,  % DescriptorType = DEVICE
    <<16#0110:16/little>>, % bcdUSB
    ?DEVICE_BDEVICE_CLASS,
    ?DEVICE_BDEVICE_SUB_CLASS,
    ?DEVICE_BDEVICE_PROTOCOL,
    8,   % MaxPacketSize
    <<?DEVICE_ID_VENDOR:16/little>>,
    <<?DEVICE_ID_PRODUCT:16/little>>,
    <<?DEVICE_BCD_DEVICE:16/little>>,  % bcdDevice
    1,  % iManufacturer
    2,  % iProduct
    0,  % iSerialNumber
    1   % bNumConfigurations
  ],

  DeviceDescriptorSize = iolist_size(DeviceDescriptorIoList) + 1,

  RespLength = lists:min([DeviceDescriptorSize, RequestedLength]),


  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
          <<SequenceNumber:32/big>>,
          <<0:16/big, 0:16/big>>,   % Devid
          <<0:32/big>>,    % Direction
          <<0:32/big>>,    % Endpoint
          <<0:32/big>>,    % Status success
          <<RespLength:32/big>>,
          <<0:32/big>>,    % ISO start frame
          <<0:32/big>>,    % Number of ISO descriptors
          <<0:32/big>>,    % ISO error count
          <<0:64/big>>     % Setup data
  ],

  FullRespBinary = iolist_to_binary([
          DeviceDescriptorSize,
          DeviceDescriptorIoList]),

  <<RespBinary:RespLength/binary, _/binary>> = FullRespBinary,

  gen_tcp:send(Socket, [RespPrefix, RespBinary]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
  0,    % Descriptor Index
  2,    % Descriptor Type  (CONFIGURATION)
  _Language:16/little,
  RequestedLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->

  InterfaceDescriptorIoList = [
    4,  % bDescriptorType (INTERFACE)
    0,  % bInterfaceNumber
    0,  % bAlternateSetting
    1,  % bNumEndpoints,
    3,  % bInterfaceClass (HID)
    1,  % bInterfaceSubclass (Boot Interface)
    1,  % bInterfaceProtocol: Keyboard,
    0   % iInterface
  ],

  InterfaceDescriptorSize = iolist_size(InterfaceDescriptorIoList) + 1,

  HidReportSize = size(?HID_REPORT),

  HidDescriptorIoList = [
    16#21,  % bDescriptorType (HID)
    <<16#110:16/little>>,  %bcdHID
    0,  %bCountryCode
    1,  % bNumDescriptors
    16#22, % bDescriptorType
    <<HidReportSize:16/little>> % wDescriptorLength
  ],

  HidDescriptorSize = iolist_size(HidDescriptorIoList) + 1,

  EndpointDescriptorIoList = [
    16#05,  % bDescriptorType (ENDPOINT)
    16#81,  % IN Endpoint:1
    16#03,  % bmAttributes
    <<?INPUT_DATA_SIZE:16/little>>,      % wMaxPacketSize
    24  % bInterval
  ],

  EndpointDescriptorSize = iolist_size(EndpointDescriptorIoList) + 1,

  AllSize = 9 + InterfaceDescriptorSize + HidDescriptorSize + EndpointDescriptorSize,

  DeviceDescriptorIoList = [
    2,  % DescriptorType = CONFIGURATION
    <<AllSize:16/little>>,  % wTotalLength
    1, % bNumInterfaces
    1, % bConfigurationValue
    0, % iConfiguration
    16#A0, % bmAttributes
    35],  % bMaxPower

  RespLength = lists:min([RequestedLength, AllSize]),

  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<RespLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  RespDescriptors = [
    9,
    DeviceDescriptorIoList,
    InterfaceDescriptorSize,
    InterfaceDescriptorIoList,
    HidDescriptorSize,
    HidDescriptorIoList,
    EndpointDescriptorSize,
    EndpointDescriptorIoList
  ],

  <<RespDescriptorsBinary:RespLength/binary, _/binary>> = iolist_to_binary(RespDescriptors),

  gen_tcp:send(Socket, [RespPrefix, RespDescriptorsBinary]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
  DescriptorIndex,    % Descriptor Index
  3,    % Descriptor Type  (STRING)
  _Language:16/little,
  RequestedLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->

  String = case DescriptorIndex of
              0 ->
                [3, <<16#0409:16/little>>];  % English
              1 ->
                [3, ?URB_VENDOR];
              2 ->
                [3, ?URB_DESC];
              _ ->
                undefined
          end,

  case String of
    undefined ->
      EmptyResp = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<0:32/big>>,
        <<0:32/big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>    % Setup data
      ],

      gen_tcp:send(Socket, EmptyResp),
      {ok, State#state{pending_data = RestBinary}};
    _ ->
      DescriptorSize = iolist_size(String) + 1,
      RespLength = lists:min([DescriptorSize, RequestedLength]),

      <<Resp:RespLength/binary, _/binary>> = iolist_to_binary([DescriptorSize, String]),

      RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<RespLength:32/big>>,
        <<0:32/big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>    % Setup data
      ],

      gen_tcp:send(Socket, [RespPrefix, Resp]),
      handle_command(RestBinary, Socket, State#state{pending_data = RestBinary})
  end;

handle_urb(get, <<16#8106:16/big,   % GET DESCRIPTOR
  0,    % Descriptor Index
  16#22,    % Descriptor Type  (HID Report)
  0:16/little,  % wInterfaceNumber
  MaxLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->


  HidReportSize = size(?HID_REPORT),
  RespLength = lists:min([HidReportSize, MaxLength]),

  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<RespLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  <<Resp:RespLength/binary, _/binary>> = iolist_to_binary([?HID_REPORT]),

  gen_tcp:send(Socket, [RespPrefix, Resp]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(set, <<16#21,    % Host to device
             9,    % bRequest  SET REPORT
             _WValue:16/little,
             0:16/little,
             1:16/little, Payload:8, RestBinary/binary>>,
            SequenceNumber, Socket, #state{timer_for_set = TimerRef} = State) ->
    % SET LED
  io:format("## SET LEDs CONFIGURATION~n"),
  EmptyResp = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<1:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  gen_tcp:send(Socket, EmptyResp),

  IsCapsLockEnabled = (Payload band 2) == 2,

    case IsCapsLockEnabled /= State#state.caps_lock_enabled andalso State#state.send_caps_lock_messages of
        true ->
            sp_fsm:caps_lock_changed(State#state.fsm_pid, IsCapsLockEnabled);
        _ ->
            ok
    end,



  NewPendingKeys = case State#state.caps_lock_fix andalso not IsCapsLockEnabled of
                       true ->
                           % We have to enable it
                           io:format("## ENABLE CAPS LOCK~n"),
                           lists:foldl(fun(Key, Queue) -> pqueue2:in(Key, ?HIGH_PRIORITY, Queue) end, State#state.pending_keys, [caps_lock, none]);
                       false ->
                           State#state.pending_keys
                   end,

  State2 = State#state{pending_keys = NewPendingKeys, caps_lock_enabled = IsCapsLockEnabled},

  State3 = case TimerRef of
              undefined ->
                          State2;
%                      true ->
 %                         % Maybe there are new keys to send
  %                        check_and_send_key(State2)
   %               end;
              _ ->
                  % We were waiting for this SET REPORT to be ready, we can start sending keys
                  io:format("## READY (SET REPORT)~n"),
                  erlang:cancel_timer(TimerRef),
                  {ok, FsmPid} = sp_fsm:start_link(self(), IsCapsLockEnabled),
                  check_and_send_key(State2#state{timer_for_set = undefined, fsm_pid = FsmPid})
           end,

  State4 = case State3#state.waiting_for_caps_lock of
             IsCapsLockEnabled ->
               gen_server:reply(State3#state.from_waiting_for_caps_lock, ok),
               State3#state{waiting_for_caps_lock = undefined, from_waiting_for_caps_lock = undefined};
             _ ->
               State3
           end,

  io:format("## CAPS_LOCK ENABLED ~p\n", [IsCapsLockEnabled]),
  handle_command(RestBinary, Socket, State4#state{pending_data = RestBinary});

handle_urb(set, <<_,    % Host to device
             _,    % bRequest
             _WValue:16/little,
             _WIndex:16/little,
             WLength:16/little, _Payload:WLength/binary, RestBinary/binary>>,
            SequenceNumber, Socket, State) ->

  io:format("##SET CONFIGURATION~n"),
  EmptyResp = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<WLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  gen_tcp:send(Socket, EmptyResp),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(_, _, _, _, State) ->
  io:format("## UNRECOGNIZED URB~n"),
  {ok, State}.

-spec bin_zero_pad(binary(), non_neg_integer()) -> iolist().
bin_zero_pad(Binary, N) when size(Binary) =< N ->
  [Binary, binary:copy(<<0>>, N - size(Binary))].


check_and_send_key(#state{socket = Socket, pending_keys = PendingKeys, submit_sequence = SequenceNumber, caps_lock_enabled = CapsLockEnabled} = State) ->
    State2 = case pqueue2:is_empty(PendingKeys) of
        true ->
            State#state{ready_for_keys = true};
        false ->
            {{value, Key}, NewPendingKeys} = pqueue2:out(PendingKeys),
            NewTimestamp = erlang:monotonic_time(millisecond),
            send_next_key(Socket, SequenceNumber, Key, CapsLockEnabled),
            State#state{
                        pending_keys = NewPendingKeys,
                        submit_sequence = SequenceNumber,
                        ready_for_keys = false,
                        time_last_send = NewTimestamp}
    end,

    case pqueue2:is_empty(State2#state.pending_keys) andalso State2#state.from_wait_for_empty_buffer =/= undefined of
        true ->
            gen_server:reply(State2#state.from_wait_for_empty_buffer, ok),
            State2#state{from_wait_for_empty_buffer = undefined};
        false ->
            State2
    end.


send_next_key(Socket, SequenceNumber, Key, CapsLockEnabled) ->
    Data = key_to_data(Key, CapsLockEnabled),
    io:format("Sending ~p~n", [Data]),
    DataLength = size(Data),
    RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<DataLength:32/big>>,
        <<16#FFFFFFFF:32/unsigned-big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>     % Setup data
    ],
    ok = gen_tcp:send(Socket, [RespPrefix, Data]).

key_to_data(escape, _) ->
    <<1, 0, 16#29, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(ctrl_a, _) ->
    <<1, 0, 4, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(ctrl_c, _) ->
    <<1, 0, 6, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(ctrl_s, _) ->
    <<1, 0, 22, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(caps_lock, _) ->
    <<0, 0, 16#39, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(none, _) ->
    <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(power, _) ->
    <<0, 0, 0, 0, 0, 0, 0, 0, 1, 0>>;
key_to_data(sleep, _) ->
    <<0, 0, 0, 0, 0, 0, 0, 0, 1, 0>>;
key_to_data(Letter, CapsLockEnabled) when Letter >= $A andalso Letter =< $Z ->
    Shift = press_shift(CapsLockEnabled),
    ScanCode = letter_to_scancode(Letter),
    << Shift:8, 0, ScanCode:8, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(Letter, CapsLockEnabled)  when Letter >= $a andalso Letter =< $z ->
    Shift = no_shift(CapsLockEnabled),
    ScanCode = letter_to_scancode(Letter),
    << Shift:8, 0, ScanCode:8, 0, 0, 0, 0, 0, 0, 0>>;
key_to_data(N, _) ->
    ScanCode = key_to_scancode(N),
    <<0, 0, ScanCode, 0, 0, 0, 0, 0, 0, 0>>.

press_shift(false) ->
    16#20;
press_shift(true) ->
    16#00.

no_shift(false) ->
    16#00;
no_shift(true) ->
    16#20.

letter_to_scancode(Value) when Value == $A orelse Value == $a ->
    4;
letter_to_scancode(Value) when Value == $B orelse Value == $b ->
    5;
letter_to_scancode(Value) when Value == $C orelse Value == $c ->
    6;
letter_to_scancode(Value) when Value == $D orelse Value == $d ->
    7;
letter_to_scancode(Value) when Value == $E orelse Value == $e ->
    8;
letter_to_scancode(Value) when Value == $F orelse Value == $f ->
    9;
letter_to_scancode(Value) when Value == $G orelse Value == $g ->
    10;
letter_to_scancode(Value) when Value == $H orelse Value == $h ->
    11;
letter_to_scancode(Value) when Value == $I orelse Value == $i ->
    12;
letter_to_scancode(Value) when Value == $J orelse Value == $j ->
    13;
letter_to_scancode(Value) when Value == $K orelse Value == $k ->
    14;
letter_to_scancode(Value) when Value == $L orelse Value == $l ->
    15;
letter_to_scancode(Value) when Value == $M orelse Value == $m ->
    16;
letter_to_scancode(Value) when Value == $N orelse Value == $n ->
    17;
letter_to_scancode(Value) when Value == $O orelse Value == $o ->
    18;
letter_to_scancode(Value) when Value == $P orelse Value == $p ->
    19;
letter_to_scancode(Value) when Value == $Q orelse Value == $q ->
    20;
letter_to_scancode(Value) when Value == $R orelse Value == $r ->
    21;
letter_to_scancode(Value) when Value == $S orelse Value == $s ->
    22;
letter_to_scancode(Value) when Value == $T orelse Value == $t ->
    23;
letter_to_scancode(Value) when Value == $U orelse Value == $u ->
    24;
letter_to_scancode(Value) when Value == $V orelse Value == $v ->
    25;
letter_to_scancode(Value) when Value == $W orelse Value == $w ->
    26;
letter_to_scancode(Value) when Value == $X orelse Value == $x ->
    27;
letter_to_scancode(Value) when Value == $Y orelse Value == $y ->
    28;
letter_to_scancode(Value) when Value == $Z orelse Value == $z ->
    29;
letter_to_scancode(_) ->
    0.

key_to_scancode($\t) ->
    16#2B;
key_to_scancode($ ) ->
    16#2C;
key_to_scancode($\n) ->
    16#28;
key_to_scancode($=) ->
    16#67;
key_to_scancode($1) ->
    16#1E;
key_to_scancode($2) ->
    16#1F;
key_to_scancode($3) ->
    16#20;
key_to_scancode($4) ->
    16#21;
key_to_scancode($5) ->
    16#22;
key_to_scancode($6) ->
    16#23;
key_to_scancode($7) ->
    16#24;
key_to_scancode($8) ->
    16#25;
key_to_scancode($9) ->
    16#26;
key_to_scancode($0) ->
    16#27;
key_to_scancode($-) ->
    16#56;
key_to_scancode($#) ->
    16#CC;
key_to_scancode(_) ->
    0.


any_to_scancode(X) when is_integer(X) ->
    case letter_to_scancode(X) of
        0 ->
            case key_to_scancode(X) of
                0 ->
                    X;
                S1 ->
                    S1
            end;
        S2 ->
            S2
    end;
any_to_scancode(X) ->
    X.

%% @doc If there is the same key twice, insert a none
filter_keys(Keys) ->
    lists:reverse(filter_keys_internal(Keys, [])).

filter_keys_internal([], Acc) ->
    Acc;
filter_keys_internal([A | [B | T]], Acc) ->
    case any_to_scancode(A) == any_to_scancode(B) of
        true ->
            filter_keys_internal([B | T], [none | [A | Acc]]);
        false ->
            filter_keys_internal([B | T], [A | Acc])
    end;
filter_keys_internal([H | T], Acc) ->
    filter_keys_internal(T, [H | Acc]).
