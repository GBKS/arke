//
//  TaskDeduplicationManager.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation
import OSLog

/// Generic task deduplication manager that prevents multiple concurrent executions of the same operation
@MainActor
class TaskDeduplicationManager {

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "TaskDeduplication")

    private var tasks: [String: Any] = [:]

    /// Ownership tokens for `executeFresh`, so a finishing call only clears
    /// the key if a later one hasn't claimed it.
    private var generations: [String: Int] = [:]
    private var generationCounter = 0

    /// Access to running task keys for monitoring purposes
    var runningTaskKeys: Set<String> {
        return Set(tasks.keys)
    }
    
    /// Execute a throwing operation with deduplication by key
    func execute<T>(
        key: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // Check if task already exists
        if let existingTask = tasks[key] as? Task<T, Error> {
            return try await existingTask.value
        }
        
        // Create new task
        let task = Task {
            try await operation()
        }
        tasks[key] = task

        // Only clear if the key still belongs to this task — an `executeFresh`
        // may have replaced it while we were suspended; removing its
        // registration would let later callers run concurrently with it.
        defer {
            if let current = tasks[key] as? Task<T, Error>, current == task {
                tasks.removeValue(forKey: key)
            }
        }
        return try await task.value
    }
    
    /// Execute a non-throwing operation with deduplication by key
    func execute<T>(
        key: String,
        operation: @escaping () async -> T
    ) async -> T {
        // Check if task already exists
        if let existingTask = tasks[key] as? Task<T, Never> {
            return await existingTask.value
        }
        
        // Create new task
        let task = Task {
            await operation()
        }
        tasks[key] = task

        let result = await task.value
        // Only clear if the key still belongs to this task — an `executeFresh`
        // may have replaced it while we were suspended; removing its
        // registration would let later callers run concurrently with it.
        if let current = tasks[key] as? Task<T, Never>, current == task {
            tasks.removeValue(forKey: key)
        }
        return result
    }

    /// Run `operation` fresh, **never joining** an in-flight task for `key`.
    ///
    /// `execute` returns whatever an already-running task produces, so on
    /// return the data is only as fresh as whenever that task started. That
    /// makes it unsafe for a caller that must observe its own writes: a
    /// refresh kicked off before the write would satisfy the call with
    /// pre-write data. This variant waits for any in-flight task (so the
    /// operation still never runs concurrently with itself) and then runs a
    /// new one.
    ///
    /// Concurrent `execute` callers that arrive while this is running will
    /// join *this* task, which is what they want.
    ///
    /// Void-only by design — the single consumer is
    /// `TransactionService.refreshTransactionsAfterWrite()`, and keeping it
    /// concrete avoids erasing the result type of the drained task.
    ///
    /// Only drains a `Task<Void, Never>`. `Task` is invariant in both generic
    /// parameters, so an in-flight task created by the *throwing* `execute`,
    /// or by a non-`Void` one, cannot be cast here and would be skipped —
    /// running `operation` concurrently with it. That's the hazard this
    /// method exists to avoid, so the mismatch traps in debug rather than
    /// degrading quietly. Keep one result type per key.
    func executeFresh(
        key: String,
        operation: @escaping () async -> Void
    ) async {
        let inFlight = tasks[key] as? Task<Void, Never>

        if tasks[key] != nil && inFlight == nil {
            assertionFailure(
                "executeFresh(key: \"\(key)\") cannot drain the in-flight task — it is not a Task<Void, Never>. "
                + "`operation` would run concurrently with it. Use one result type per key."
            )
            Self.logger.error("executeFresh(key: \(key, privacy: .public)) could not drain a differently-typed in-flight task — proceeding without draining")
        }

        generationCounter += 1
        let generation = generationCounter

        let task = Task {
            // Drain first: the upsert pipeline awaits mid-loop while holding
            // a pre-fetched snapshot, so two concurrent runs could both
            // decide to insert the same row.
            await inFlight?.value
            await operation()
        }
        tasks[key] = task
        generations[key] = generation

        await task.value

        // Only clear if still ours — a later `executeFresh` may have taken
        // the key over while we were suspended.
        if generations[key] == generation {
            tasks.removeValue(forKey: key)
            generations.removeValue(forKey: key)
        }
    }

    /// Cancel a specific task by key
    func cancel(key: String) {
        if let task = tasks[key] as? Task<Any, Error> {
            task.cancel()
            tasks.removeValue(forKey: key)
        } else if let task = tasks[key] as? Task<Any, Never> {
            task.cancel()
            tasks.removeValue(forKey: key)
        }
    }
    
    /// Cancel all tasks
    func cancelAll() {
        for (_, task) in tasks {
            if let throwingTask = task as? Task<Any, Error> {
                throwingTask.cancel()
            } else if let nonThrowingTask = task as? Task<Any, Never> {
                nonThrowingTask.cancel()
            }
        }
        tasks.removeAll()
    }
    
    /// Check if a task is currently running for a given key
    func isRunning(key: String) -> Bool {
        return tasks[key] != nil
    }
}

/// Convenience extensions for common task deduplication patterns
extension TaskDeduplicationManager {
    
    /// Execute operation with automatic key generation from function name
    func execute<T>(
        operation: @escaping () async throws -> T,
        file: String = #file,
        function: String = #function
    ) async throws -> T {
        let key = "\(URL(fileURLWithPath: file).lastPathComponent).\(function)"
        return try await execute(key: key, operation: operation)
    }
    
    /// Execute non-throwing operation with automatic key generation
    func execute<T>(
        operation: @escaping () async -> T,
        file: String = #file,
        function: String = #function
    ) async -> T {
        let key = "\(URL(fileURLWithPath: file).lastPathComponent).\(function)"
        return await execute(key: key, operation: operation)
    }
}
