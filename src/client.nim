# Websockets-based client for Elixir Phoenix Channels,
# that also implements a Supabase Realtime client on top.
# Elixir Phoenix Channels are basically just a websocket.
import whisky

type
  RealtimeClient* = object
    client: WebSocket
    url: string

  SREvents* {.pure.} = enum
    close     = "phx_close"
    error     = "phx_error"
    join      = "phx_join"
    reply     = "phx_reply"
    leave     = "phx_leave"
    heartbeat = "heartbeat"

proc close*(self: RealtimeClient) {.inline.} = self.client.close()

func connect*(self: RealtimeClient) {.inline.} = discard  # Do nothing.

proc newRealtimeClient*(url: string): RealtimeClient = RealtimeClient(url: url, client: newWebSocket(url))

proc listen*(self: RealtimeClient): auto =
  discard

proc setChannel*(self: RealtimeClient; topic: string): auto =
  discard

proc summary*(self: RealtimeClient) =
  discard
