# Websockets-based client for Elixir Phoenix Channels,
# that also implements a Supabase Realtime client on top.
# Elixir Phoenix Channels are basically just a websocket.
import whisky  # https://github.com/guzba/whisky

type
  RealtimeClient* = object
    url*, channel*: string
    client: WebSocket

  SREvents* {.pure.} = enum
    close     = "phx_close"
    error     = "phx_error"
    join      = "phx_join"
    reply     = "phx_reply"
    leave     = "phx_leave"
    heartbeat = "heartbeat"

proc close*(self: RealtimeClient) {.inline.} = self.client.close()

func connect*(self: RealtimeClient) {.inline.} = discard  # Do nothing?.

proc newRealtimeClient*(url: string): RealtimeClient = RealtimeClient(url: url, client: newWebSocket(url))

template setChannel*(self: RealtimeClient; topic: string) =
  # https://github.com/supabase-community/realtime-py/blob/8bcf6da63e161d7127292a079887952d2c8a2722/realtime/connection.py#L142-L148
  if topic.len > 0: self.channel = topic

proc summary*(self: RealtimeClient) =
  # https://github.com/supabase-community/realtime-py/blob/8bcf6da63e161d7127292a079887952d2c8a2722/realtime/connection.py#L152-L159
  #for topic, chans in self.channels.items():
  #  for chan in chans:
  #    echo "Topic: ", topic, " | Events: ", chan
  discard

proc listen*(self: RealtimeClient): auto =
  # https://github.com/supabase-community/realtime-py/blob/8bcf6da63e161d7127292a079887952d2c8a2722/realtime/connection.py#L59-L66
  discard
