# ts-appc-metrics

A Python script that surfaces traffic metrics for Tailscale [App Connectors](https://tailscale.com/kb/1281/app-connectors) from network logs. Everything displayed is derived directly from log data — no assumptions are made about backend routes, DNS names, or traffic beyond what the logs record.

## How it works

The script queries three Tailscale API endpoints:

| Step | API call | Purpose |
|------|----------|---------|
| 1 | `GET /tailnet/{tailnet}/acl` | Parse `nodeAttrs` to discover which app connectors exist and which tags identify their nodes |
| 2 | `GET /tailnet/{tailnet}/devices` | Match connector tags to actual device names for display in the report header |
| 3 | `GET /tailnet/{tailnet}/network-logs` | Fetch raw network-log windows for the selected time range |

### Log processing

Tailscale network logs arrive in 5-second windows. The script filters entries where the destination node's tags match the selected connector, then processes the `virtualTraffic` flows within those entries (proto 99 keepalives are excluded).

Each `virtualTraffic` flow records:
- `src` — source IP:port (the user's device)
- `dst` — connector endpoint IP:port (what the user connected to on the connector node)
- `proto` — IP protocol number
- `txBytes` / `rxBytes` — bytes transferred in this 5-second window

Flows with the same `(src, dst, proto)` key appearing across multiple windows are deduplicated: `txBytes` and `rxBytes` are kept at their observed maximum, and the time range is widened to cover all windows.

Flows are then grouped by originating Tailscale user (`srcNode.user`).

### Report sections

| Section | What it shows |
|---------|--------------|
| **Connections** | Each unique connection seen in logs: source user, source IP:port, connector endpoint IP:port, first-seen timestamp |
| **Per-user summary** | Totals per user: connection count, TX bytes, RX bytes, time range |
| **Per-user flow detail** | Full flow table per user with timestamps, protocol, source, connector endpoint, TX/RX bytes |
| **Raw log entries** | Every matching 5-second log window with virtual and physical traffic detail exactly as logged |

TX and RX are as recorded in the log entry for the user→connector leg. What happens beyond the connector is not visible in the logs and is not reported.

## Requirements

- Python 3.8+ (stdlib only — no third-party packages needed)
- A Tailscale API key with network-log read access

## Setup

Export your API key:

```bash
export TS_API_KEY="tskey-api-..."
```

## Usage

### Interactive mode (default)

Prompts you to select an app connector (if multiple exist) and a time range:

```bash
python3 ts-appc-metrics.py
```

### Non-interactive — hours back

```bash
python3 ts-appc-metrics.py --hours 6
```

### Non-interactive — explicit time range

```bash
python3 ts-appc-metrics.py --start 2026-04-19T08:00:00.000Z --end 2026-04-19T16:00:00.000Z
```

### Target a different tailnet

```bash
python3 ts-appc-metrics.py --tailnet my-tailnet.ts.net --hours 24
```

### JSON output

Dump the raw metrics as JSON instead of the human-readable report:

```bash
python3 ts-appc-metrics.py --hours 1 --json | jq .
```

## CLI reference

| Flag | Default | Description |
|------|---------|-------------|
| `--tailnet` | `TwdXJAaTG221CNTRL` | Tailnet name or organisation |
| `--hours N` | — | Query the last N hours (skips the interactive time prompt) |
| `--start ISO` | — | Start of query window (ISO 8601 UTC). Requires `--end` |
| `--end ISO` | — | End of query window (ISO 8601 UTC). Requires `--start` |
| `--json` | off | Emit JSON instead of the formatted report |

## Example output (truncated)

```
══════════════════════════════════════════════════════════════════════════════
  App Connector  : my-internal-app
  Domains        : app.internal.example.com
  Tags           : tag:app-connector
  Node           : connector-node-1
  Period         : 2026-04-19T08:00:00.000Z  →  2026-04-19T16:00:00.000Z
══════════════════════════════════════════════════════════════════════════════

  ▼  CONNECTIONS  (as recorded in network logs)
     Connector node(s): connector-node-1
  ──────────────────────────────────────────────────────────────────────────
  Source User                          Source IP:Port             Connector Endpoint         First Seen
  ──────────────────────────────────────────────────────────────────────────
  alice@example.com                    100.64.1.2:54321           100.64.2.1:443             2026-04-19T09:01:05.000Z
  bob@example.com                      100.64.1.3:49123           100.64.2.1:443             2026-04-19T11:30:22.000Z
  ──────────────────────────────────────────────────────────────────────────
  TOTAL unique connections                          2

  ▼  PER-USER SUMMARY
  ──────────────────────────────────────────────────────────────────────────
  User                                  Connections                TX                RX              First Seen                Last Seen
  alice@example.com                               3          12.3 KB          198.4 KB    2026-04-19T09:01:05Z    2026-04-19T14:22:10Z
  bob@example.com                                 1           1.1 KB           45.0 KB    2026-04-19T11:30:22Z    2026-04-19T11:30:55Z
```

## References

- [Tailscale App Connectors](https://tailscale.com/kb/1281/app-connectors)
- [Tailscale Network Logs API](https://tailscale.com/api#tag/logging/GET/tailnet/%7Btailnet%7D/network-logs)
- [Tailscale API authentication](https://tailscale.com/api#section/Authentication)
