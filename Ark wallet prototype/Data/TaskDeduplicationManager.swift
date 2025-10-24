//
//  TaskDeduplicationManager.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/23/25.
//

import Foundation

/// Generic task deduplication manager that prevents multiple concurrent executions of the same operation
@MainActor
class TaskDeduplicationManager {
    private var tasks: [String: Any] = [:]
    
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
        
        do {
            let result = try await task.value
            tasks.removeValue(forKey: key)
            return result
        } catch {
            tasks.removeValue(forKey: key)
            throw error
        }
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
        tasks.removeValue(forKey: key)
        return result
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