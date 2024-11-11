# Websockets-based client for Elixir Phoenix Channels,
# that also implements a Supabase Realtime client on top.
# Elixir Phoenix Channels are basically just a websocket.
import whisky # https://github.com/guzba/whisky 0.1.3
import std/[assertions, tables, json]
from std/strutils import strip


type
  PostgresChanges* {.pure.} = enum
    ALL = "*"
    INSERT = "INSERT"
    DELETE = "DELETE"
    UPDATE = "UPDATE"

  RealtimeChannelConfig {.pure.} = enum
    broadcast = "broadcast"
    presence = "presence"

  ChannelEvents {.pure.} = enum
    `close` = "phx_close"
    error = "phx_error"
    join = "phx_join"
    reply = "phx_reply"
    leave = "phx_leave"
    heartbeat = "heartbeat"
    access_token = "access_token"
    broadcast = "broadcast"
    presence = "presence"

  RealtimeChannelOptions = object
    case config: RealtimeChannelConfig
    of broadcast:
      ack, self: bool
    of presence:
      key: string
    private: bool

  Callback = proc(arg: JsonNode)
  # SubscriberStateCallback = proc(state: RealTimeSubscribeState)
  CallbackListener = tuple[event: string, callback: Callback]

  Binding = object
    `type`: string
    filter: Table[string, string]
    callback: Callback

  Hook = ref object
    status: string
    callback: Callback

  Channel = ref object
    topic: string
    params: RealtimeChannelOptions
    listeners: seq[CallbackListener]
    joined: bool
    state: ChannelStates
    bindings: Table[string, seq[Binding]]
    join_push: AsyncPush

  AsyncPush = ref object
    event: string
    ref_event: string
    payload: JsonNode
    received_resp: JsonNode
    ref_hook: seq[Hook]
    reference: ref int

  RealtimeClient* = ref object
    channels*: TableRef[string, Channel]
    url*: string
    access_token: string
    client: WebSocket
    auto_reconnect: bool
    initial_backoff: float = 1.0
    max_retries: Positive = 5.Positive
    timeout: int = -1
    reference: int

  ChannelStates {.pure.} = enum
    joined = "joined"
    closed = "closed"
    errored = "errored"
    joining = "joining"
    leaving = "leaving"

  # RealTimeSubscribeState {.pure.} = enum
  #   subscribed = "subscribed"
  #   timed_out = "timed_out"
  #   closed = "closed"
  #   channel_error = "channel_error"

  # RealTimePresenceListenEvents {.pure.} = enum
  #   sync = "sync"
  #   join = "join"
  #   leave = "leave"


const
  # DEFAULT_TIMEOUT = 10
  PHOENIX_CHANNEL = "phoenix"
  RealtimePostgresChangesListenEvent = ["*", "INSERT", "DELETE", "UPDATE"]


template connect*(self: RealtimeClient) =
  self.client = newWebSocket(self.url & "/websocket?apikey=" & self.access_token)


proc newRealtimeClient*(url, token: string; channels = newTable[string, Channel](); auto_reconnect = false; timeout = -1): RealtimeClient =
  assert url.len > 0, "url must be a valid HTTP URL string"
  assert token.len > 0, "token must be a valid JWT string"
  result = RealtimeClient(url: url, channels: channels, initial_backoff: 1.0, max_retries: 5, access_token: token, auto_reconnect: auto_reconnect, timeout: timeout)
  result.connect()


proc close*(self: RealtimeClient) =
  self.client.close()


template broadcast_config*(): RealtimeChannelOptions =
  RealtimeChannelOptions(config: RealtimeChannelConfig.broadcast)


proc receive(self: AsyncPush; status: string; callback: proc(payload: JsonNode)) =
  if not self.received_resp.isNil:
    echo self.received_resp
  self.ref_hook.add Hook(status: status, callback: callback)


proc initAsyncPush(event: string; payload: RealtimeChannelOptions): AsyncPush =
  AsyncPush(event: event, payload: %*{})


proc on(self: Channel; topic: string; filter = initTable[string, string](); callback: Callback) =
  if topic notin self.bindings:
    self.bindings[topic] = @[]
  self.bindings[topic].add Binding(`type`: topic, filter: filter, callback: callback)


proc resend(self: RealtimeClient; channel: Channel; push: AsyncPush) =
  inc self.reference
  push.ref_event = "chan_reply_"
  push.ref_event.addInt self.reference
  var message = %*{
    "topic": channel.topic,
    "event": push.event,
    "payload": push.payload,
    "ref": nil,
  }
  proc on_reply(payload: JsonNode) =
    push.received_resp = payload

  channel.on(push.ref_event, callback = on_reply)
  self.client.send $message


proc trigger(self: Channel; topic: string; payload: JsonNode; reference: string) =
  let payload_fields = payload.getFields
  if topic in self.bindings:
    for binding in self.bindings[topic]:
      case topic
      of "postgres_changes":
        var
          binding_event = binding.filter.getOrDefault("event")
          data_type = payload_fields["data"].getFields()["type"].getStr

        if binding_event == data_type:
          binding.callback(payload)
      of "broadcast":
        var
          binding_event = binding.filter.getOrDefault("event")
          payload_event = payload_fields["event"].getStr

        if binding_event == payload_event:
          binding.callback(payload_fields["payload"])
      else:
        echo "TOPIC:\t", topic # Unhandled topic???


proc setChannel*(self: RealtimeClient; topic: string; params: RealtimeChannelOptions): Channel =
  if topic.len > 0:
    let channel_topic = "realtime:" & topic
    var channel = Channel(topic: channel_topic, params: params, join_push: initAsyncPush($ChannelEvents.join, params))
    proc on_join_push_ok(payload: JsonNode) =
      channel.state = ChannelStates.joined
      self.resend(channel, channel.join_push)

    channel.join_push.receive("ok", on_join_push_ok)
    self.channels[channel_topic] = channel
    proc on_reply(payload: JsonNode) =
      channel.trigger("chan_reply_" & $self.reference, payload, $self.reference)

    channel.on($ChannelEvents.reply, callback = on_reply)
    result = channel


proc getChannels*(self: RealtimeClient): seq[Channel] =
  for item in self.channels.values:
    result.add item


proc removeChannel*(self: RealtimeClient; channel: Channel) =
  if channel.topic in self.channels:
    self.channels.del channel.topic

  if self.channels.len == 0:
    #close
    discard


proc summary*(self: RealtimeClient) =
  for topic, chans in self.channels.pairs:
    for event in chans.listeners:
      echo "Topic ", topic, " | Event ", event


template rejoin(self: RealtimeClient; channel: Channel) =
  channel.state = ChannelStates.joining
  proc on_join_push_ok(payload: JsonNode) =
    echo "on_join_push_ok\n", payload
  channel.join_push.receive("ok", on_join_push_ok)
  self.resend(channel, channel.join_push)


template update_payload(self: AsyncPush; payload: JsonNode) =
  self.payload = payload


proc subscribe*(self: RealtimeClient; channel: Channel) =
  if not self.client.isNil:
    var
      params = channel.params
      config = params.config
      broadcast = %*{}
      presence = %*{}

    if config == RealtimeChannelConfig.broadcast:
      broadcast = %*{"ack": params.ack, "self": params.self}
    else:
      presence = %*{"key": params.key}

    var filters: seq[Table[string, string]]

    if "postgres_changes" in channel.bindings:
      for item in channel.bindings["postgres_changes"]:
        filters.add item.filter

    let payload = %*{
      "config": %*{
        "private": params.private,
        "broadcast": broadcast,
        "presence": presence,
        "postgres_changes": %filters
      },
      "access_token": self.access_token
    }
    channel.join_push.update_payload(payload)
    self.rejoin(channel)


proc join*(self: RealtimeClient; channel: Channel) =
  var message = %*{"topic": channel.topic, "event": "phx_join", "ref": nil, "payload": %*{"config": channel.params}}
  self.client.send $message


template rejoin =
  if self.auto_reconnect:
    echo "Connection with server closed, trying to reconnect..."
    self.connect()
    for channel in self.channels.values:
      self.rejoin(channel)
  else:
    echo "Connection with the server closed."
    break


template retry(code: untyped) =
  while true:
    try:
      code
    except:
      rejoin()


template heartbeat_message(): JsonNode =
  %*{
    "topic": PHOENIX_CHANNEL,
    "event": ChannelEvents.heartbeat,
    "payload": {},
    "ref": nil
  }


proc listen*(self: RealtimeClient): auto =
  var
    raw_msg: Option[Message]
    json_msg: JsonNode
    channel: Channel
    payload: JsonNode

  retry:
    raw_msg = self.client.receiveMessage(timeout = self.timeout)
    json_msg = parseJson(raw_msg.get.data)
    if json_msg["topic"].getStr in self.channels:
      channel = self.channels[json_msg["topic"].getStr]
      payload = json_msg["payload"]
      channel.trigger(json_msg["event"].getStr, payload, json_msg["ref"].getStr)
    self.client.send $heartbeat_message


proc on_postgres_changes*(self: Channel; event: PostgresChanges; callback: Callback; table = "*", schema = "public", filter = "") =
  if $event in RealtimePostgresChangesListenEvent:
    var bindings_filters = {"event": $event, "schema": schema, "table": table}.toTable
    if filter.strip.len > 0:
      bindings_filters["filter"] = filter
    self.on("postgres_changes", filter = bindings_filters, callback)


proc on_broadcast*(self: Channel; event: string; callback: Callback) =
  self.on("broadcast", {"event": event}.toTable, callback)


proc send_broadcast*(self: RealtimeClient; channel: Channel; event: string; payload: JsonNode) =
  channel.join_push.event = $ChannelEvents.broadcast
  channel.join_push.payload = %*{"type": "broadcast", "event": event, "payload": payload}
  self.resend(channel, channel.join_push)
