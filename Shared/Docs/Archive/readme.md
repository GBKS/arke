# Documentation Archive

This folder contains historical implementation and migration documentation that chronicles the development process but is no longer the primary reference for current system state.

## Migration Documents

These documents describe completed architectural changes:

- `MIGRATION_HISTORY.md` - Consolidated summary of all completed migrations  
- `ARCHITECTURE_MIGRATION.md` - Transaction architecture restructuring
- `ARK_BALANCE_MIGRATION.md` - Ark balance model unification
- `ONCHAIN_BALANCE_MIGRATION.md` - Onchain balance model unification

## Implementation Step Documents

These documents chronicle the step-by-step implementation of the tag system:

- `STEP1_IMPLEMENTATION.md` - SwiftData tag models and relationships
- `STEP2_IMPLEMENTATION.md` - TagService implementation with CRUD operations
- `STEP3_IMPLEMENTATION.md` - WalletManager integration and coordinator pattern
- `STEP4_TAG_PRESERVATION_IMPLEMENTATION.md` - Tag preservation during server refreshes

## Device Registry & Device Migration (archived 2026-07-08)

Completed device-registry implementation docs. The living references remain at the Docs root (`Device_Registry_Reference.md`, `DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md`):

- `DEVICE_REGISTRY_PHASE1_SUMMARY.md` - Phase 1: foundation
- `DEVICE_REGISTRY_PHASE2_SUMMARY.md` - Phase 2: wallet lifecycle integration
- `DEVICE_REGISTRY_PHASE3_SUMMARY.md` - Phase 3: device management UI
- `DEVICE_REGISTRY_COMPLETE.md` - Intermediate completion snapshot (superseded by ALL_PHASES_COMPLETE)
- `DEVICE_REGISTRATION_RACE_CONDITION_FIX.md` - Completed fix (2026-05-13)
- `DEVICE_MIGRATION_IMPLEMENTATION_PLAN.md` - Superseded by DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md (at Docs root)

## Purpose

These documents are preserved for:
- Historical context of design decisions
- Understanding the evolution of the codebase
- Reference for similar future implementations  
- Troubleshooting migration-related issues

## Current Documentation

For current system documentation, see the main `Docs/` folder structure.

---
*Archived: October 30, 2025*