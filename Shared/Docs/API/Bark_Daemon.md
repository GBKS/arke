# Bark Daemon Functionality

Notes from analyzing the bark repo (Copilot, May 31, 2026). Describes the background daemon the Bark library runs for a wallet.

Daemon responsibilities, end-to-end:

Starts background processing for a wallet, and exposes a handle to stop gracefully.

Runs startup tasks:

- Tries an immediate server refresh.
- Sets initial connected/disconnected state.
- Runs a full wallet sync unless manual-sync mode is enabled.
- Source: daemon.rs, lib.rs

Maintains server connectivity:

- Periodic heartbeat/reconnect loop.
- Sets internal connected flag that gates some network-dependent work.
- Source: daemon.rs

Keeps a live round-events subscription:

- Subscribes to round event stream.
- Processes each event via round progression logic.
- Re-subscribes on stream resets/errors.
- Source: daemon.rs, mod.rs

Runs mailbox processing continuously:

- Subscribes to mailbox messages.
- Processes incoming arkoor-related mailbox items.

Handles lightning notifications:

- Incoming lightning payment notifications trigger receive-claim attempts.
- Outgoing lightning completion notifications drive settlement/continuation.
- Source: daemon.rs, mailbox.rs

Runs periodic sync tasks on interval:

- Updates fee-rate cache from chain source.
- Syncs pending boards.
- Syncs pending offboards.
- Syncs onchain wallet.
- Syncs pending rounds (confirmation/finalization side).
- Progresses unilateral exits, including CPFP handling through onchain wallet.
- Source: daemon.rs, bdk.rs

Handles exits automatically in background:

- Advances exit state machine.
- Broadcasts/rebroadcasts and fee-bumps as needed.
- Tracks confirmation/timelock progression toward claimable state.
- Source: daemon.rs, mod.rs, states.rs

Handles lightning in two ways:

- Startup/full sync path includes pending lightning send sync and “claim all pending receives”.
- Runtime relies mainly on mailbox-driven events for fast ongoing lightning progress/claim.
- Source: lib.rs, mailbox.rs, receive.rs

Supports manual-sync mode:

- Disables startup/full auto sync, periodic sync loop, round-event subscription, and mailbox subscription.
- Leaves only server connection heartbeat running.
- Source: daemon.rs, config.rs

Supports clean shutdown:

- Cancellation token stops all loops.
- stop_wait waits for task completion on native targets.
- Source: daemon.rs

Practical one-liner: the daemon is the wallet’s background orchestrator for connectivity, mailbox/event handling, periodic state sync, round progress, and unilateral-exit advancement, with lightning mostly event-driven after startup sync.

---

Another note is that the daemon may automatically trigger exits in some scenarios:

VTXOs may be automatically exited in some scenarios
- Board funding VTXO expiry path: A pending board that is about to expire before required confirmations is automatically marked for exit in board.rs:118 and board.rs:119.
- Lightning receive fallback path: If a lightning receive claim ultimately fails (after retries), the wallet falls back to exiting HTLC VTXOs in receive.rs:668, receive.rs:669, and receive.rs:472.
- Lightning send revocation failure path: If HTLC revocation cannot be completed near expiry, the wallet escalates to exit in pay.rs:617 and pay.rs:624.
