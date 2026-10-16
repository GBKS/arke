# arke-agent-mcp

A stdio MCP server that lets Claude Desktop ask Arké to pay a Lightning invoice. The payment is
approved on the phone. See `Docs/Features/Agent_Payments.md`.

No dependencies: it needs Node 18 or newer, nothing to install.

## Setup

1. In Arké Desktop and Arké on the phone, turn on **Settings → Experimental → Agent payments**.
   Keep Arké open on the phone; the Mac's setting should say "Connected: …".
2. Add the server to Claude Desktop's `~/Library/Application Support/Claude/claude_desktop_config.json`.
   Claude Desktop doesn't see nvm's PATH, so use the absolute path to `node`:

   ```json
   {
     "mcpServers": {
       "arke": {
         "command": "/Users/christoph/.nvm/versions/node/v22.12.0/bin/node",
         "args": ["/Users/christoph/workspace/Arke/Tools/agent-mcp/arke-agent-mcp.mjs"]
       }
     }
   }
   ```

3. Restart Claude Desktop. The tools `request_payment` and `get_payment_status` appear under the
   tools menu.

## Tools

| Tool | Input | Result |
|---|---|---|
| `request_payment` | `invoice`, `reason` | Waits up to 45 s; `paid` with `preimage` + `paymentHash`, `declined`, `refused`, `failed`, or `pending` with a `request_id` |
| `get_payment_status` | `request_id` | Same fields |
| `http_request` | `url`, optional `method` (GET/POST), optional JSON `body` | Status, content type, body (max 100 KB). For reading a merchant's `llms.txt` and placing orders. Public https only: loopback, private and link-local addresses are refused, also after redirects |

Claude's own web fetch can't open links it found inside a page, and its code sandbox can't reach
arbitrary domains, so `http_request` is how it orders. For the demo, turn off any browser MCP
(e.g. Puppeteer) in Claude Desktop so it doesn't reach for that instead.

## Testing without Claude

The Mac's loopback API (every request needs the `X-Arke-Agent` header):

```sh
curl -s -H 'X-Arke-Agent: 1' http://127.0.0.1:48211/agent/status

INVOICE=$(curl -s 'https://doghouse.arke.cash/api/orders/new?item=bone' | jq -r .invoice)
curl -s -H 'X-Arke-Agent: 1' -H 'Content-Type: application/json' \
  -d "{\"invoice\": \"$INVOICE\", \"reason\": \"A bone for Byte\"}" \
  http://127.0.0.1:48211/agent/payments
curl -s -H 'X-Arke-Agent: 1' "http://127.0.0.1:48211/agent/payments/<id>?wait=45"
```

Or drive the MCP server directly:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node arke-agent-mcp.mjs
```

Environment overrides: `ARKE_AGENT_API` (default `http://127.0.0.1:48211`), `ARKE_AGENT_WAIT`
(seconds, default 45).
