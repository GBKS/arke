# Project Documentation

Welcome to the project documentation. This documentation is organized to help you understand the system architecture, features, and development workflows.

**The docs are created and maintained by AI, mostly for its own use. As the project grows, it can reference basic architectural decisions, etc. In reverse, make sure to tell AI to revise docs as needed.**

## 📋 Documentation Structure

### 🏗️ Architecture
Core system design and component relationships:
- [System Overview](Architecture/system-overview.md) - High-level architecture and component responsibilities
- [Data Flow](Architecture/data-flow.md) - How data moves through the system
- [Service Layer](Architecture/service-layer.md) - Core services and their interfaces

### ⚡ Features
Detailed implementation guides for major features:
- [Balance Persistence](Features/balance-persistence.md) - SwiftData persistence for Ark and Onchain balances
- [Tag System](Features/tag-system.md) - Complete transaction tagging and organization system

### 📚 API Reference
Technical reference for services and models:
- [Service Interfaces](API/service-interfaces.md) - Key methods and protocols
- [Model Definitions](API/model-definitions.md) - Data models and transformations

### 🛠️ Development
Practical guides for development workflows:
- [Setup Guide](Development/setup.md) - Getting started with the project
- [Testing Patterns](Development/testing-patterns.md) - Testing strategies and examples
- [Common Tasks](Development/common-tasks.md) - Frequently needed development workflows

### 🗂️ Archive
Historical implementation and migration documentation:
- [Migration History](Archive/readme.md) - Summary of all completed migrations
- Individual migration files preserved for reference

## 🚀 Quick Start

New to the project? Start with:
1. [System Overview](Architecture/system-overview.md) - Understand the big picture
2. [Setup Guide](Development/setup.md) - Get your development environment ready
3. [Service Layer](Architecture/service-layer.md) - Learn the core services

## 📝 Contributing to Documentation

This documentation follows a consistent structure:
- **Overview**: Brief description of the system/feature
- **Implementation Details**: Technical specifics with code examples
- **Benefits**: User experience and performance improvements
- **Architecture Consistency**: How it fits with existing patterns

When adding new documentation, use the existing balance persistence document as a template for structure and detail level.

---
*Last updated: April 24, 2026*