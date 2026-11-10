# Debug Log Export

**Status:** fix BUILT 2026-10-14 (DECIDED, notice-level launch skeleton),
device check owed (Tier 2 Diagnostics). The export is the support-case path,
so it gates every unattached measurement.

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Info-level eviction and the notice-level launch skeleton

- [ ] **Debug export can come back empty or miss the first seconds**
  (2026-10-14, iPhone 17 on iOS 27.0.1, build 24): an export taken 18 s
  after a cold launch had `Entries: 0`; one taken 51 s after the next launch
  had 199 entries, but its first info-level lines start 5.4 s after the
  anchor while error-level lines are present from 1.4 s, so the Step 1 and
  Step 2 markers and `refresh() CALLED` are missing. The exporter itself is
  sound: a Swift Testing probe on the iPhone 17 Pro (26.5) and iPhone 17
  (27.0) simulators saw its own info/notice/error lines (debug is never
  persisted). Third export 17:53 the same day refutes the lag reading: it
  was taken 63 s after the anchor, contains info lines from 42 s after the
  anchor onwards (the pull-to-refresh, 17 s before the export) and none
  from the launch itself, while error and notice lines from 1.4 s on are
  present. PLAUSIBLE, revised: on device, info-level entries live in a
  bounded per-process memory buffer and the oldest are evicted as the
  buffer fills; the launch is the noisiest window (the debug-level dump of
  every movement, one "Establishing links" line per movement, the VTXO
  list), so the launch is exactly what gets evicted. The 12:16 export with
  zero entries fits a buffer that had just turned over. Until fixed:
  launch-step timings cannot be read from exports at all; use Console.app
  with the phone on a cable. Fix shape: mirror the app's own `Logger` lines
  into an in-process ring buffer the export reads first, with OSLogStore
  for bark's bridged lines; and cut the launch log volume (the full
  movements JSON at debug level, per-movement linking lines). The export is
  the support-case path (2026-10-11), so this gates every unattached
  measurement. CONFIRMED by the `OSLogType` docs (read 2026-10-14): "the
  system stores info-level messages in memory buffers and, without a
  configuration change, purges the oldest messages as those buffers fill
  up", while default/notice and above are written to the data store. Fix
  built 2026-10-14 (DECIDED, uncommitted), the documented route rather
  than a mirror: the launch skeleton now logs at notice — `Launch
  verdict`, `Existing wallet opened`, `Wallet opened`, `refresh() CALLED`,
  every `[Refresh] Step` marker incl. `Step 2b … after launch anchor`,
  `Wallet synced`, `Onchain wallet synced`, `Retrieved N movements`,
  `Successfully saved`, `Newest inserted row`, `Balance retrieved`,
  `Onchain balance retrieved`, `Onchain history stabilized`, `DataVersion
  incremented` (20 lines, no private interpolations). The export header
  now lists entries per level and states that info is best-effort. Detail
  lines stay at info and may still be missing from the start of a session;
  the ring-buffer mirror stays here as the follow-up if that proves
  limiting. Device check owed: one export after a cold launch must show the
  `Step 1`…`Step 4` markers.
