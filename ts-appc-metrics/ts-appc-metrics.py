#!/usr/bin/env python3
"""
Tailscale App Connector Proxy Metrics
Shows traffic observed in network logs for a selected app connector:
  1. Each unique connection (source user, source IP:port, connector endpoint, timestamp)
  2. Per-user summary (connection count, bytes sent/received, time range)
  3. Per-user flow detail (timestamps, protocol, IPs, bytes per connection)
  4. Raw matching log windows

Only data present in the logs is displayed — no assumptions about backend routes
or DNS names are made.

Usage:
    python3 ts-appc-metrics.py [--tailnet TAILNET] [--hours N] [--start ISO] [--end ISO]

Environment:
    TS_API_KEY  Tailscale API key (tskey-api-...)
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

API_BASE = "https://api.tailscale.com/api/v2"
DEFAULT_TAILNET = "TwdXJAaTG221CNTRL"
PROTO_NAMES = {1: "ICMP", 6: "TCP", 17: "UDP", 99: "TS-keepalive"}


# ── API helpers ──────────────────────────────────────────────────────────────

def _b64(s: str) -> str:
    import base64
    return base64.b64encode(s.encode()).decode()


def api_get(path: str, api_key: str) -> dict:
    url = f"{API_BASE}{path}"
    req = Request(url, headers={"Authorization": f"Basic {_b64(api_key + ':')}"})
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode()
        print(f"HTTP {e.code} from {url}: {body}", file=sys.stderr)
        sys.exit(1)
    except URLError as e:
        print(f"Network error: {e.reason}", file=sys.stderr)
        sys.exit(1)


def fetch_logs(tailnet: str, start: str, end: str, api_key: str) -> list:
    data = api_get(f"/tailnet/{tailnet}/network-logs?start={start}&end={end}", api_key)
    return data.get("logs", [])


def fetch_acl(tailnet: str, api_key: str) -> str:
    req = Request(
        f"{API_BASE}/tailnet/{tailnet}/acl",
        headers={"Authorization": f"Basic {_b64(api_key + ':')}"},
    )
    try:
        with urlopen(req) as resp:
            return resp.read().decode()
    except HTTPError as e:
        print(f"HTTP {e.code} fetching ACL", file=sys.stderr)
        sys.exit(1)


def fetch_devices(tailnet: str, api_key: str) -> list:
    data = api_get(f"/tailnet/{tailnet}/devices?fields=all", api_key)
    return data.get("devices", [])


# ── ACL parsing ──────────────────────────────────────────────────────────────

def parse_app_connectors(acl_text: str) -> list:
    text = re.sub(r"//[^\n]*", "", acl_text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"ACL parse error: {e}", file=sys.stderr)
        return []
    connectors = []
    for na in data.get("nodeAttrs", []):
        for c in na.get("app", {}).get("tailscale.com/app-connectors", []):
            connectors.append({
                "name": c.get("name", "(unnamed)"),
                "tags": c.get("connectors", []),
                "domains": c.get("domains", []),
            })
    return connectors


def get_connector_nodes(connector: dict, devices: list) -> list:
    tag_set = set(connector["tags"])
    nodes = []
    for dev in devices:
        if set(dev.get("tags") or []) & tag_set:
            nodes.append({
                "name": dev.get("name", "?").split(".")[0],
                "addresses": dev.get("addresses") or [],
            })
    return nodes


# ── Selection prompts ────────────────────────────────────────────────────────

def select_timeframe() -> tuple:
    """
    Interactively select a time window.
    Returns (start_str, end_str) as ISO 8601 UTC strings.
    """
    now = datetime.now(timezone.utc)

    presets = [
        ("Last 1 hour",   timedelta(hours=1)),
        ("Last 6 hours",  timedelta(hours=6)),
        ("Last 24 hours", timedelta(hours=24)),
        ("Last 7 days",   timedelta(days=7)),
        ("Last 30 days",  timedelta(days=30)),
        ("Custom range",  None),
    ]

    print(file=sys.stderr)
    print("Time range:", file=sys.stderr)
    for i, (label, _) in enumerate(presets):
        print(f"  [{i + 1}] {label}", file=sys.stderr)
    print(file=sys.stderr)

    while True:
        try:
            raw = input(f"Select time range [1-{len(presets)}]: ").strip()
            idx = int(raw) - 1
            if not (0 <= idx < len(presets)):
                print(f"  Please enter a number between 1 and {len(presets)}.", file=sys.stderr)
                continue
            break
        except (ValueError, EOFError):
            print("  Invalid input.", file=sys.stderr)

    label, delta = presets[idx]

    if delta is not None:
        end_dt   = now
        start_dt = now - delta
    else:
        # Custom range
        fmt_hint = "YYYY-MM-DD  or  YYYY-MM-DDTHH:MM  or  YYYY-MM-DDTHH:MM:SS"
        print(f"\n  Enter dates in UTC ({fmt_hint})", file=sys.stderr)

        def parse_dt(prompt: str) -> datetime:
            while True:
                raw = input(prompt).strip()
                for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d"):
                    try:
                        return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
                    except ValueError:
                        pass
                print(f"  Unrecognised format. Use: {fmt_hint}", file=sys.stderr)

        start_dt = parse_dt("  Start: ")
        end_dt   = parse_dt("  End  : ")
        if end_dt <= start_dt:
            print("  End must be after start — swapping.", file=sys.stderr)
            start_dt, end_dt = end_dt, start_dt

    start_str = start_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    end_str   = end_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    print(f"  → {start_str}  to  {end_str}", file=sys.stderr)
    return start_str, end_str


def select_connector(connectors: list) -> dict:
    if not connectors:
        print("No app connectors found in ACL.", file=sys.stderr)
        sys.exit(1)
    if len(connectors) == 1:
        print(f"Using only connector: {connectors[0]['name']}", file=sys.stderr)
        return connectors[0]

    print(file=sys.stderr)
    print("Available app connectors:", file=sys.stderr)
    for i, c in enumerate(connectors):
        domains_str = ", ".join(c["domains"]) if c["domains"] else "(no domains)"
        print(f"  [{i + 1}] {c['name']}", file=sys.stderr)
        print(f"       Domains : {domains_str}", file=sys.stderr)
        print(f"       Tags    : {', '.join(c['tags'])}", file=sys.stderr)
        print(file=sys.stderr)

    while True:
        try:
            raw = input(f"Select connector [1-{len(connectors)}]: ").strip()
            idx = int(raw) - 1
            if 0 <= idx < len(connectors):
                return connectors[idx]
            print(f"  Please enter a number between 1 and {len(connectors)}.", file=sys.stderr)
        except (ValueError, EOFError):
            print("  Invalid input.", file=sys.stderr)


# ── Metrics ──────────────────────────────────────────────────────────────────

def compute_metrics(logs: list, connector: dict):
    """
    Scans for entries where the connector appears in dstNodes and virtualTraffic
    is present.

    Each virtualTraffic flow represents one proxied connection as seen in the
    logs. Per flow we track:
      - src / dst / proto  (as recorded in the log entry)
      - tx_bytes / rx_bytes
      - first_seen / last_seen (UTC window timestamps across all 5s windows)

    Deduplication: same (src, dst, proto) across multiple windows keeps
    max(tx_bytes) and max(rx_bytes) independently, and widens the time range.

    Proto 99 (Tailscale keepalive) is excluded.
    """
    tag_set = set(connector["tags"])
    user_flows: dict = defaultdict(dict)
    matching_entries = []

    for entry in logs:
        dst_tags = set()
        for dn in entry.get("dstNodes", []):
            dst_tags.update(dn.get("tags", []) or [])
        if not dst_tags & tag_set:
            continue

        vt_flows = [vt for vt in entry.get("virtualTraffic", []) if vt.get("proto") != 99]
        if not vt_flows:
            continue

        matching_entries.append(entry)

        src_node = entry.get("srcNode", {})
        user = src_node.get("user") or src_node.get("name", "unknown")
        ws = entry.get("start", "")
        we = entry.get("end",   "")

        for vt in vt_flows:
            proto = vt.get("proto", 0)
            fk = (vt.get("src"), vt.get("dst"), proto)
            tx = vt.get("txBytes", 0)
            rx = vt.get("rxBytes", 0)

            existing = user_flows[user].get(fk)
            if existing is None:
                user_flows[user][fk] = {
                    "src":        vt.get("src"),
                    "dst":        vt.get("dst"),
                    "proto":      proto,
                    "tx_bytes":   tx,
                    "rx_bytes":   rx,
                    "first_seen": ws,
                    "last_seen":  we,
                }
            else:
                if tx > existing["tx_bytes"]:
                    existing["tx_bytes"] = tx
                if rx > existing["rx_bytes"]:
                    existing["rx_bytes"] = rx
                if ws and (not existing["first_seen"] or ws < existing["first_seen"]):
                    existing["first_seen"] = ws
                if we and (not existing["last_seen"]  or we > existing["last_seen"]):
                    existing["last_seen"]  = we

    metrics = {}
    for user, flows in user_flows.items():
        flow_list = sorted(flows.values(), key=lambda f: f.get("first_seen", ""))
        metrics[user] = {
            "connections": len(flow_list),
            "bytes_tx":    sum(f["tx_bytes"] for f in flow_list),
            "bytes_rx":    sum(f["rx_bytes"] for f in flow_list),
            "flows":       flow_list,
            "first_seen":  flow_list[0]["first_seen"]  if flow_list else "",
            "last_seen":   flow_list[-1]["last_seen"]   if flow_list else "",
        }

    return metrics, matching_entries


# ── Output ───────────────────────────────────────────────────────────────────

def human_bytes(n) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def fmt_ts(ts: str) -> str:
    return re.sub(r"(\.\d{3})\d+Z$", r"\1Z", ts)


def print_report(connector, connector_nodes, metrics, entries, start: str, end: str):
    SEP  = "─" * 78
    DSEP = "═" * 78

    print()
    print(DSEP)
    print(f"  App Connector  : {connector['name']}")
    print(f"  Domains        : {', '.join(connector['domains']) or '(none)'}")
    print(f"  Tags           : {', '.join(connector['tags'])}")
    for node in connector_nodes:
        print(f"  Node           : {node['name']}")
    print(f"  Period         : {start}  →  {end}")
    print(DSEP)

    if not metrics:
        print("\n  No proxy traffic found for this connector in the selected period.\n")
        return

    total_conn   = sum(u["connections"] for u in metrics.values())
    total_tx     = sum(u["bytes_tx"]    for u in metrics.values())
    total_rx     = sum(u["bytes_rx"]    for u in metrics.values())

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 1 — CONNECTIONS SEEN IN LOGS
    # ─────────────────────────────────────────────────────────────────────────
    print(f"\n  ▼  CONNECTIONS  (as recorded in network logs)")
    print(f"     Connector node(s): {', '.join(c['name'] for c in connector_nodes) or connector['name']}")
    print(f"  {SEP}")
    print(f"  {'Source User':<36} {'Source IP:Port':<26} {'Connector Endpoint':<26} {'First Seen':>24}")
    print(f"  {SEP}")

    for user, stats in sorted(metrics.items(), key=lambda x: x[1]["connections"], reverse=True):
        for flow in stats["flows"]:
            fs = fmt_ts(flow.get("first_seen", ""))
            print(
                f"  {user:<36} {flow['src']:<26} {flow['dst']:<26} {fs:>24}"
            )

    print(f"  {SEP}")
    print(f"  {'TOTAL unique connections':<36} {total_conn:>6,}")

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 2 — PER-USER SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    print(f"\n\n  ▼  PER-USER SUMMARY")
    print(f"  {SEP}")
    print(f"  {'User':<36} {'Connections':>12}  {'TX':>16}  {'RX':>16}  {'First Seen':>24}  {'Last Seen':>24}")
    print(f"  {SEP}")

    for user, stats in sorted(metrics.items(), key=lambda x: x[1]["connections"], reverse=True):
        fs = fmt_ts(stats.get("first_seen", ""))
        ls = fmt_ts(stats.get("last_seen",  ""))
        print(
            f"  {user:<36} {stats['connections']:>12,}  "
            f"{human_bytes(stats['bytes_tx']):>16}  "
            f"{human_bytes(stats['bytes_rx']):>16}  "
            f"{fs:>24}  {ls:>24}"
        )

    print(f"  {SEP}")
    print(
        f"  {'TOTAL':<36} {total_conn:>12,}  "
        f"{human_bytes(total_tx):>16}  "
        f"{human_bytes(total_rx):>16}"
    )

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 3 — PER-USER FLOW DETAIL
    # ─────────────────────────────────────────────────────────────────────────
    print(f"\n\n  ▼  PER-USER FLOW DETAIL")
    for user, stats in sorted(metrics.items(), key=lambda x: x[1]["connections"], reverse=True):
        print(f"\n  ┌─ {user}  ({stats['connections']} connections)")
        print(f"  │  {'First Seen':>24}  {'Last Seen':>24}  {'Proto':<7}  {'Source IP:Port':<26}  {'Connector Endpoint':<26}  {'TX':>9}  {'RX':>9}")
        print(f"  │  {SEP}")
        for flow in stats["flows"]:
            proto_name = PROTO_NAMES.get(flow["proto"], str(flow["proto"]))
            fs = fmt_ts(flow.get("first_seen", ""))
            ls = fmt_ts(flow.get("last_seen",  ""))
            print(
                f"  │  {fs:>24}  {ls:>24}  {proto_name:<7}  {flow['src']:<26}  {flow['dst']:<26}"
                f"  {human_bytes(flow['tx_bytes']):>9}  {human_bytes(flow['rx_bytes']):>9}"
            )
        print(f"  └{'─' * 76}")

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 4 — RAW LOG ENTRIES
    # ─────────────────────────────────────────────────────────────────────────
    print(f"\n\n  ▼  RAW LOG ENTRIES ({len(entries)} windows — same connection reappears each 5s while active)")
    print(f"  {SEP}")

    for i, entry in enumerate(sorted(entries, key=lambda e: e.get("start", "")), 1):
        src_node  = entry.get("srcNode", {})
        src_name  = src_node.get("name", "?").split(".")[0]
        src_user  = src_node.get("user", "")
        dst_names = [dn.get("name", "?").split(".")[0] for dn in entry.get("dstNodes", [])]
        ws = fmt_ts(entry.get("start", ""))
        we = fmt_ts(entry.get("end",   ""))

        vt_flows = [vt for vt in entry.get("virtualTraffic", []) if vt.get("proto") != 99]
        pt_flows = entry.get("physicalTraffic", [])

        label = src_name + (f"  ({src_user})" if src_user else "")
        print(f"\n  [{i:>4}]  {ws} → {we}")
        print(f"         src  : {label}")
        print(f"         dst  : {', '.join(dst_names)}")

        if vt_flows:
            print(f"         proxy flows ({len(vt_flows)}):")
            for vt in vt_flows:
                proto = PROTO_NAMES.get(vt.get("proto"), str(vt.get("proto")))
                print(
                    f"           {proto:<6}  {vt.get('src','?'):<28} → {vt.get('dst','?'):<28}"
                    f"  tx={vt.get('txPkts',0)}pkts/{human_bytes(vt.get('txBytes',0))}"
                    f"  rx={vt.get('rxPkts',0)}pkts/{human_bytes(vt.get('rxBytes',0))}"
                )

        if pt_flows:
            print(f"         physical paths ({len(pt_flows)}):")
            for pt in pt_flows:
                print(
                    f"           {pt.get('src','?'):<28} → {pt.get('dst','?'):<28}"
                    f"  tx={pt.get('txPkts',0)}pkts  rx={pt.get('rxPkts',0)}pkts"
                )

    print(f"\n  {SEP}\n")


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Tailscale App Connector traffic metrics from network logs",
    )
    parser.add_argument("--tailnet", default=DEFAULT_TAILNET)
    parser.add_argument("--hours",  type=int, default=None, help="Hours back to query (skips interactive prompt)")
    parser.add_argument("--start",  help="Start time ISO 8601")
    parser.add_argument("--end",    help="End time ISO 8601")
    parser.add_argument("--json",   action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("TS_API_KEY")
    if not api_key:
        print("Error: TS_API_KEY environment variable not set.", file=sys.stderr)
        sys.exit(1)

    if args.start and args.end:
        start_str, end_str = args.start, args.end
    elif args.hours:
        now = datetime.now(timezone.utc)
        start_str = (now - timedelta(hours=args.hours)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        end_str   = now.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    else:
        start_str, end_str = select_timeframe()

    print(f"Fetching ACL for {args.tailnet}...", file=sys.stderr)
    acl_text   = fetch_acl(args.tailnet, api_key)
    connectors = parse_app_connectors(acl_text)
    connector  = select_connector(connectors)

    print(f"Fetching devices...", file=sys.stderr)
    devices         = fetch_devices(args.tailnet, api_key)
    connector_nodes = get_connector_nodes(connector, devices)

    print(f"Fetching network logs ({start_str} → {end_str})...", file=sys.stderr)
    logs = fetch_logs(args.tailnet, start_str, end_str, api_key)
    print(f"Retrieved {len(logs):,} log entries.", file=sys.stderr)

    metrics, matching_entries = compute_metrics(logs, connector)

    if args.json:
        print(json.dumps({
            "connector":       connector,
            "connector_nodes": connector_nodes,
            "period":          {"start": start_str, "end": end_str},
            "metrics":         metrics,
            "log_entries":     matching_entries,
        }, indent=2))
    else:
        print_report(connector, connector_nodes, metrics, matching_entries,
                     start_str, end_str)


if __name__ == "__main__":
    main()
