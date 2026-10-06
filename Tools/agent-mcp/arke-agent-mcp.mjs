#!/usr/bin/env node
//
// arke-agent-mcp — stdio MCP server for Arké agent payments
// (Docs/Features/Agent_Payments.md §3.1 and §6).
//
// Claude Desktop starts this script; it turns two tools into calls to the
// Arké Desktop loopback API on 127.0.0.1. The Mac forwards each request to
// the phone, where the person approves it. No dependencies: needs Node 18+
// (built-in fetch). MCP over stdio is newline-delimited JSON-RPC 2.0.
//

import { createInterface } from "node:readline";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";

const API = process.env.ARKE_AGENT_API ?? "http://127.0.0.1:48211";
const WAIT_SECONDS = Number(process.env.ARKE_AGENT_WAIT ?? 45);
const SERVER_INFO = { name: "arke-agent-payments", version: "0.1.0" };
const DEFAULT_PROTOCOL = "2025-06-18";

const TERMINAL = new Set(["paid", "declined", "refused", "failed", "expired"]);

const MAX_RESPONSE_BYTES = 100_000;
const MAX_REDIRECTS = 3;

const TOOLS = [
  {
    name: "http_request",
    description:
      "Make an HTTPS GET or POST request from the user's Mac. Use this to read a merchant's llms.txt, " +
      "menu or API docs and to place orders, instead of a browser or web fetch. Public https URLs only. " +
      "Returns the status, content type and body (truncated to 100 KB). To pay an invoice it returns, " +
      "use request_payment.",
    inputSchema: {
      type: "object",
      properties: {
        method: { type: "string", enum: ["GET", "POST"], description: "Defaults to GET." },
        url: { type: "string", description: "An https:// URL." },
        body: { type: "object", description: "JSON body for POST requests." },
      },
      required: ["url"],
    },
  },
  {
    name: "request_payment",
    description:
      "Ask the user's Arké wallet to pay a BOLT11 Lightning invoice. The request appears on the user's Mac " +
      "and must be approved on their phone with Face ID, so it can take a while. Waits up to " +
      `${WAIT_SECONDS} seconds. Returns state "paid" with preimage and paymentHash (hex) as proof of payment ` +
      "(sha256(preimage) == paymentHash), or declined / refused / failed with a message, or pending with a " +
      "request_id to pass to get_payment_status. Signet only.",
    inputSchema: {
      type: "object",
      properties: {
        invoice: { type: "string", description: "The BOLT11 invoice to pay (lntbs… on signet)." },
        reason: {
          type: "string",
          description: "One short sentence telling the user what this payment is for. Shown on the phone as unverified.",
        },
      },
      required: ["invoice", "reason"],
    },
  },
  {
    name: "get_payment_status",
    description:
      "Check a payment started with request_payment. Waits up to " +
      `${WAIT_SECONDS} seconds for it to finish. Returns the same fields as request_payment.`,
    inputSchema: {
      type: "object",
      properties: {
        request_id: { type: "string", description: "The request_id returned by request_payment." },
      },
      required: ["request_id"],
    },
  },
];

// MARK: - Loopback API

async function api(path, options = {}) {
  let response;
  try {
    response = await fetch(`${API}${path}`, {
      ...options,
      headers: { "Content-Type": "application/json", "X-Arke-Agent": "1", ...(options.headers ?? {}) },
      signal: AbortSignal.timeout((WAIT_SECONDS + 15) * 1000),
    });
  } catch (error) {
    return {
      error: "app_not_running",
      message: "Couldn't reach Arké on this Mac. Open Arké and turn on Settings → Experimental → Agent payments.",
    };
  }
  try {
    return await response.json();
  } catch {
    return { error: "bad_response", message: `Arké answered with HTTP ${response.status}.` };
  }
}

function summarize(record) {
  if (record.error && !record.state) {
    return { state: "error", error: record.error, message: record.message };
  }
  const result = { request_id: record.id, state: record.state };
  for (const key of ["amountSats", "description", "preimage", "paymentHash", "feeSats", "error", "message"]) {
    if (record[key] !== undefined) result[key] = record[key];
  }
  if (!TERMINAL.has(record.state)) {
    result.state = "pending";
    result.message = "Still waiting for the user to approve on their phone. Call get_payment_status with this request_id.";
  }
  return result;
}

async function requestPayment({ invoice, reason }) {
  const created = await api("/agent/payments", {
    method: "POST",
    body: JSON.stringify({ invoice, reason: reason ?? "", agent: "Claude" }),
  });
  if (!created.id) return summarize(created);
  const record = await api(`/agent/payments/${created.id}?wait=${WAIT_SECONDS}`);
  return summarize(record.id ? record : created);
}

async function getPaymentStatus({ request_id }) {
  return summarize(await api(`/agent/payments/${encodeURIComponent(request_id)}?wait=${WAIT_SECONDS}`));
}

// MARK: - HTTP for merchants

// Refuse loopback, private, link-local and similar addresses, so a prompt
// injection can't point the agent at the Mac's own payment API or the local
// network. Checked after DNS resolution and again on every redirect.
function isPrivateAddress(address) {
  const ip = address.toLowerCase().replace(/^::ffff:/, "");
  if (isIP(ip) === 4) {
    const [a, b] = ip.split(".").map(Number);
    return (
      a === 0 || a === 10 || a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      a >= 224
    );
  }
  return ip === "::" || ip === "::1" || ip.startsWith("fc") || ip.startsWith("fd") || ip.startsWith("fe8") ||
    ip.startsWith("fe9") || ip.startsWith("fea") || ip.startsWith("feb");
}

async function checkURL(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    return { error: "invalid_url", message: "That isn't a valid URL." };
  }
  if (url.protocol !== "https:") {
    return { error: "https_only", message: "Only https:// URLs are allowed." };
  }
  const host = url.hostname.replace(/^\[|\]$/g, "");
  let addresses;
  try {
    addresses = isIP(host) ? [{ address: host }] : await lookup(host, { all: true });
  } catch {
    return { error: "dns_failed", message: `Couldn't resolve ${host}.` };
  }
  if (addresses.length === 0 || addresses.some(({ address }) => isPrivateAddress(address))) {
    return { error: "private_address", message: "Requests to local or private network addresses aren't allowed." };
  }
  return { url };
}

async function httpRequest({ method = "GET", url, body }) {
  method = String(method).toUpperCase();
  if (method !== "GET" && method !== "POST") {
    return { error: "bad_method", message: "Only GET and POST are supported." };
  }

  let target = url;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const checked = await checkURL(target);
    if (checked.error) return checked;

    let response;
    try {
      response = await fetch(checked.url, {
        method,
        redirect: "manual",
        headers: {
          "User-Agent": "arke-agent-mcp/0.1",
          Accept: "application/json, text/plain, text/markdown, */*",
          ...(method === "POST" ? { "Content-Type": "application/json" } : {}),
        },
        body: method === "POST" ? JSON.stringify(body ?? {}) : undefined,
        signal: AbortSignal.timeout(20_000),
      });
    } catch (error) {
      return { error: "request_failed", message: String(error?.cause?.message ?? error) };
    }

    const location = response.headers.get("location");
    if (response.status >= 300 && response.status < 400 && location) {
      target = new URL(location, checked.url).toString();
      // A redirected POST turns into a GET, like browsers do
      if (response.status !== 307 && response.status !== 308) method = "GET";
      continue;
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    const truncated = bytes.length > MAX_RESPONSE_BYTES;
    return {
      status: response.status,
      url: checked.url.toString(),
      contentType: response.headers.get("content-type") ?? "",
      body: new TextDecoder().decode(bytes.subarray(0, MAX_RESPONSE_BYTES)),
      ...(truncated ? { truncated: true } : {}),
    };
  }
  return { error: "too_many_redirects", message: "Too many redirects." };
}

// MARK: - JSON-RPC over stdio

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

async function handle(message) {
  const { id, method, params } = message;
  const isRequest = id !== undefined && id !== null;

  switch (method) {
    case "initialize":
      return send({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: params?.protocolVersion ?? DEFAULT_PROTOCOL,
          capabilities: { tools: {} },
          serverInfo: SERVER_INFO,
        },
      });
    case "ping":
      return send({ jsonrpc: "2.0", id, result: {} });
    case "tools/list":
      return send({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
    case "tools/call": {
      const args = params?.arguments ?? {};
      let result;
      if (params?.name === "request_payment") result = await requestPayment(args);
      else if (params?.name === "get_payment_status") result = await getPaymentStatus(args);
      else if (params?.name === "http_request") result = await httpRequest(args);
      else return send({ jsonrpc: "2.0", id, error: { code: -32602, message: `Unknown tool: ${params?.name}` } });

      const isError =
        ["error", "refused", "failed", "declined", "expired"].includes(result.state) ||
        (params.name === "http_request" && result.error !== undefined);
      return send({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], isError },
      });
    }
    default:
      // Notifications (no id) such as notifications/initialized need no answer
      if (isRequest) send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
  }
}

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  }
  handle(message).catch((error) => {
    console.error("arke-agent-mcp:", error);
    if (message.id !== undefined) send({ jsonrpc: "2.0", id: message.id, error: { code: -32603, message: String(error) } });
  });
});
