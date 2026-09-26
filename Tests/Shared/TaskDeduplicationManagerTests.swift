//
//  TaskDeduplicationManagerTests.swift
//  ArkéTests
//
//  Pins the difference between `execute` (joins an in-flight task) and
//  `executeFresh` (drains it, then runs anew). The distinction is load
//  bearing: post-write callers must observe their own writes, and joining a
//  fetch that started earlier silently returns pre-write data — which left
//  Guard C blind to a refresh the app had just scheduled.
//  See Shared/Docs/Features/Refresh_Deduplication.md §3.2.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Task Deduplication Manager Tests")
@MainActor
struct TaskDeduplicationManagerTests {

    /// Counts invocations and lets the test hold an operation open until it
    /// chooses to release it, so "in flight" is deterministic rather than
    /// timing-dependent.
    private final class Probe {
        var started = 0
        var finished = 0
        /// Holds *all* waiters, not one. A single slot would leak a
        /// continuation if two operations ever waited concurrently, and the
        /// test would hang instead of failing — the worst outcome for a
        /// concurrency test, since a serialization regression is exactly
        /// what would cause the overlap.
        private var gates: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        /// Suspends until `release()` — or returns immediately if already released.
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { gates.append($0) }
        }

        func release() {
            isOpen = true
            let pending = gates
            gates.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    // MARK: - execute (joining)

    @Test("execute joins an in-flight task instead of running twice")
    func executeJoinsInFlight() async {
        let manager = TaskDeduplicationManager()
        let probe = Probe()

        let first = Task { @MainActor in
            await manager.execute(key: "k") {
                probe.started += 1
                await probe.wait()
                probe.finished += 1
            }
        }
        await Task.yield()   // let `first` claim the key

        let second = Task { @MainActor in
            await manager.execute(key: "k") {
                probe.started += 1
                await probe.wait()
                probe.finished += 1
            }
        }
        await Task.yield()

        probe.release()
        _ = await first.value
        _ = await second.value

        // The join is the whole point of `execute`: one execution, two callers.
        #expect(probe.started == 1)
        #expect(probe.finished == 1)
    }

    // MARK: - executeFresh (never joins)

    @Test("executeFresh runs a new execution rather than joining")
    func executeFreshDoesNotJoin() async {
        let manager = TaskDeduplicationManager()
        let probe = Probe()

        let inFlight = Task { @MainActor in
            await manager.execute(key: "k") {
                probe.started += 1
                await probe.wait()
                probe.finished += 1
            }
        }
        await Task.yield()

        let fresh = Task { @MainActor in
            await manager.executeFresh(key: "k") {
                probe.started += 1
                await probe.wait()
                probe.finished += 1
            }
        }
        await Task.yield()

        probe.release()
        _ = await inFlight.value
        _ = await fresh.value

        // Two executions: the joined one would have returned pre-write data.
        #expect(probe.started == 2)
        #expect(probe.finished == 2)
    }

    @Test("executeFresh does not run concurrently with the task it drains")
    func executeFreshSerializes() async {
        let manager = TaskDeduplicationManager()
        let probe = Probe()
        var maxConcurrent = 0
        var active = 0

        // The upsert pipeline awaits mid-loop while holding a pre-fetched
        // snapshot, so overlapping runs could double-insert. Draining — not
        // bypassing — is what keeps that safe.
        let body: () async -> Void = {
            active += 1
            maxConcurrent = max(maxConcurrent, active)
            await probe.wait()
            active -= 1
        }

        let inFlight = Task { @MainActor in
            await manager.execute(key: "k", operation: body)
        }
        await Task.yield()

        let fresh = Task { @MainActor in
            await manager.executeFresh(key: "k", operation: body)
        }
        await Task.yield()

        probe.release()
        _ = await inFlight.value
        _ = await fresh.value

        #expect(maxConcurrent == 1)
    }

    @Test("executeFresh releases the key when it finishes")
    func executeFreshClearsKey() async {
        let manager = TaskDeduplicationManager()

        await manager.executeFresh(key: "k") { }

        #expect(manager.runningTaskKeys.isEmpty)
    }

    @Test("execute arriving after a drain joins the fresh task rather than running concurrently")
    func executeJoinsFreshTaskAfterDrain() async {
        // The interleaving that matters: executeFresh drains an
        // execute-created task; when that drained task finishes, its creator's
        // cleanup must not deregister the fresh task — otherwise an `execute`
        // arriving while the fresh task still runs finds no key and starts a
        // concurrent run, the exact double-upsert hazard the drain prevents.
        let manager = TaskDeduplicationManager()
        let firstGate = Probe()
        let freshGate = Probe()
        var freshStarted = 0
        var joinerRan = 0

        let first = Task { @MainActor in
            await manager.execute(key: "k") { await firstGate.wait() }
        }
        await Task.yield()

        let fresh = Task { @MainActor in
            await manager.executeFresh(key: "k") {
                freshStarted += 1
                await freshGate.wait()
            }
        }
        await Task.yield()

        // Finish the drained task: the fresh operation starts, and — crucially
        // — the first `execute` caller resumes and runs its cleanup path.
        firstGate.release()
        _ = await first.value
        await Task.yield()

        // An execute arriving now must JOIN the still-running fresh task.
        let joiner = Task { @MainActor in
            await manager.execute(key: "k") {
                joinerRan += 1
                await freshGate.wait()
            }
        }
        await Task.yield()

        freshGate.release()
        _ = await fresh.value
        _ = await joiner.value

        #expect(freshStarted == 1)
        #expect(joinerRan == 0)                   // joined: its own closure never ran
        #expect(manager.runningTaskKeys.isEmpty)  // and no cascade residue remains
    }

    @Test("Concurrent executeFresh calls both run and leave no stale key")
    func concurrentExecuteFreshDoesNotLeak() async {
        // Two overlapping forced refreshes: the later one claims the key, so
        // the earlier one must not clear it out from under it on completion.
        let manager = TaskDeduplicationManager()
        let probe = Probe()

        let a = Task { @MainActor in
            await manager.executeFresh(key: "k") {
                probe.started += 1
                await probe.wait()
            }
        }
        await Task.yield()

        let b = Task { @MainActor in
            await manager.executeFresh(key: "k") {
                probe.started += 1
                await probe.wait()
            }
        }
        await Task.yield()

        probe.release()
        _ = await a.value
        _ = await b.value

        #expect(probe.started == 2)
        #expect(manager.runningTaskKeys.isEmpty)
    }
}
