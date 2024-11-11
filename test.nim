import std/[envvars, json]

import src/client


proc postgres_changes_callback(payload: JsonNode) =
  echo "postgres_changes_callback!"
  echo payload


proc delete_callback(payload: JsonNode) =
  echo "delete statement reached!"
  echo payload


proc broadcast_callback(payload: JsonNode) =
  echo "broadcast: ", payload


proc main() =
  let
    url = getEnv("SUPABASE_URL")
    key = getEnv("SUPABASE_KEY")
    rclient = newRealtimeClient(url, key, auto_reconnect = true)
  var
    chan  = rclient.setChannel("pg-test", broadcast_config)
    chan2 = rclient.setChannel("broadcast_test", broadcast_config)
  defer: rclient.close()

  rclient.join(chan)
  chan.on_postgres_changes(PostgresChanges.INSERT, postgres_changes_callback, filter="item=eq.10")
  chan.on_postgres_changes(PostgresChanges.DELETE, delete_callback)
  rclient.subscribe(chan)

  rclient.join(chan2)
  chan2.on_broadcast("event_test", broadcast_callback)
  rclient.subscribe(chan2)

  for i in 0 .. 10:
    rclient.send_broadcast(chan2, "event_test", %*{"data": "pong - " & $i})

  rclient.listen()


when isMainModule:
  main()
