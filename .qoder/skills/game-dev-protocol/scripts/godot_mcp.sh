#!/bin/bash
# godot_mcp.sh — call Godot AI MCP tools over streamable HTTP (editor must be running).
# usage: godot_mcp.sh <tool_name> ['<json-args>']
#   godot_mcp.sh editor_state
#   godot_mcp.sh node_find '{"type":"CSGPolygon3D"}'
#   godot_mcp.sh filesystem_manage '{"op":"scan"}'
#   godot_mcp.sh --list                 list real tool names + their op enums (never guess names)
#   godot_mcp.sh --schema <tool>        print one tool's description + full inputSchema
URL="http://127.0.0.1:8000/mcp"
STATE_DIR="${TMPDIR:-/tmp}/godot_ai_mcp"
mkdir -p "$STATE_DIR"
SID_FILE="$STATE_DIR/session_id"

init() {
  SID=$(curl -s -D - -o /dev/null -X POST "$URL" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"godot-mcp-sh","version":"1.0"}}}' \
    | grep -i '^mcp-session-id:' | tr -d '\r' | awk '{print $2}')
  if [ -z "$SID" ]; then echo "ERROR: MCP init failed. Is the Godot editor open and the Godot AI plugin server running on port 8000?"; exit 1; fi
  echo "$SID" > "$SID_FILE"
  curl -s -o /dev/null -X POST "$URL" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Mcp-Session-Id: $SID" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
}

# post <json-body> — re-initialises once if the session went stale.
post() {
  local body="$1" out
  [ -z "$(cat "$SID_FILE" 2>/dev/null)" ] && init
  out=$(curl -s -X POST "$URL" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Mcp-Session-Id: $(cat "$SID_FILE")" -d "$body")
  if echo "$out" | grep -q 'session expired'; then
    init
    out=$(curl -s -X POST "$URL" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -H "Mcp-Session-Id: $(cat "$SID_FILE")" -d "$body")
  fi
  printf '%s' "$out"
}

# Response bodies go through a temp file, not argv or stdin: tools/list is ~90 KB
# (over the Windows command-line limit) and the python heredoc already owns stdin.
RESP_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE"' EXIT

# rpc <json-body> <mode> [want]
rpc() {
  post "$1" > "$RESP_FILE"
  python - "$RESP_FILE" "$2" "${3:-}" <<'PYEOF'
import sys, json

path, mode, want = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path, encoding="utf-8", errors="replace").read()
datas = [l for l in raw.splitlines() if l.startswith("data: ")]
if not datas:
    print("ERROR: no SSE response from MCP server."); print(raw[:400]); sys.exit(1)
try:
    d = json.loads(datas[0][6:])
except Exception:
    print("ERROR: unparsable response:"); print(raw[:400]); sys.exit(1)
if "error" in d:
    print("ERROR:", json.dumps(d["error"], ensure_ascii=False)[:600]); sys.exit(1)

if mode in ("list", "schema"):
    tools = d.get("result", {}).get("tools", [])
    if mode == "list":
        print("%d tools registered:" % len(tools))
        for t in tools:
            props = t.get("inputSchema", {}).get("properties", {}) or {}
            ops = (props.get("op") or {}).get("enum")
            args = [k for k in props if k not in ("op", "session_id")]
            line = "- " + t["name"]
            if ops:
                line += "  op: " + "|".join(ops)
            elif args:
                line += "  args: " + ",".join(args)
            print(line)
        sys.exit(0)
    hit = [t for t in tools if t["name"] == want]
    if not hit:
        print("ERROR: no tool named %r. Run --list for the %d real names." % (want, len(tools)))
        sys.exit(1)
    t = hit[0]
    print("=== %s ===" % t["name"])
    print((t.get("description") or "").strip())
    print("\ninputSchema:")
    print(json.dumps(t.get("inputSchema", {}), ensure_ascii=False, indent=2))
    sys.exit(0)

r = d.get("result", {})
if r.get("isError"):
    print("TOOL_ERROR:", (r.get("content") or [{}])[0].get("text", "")[:600]); sys.exit(1)
sc = r.get("structuredContent")
if sc is not None:
    print(json.dumps(sc, ensure_ascii=False))
else:
    for c in r.get("content", []):
        print(c.get("text", ""))
PYEOF
}

[ -z "$1" ] && { echo "usage: godot_mcp.sh <tool_name> ['<json-args>'] | --list | --schema <tool>"; exit 2; }

case "$1" in
  --list)
    rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' list
    ;;
  --schema)
    [ -z "$2" ] && { echo "usage: godot_mcp.sh --schema <tool_name>"; exit 2; }
    rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' schema "$2"
    ;;
  *)
    TOOL="$1"
    if [ -z "$2" ]; then ARGS='{}'; else ARGS="$2"; fi
    rpc "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"$TOOL\",\"arguments\":$ARGS}}" call
    ;;
esac
