# Contact & Address Deletion Logic

## Overview

This document describes the deletion and unassignment logic for contacts and addresses in the Ark wallet prototype.

## Design Philosophy

**Principle: Minimal Surprise, Maximum Clarity**

- Each deletion action affects only what the user directly interacted with
- Transaction assignments are treated as historical records (not automatically removed)
- Address book entries are convenience features (can be removed without affecting transaction history)
- Clear UI messaging explains what will and won't be affected

## Scenarios

### Scenario A: Deleting an Address from a Contact

**Location**: `ContactDetailView.deleteAddress()`, `ContactAddressEditor`

**Behavior**: Non-destructive to transaction assignments

```
When a user deletes an address from a contact:
✅ Removes the address from the contact's address book
❌ Does NOT remove contact assignments from transactions
❌ Does NOT affect other transactions with that address
```

**Rationale**:
- Addresses are metadata/convenience for future sends
- Transaction relationships are historical and shouldn't be "forgotten"
- Users can manually unassign contacts from transactions if desired

**UI Communication**:
- Info banner in address list: "Deleting an address only removes it from this contact card. Transaction assignments remain unchanged."
- Confirmation dialog clarifies: "This will remove the address from [Contact]'s contact card. Transactions previously assigned to this contact will remain assigned."

---

### Scenario B: Removing a Contact from a Transaction

**Location**: `ContactSelectorSheet.removeAssignment()`, `TransactionContactView.removeContact()`

**Behavior**: Scoped to single transaction

```
When a user removes a contact from a transaction:
✅ Removes the contact assignment from THIS transaction only
❌ Does NOT remove assignments from other transactions
❌ Does NOT remove the address from the contact's address book
```

**Rationale**:
- User is focused on THIS specific transaction
- Perhaps only this transaction was incorrectly assigned
- Address might be correct for other transactions
- Keep address in contact's address book for future use

**UI Communication**:
- Info message shows: "Remove '[Contact]' from this transaction only"
- Additional info: "X other transaction(s) with this address will remain assigned"
- Secondary note: "The address will stay in '[Contact]'s contact card"

---

### Scenario C: Deleting a Contact Entirely

**Location**: Contact management (ContactService, WalletManager)

**Behavior**: Complete cascade deletion

```
When a user deletes a contact:
✅ Removes the contact record
✅ Cascade deletes all addresses (via deleteRule: .cascade)
✅ Cascade deletes all transaction assignments (via deleteRule: .cascade)
```

**Rationale**:
- This is an explicit "forget everything about this contact" action
- Complete cleanup is expected behavior
- SwiftData's cascade delete rules handle this automatically

---

## Forward Logic (Context)

For comparison, here's how the **forward direction** works:

### Assigning a Contact to a Transaction

**Location**: `WalletManager.assignContactWithAddressLearning()`

**Behavior**: Smart bulk assignment

```
When a user assigns a contact to a transaction:
✅ Creates contact ↔ transaction assignment
✅ If transaction has an address: adds it to contact's address book
✅ Auto-assigns: finds ALL other transactions with same address (without contacts) and bulk-assigns them
```

This creates a powerful learning system where one assignment can cascade to many transactions.

---

## Implementation Details

### Files Modified

1. **ContactDetailView.swift**
   - Added comments to `deleteAddress()` clarifying behavior
   - Added info banner in `addressesSection` explaining deletion scope

2. **ContactAddressEditor.swift**
   - Updated delete confirmation dialog with clear messaging
   - Changed button text to "Delete Address Only"
   - Added explanation about transaction assignments remaining

3. **ContactSelectorSheet.swift**
   - Added comments to `removeAssignment()` clarifying behavior
   - Enhanced removal preview UI to show:
     - "Remove from this transaction only"
     - Count of other transactions that remain assigned
     - Note that address stays in contact's address book
   - Updated `loadCurrentAssignment()` to populate preview data

4. **TransactionContactView.swift**
   - Added comments to `removeContact()` clarifying behavior

5. **ContactService.swift**
   - Added documentation to `unassignContact()` method
   - Added documentation to `removeAllContactsFromTransaction()` method
   - Clarified that these operations are scoped to specific transactions

### Code Comments Added

Strategic comments were added to all deletion/unassignment operations:

```swift
// Note: This does NOT remove contact assignments from transactions
// Note: This does NOT affect other transactions with the same address
// Note: This does NOT remove the address from the contact's address book
```

---

## Edge Cases Handled

### 1. Last Address Deletion
Currently: No special warning (user can have contact with zero addresses)
Future consideration: Optional warning when deleting the last/only address

### 2. Primary Address Deletion
Handled by: `ContactAddressService.deleteAddress()`
Behavior: Deletion succeeds; contact has no primary address until user sets another

### 3. Empty Contact Preview Data
Handled gracefully with conditional UI in `ContactSelectorSheet`

### 4. Transaction with Multiple Contacts
Each contact can be removed independently via `unassignContact()`
Or all at once via `removeAllContactsFromTransaction()`

---

## Database Relationships

### SwiftData Cascade Rules

```swift
// PersistentContact
@Relationship(deleteRule: .cascade, inverse: \TransactionContactAssignment.contact)
var contactAssignments: [TransactionContactAssignment] = []

@Relationship(deleteRule: .cascade)
var addresses: [PersistentContactAddress] = []
```

**Result**: Deleting a contact cascades to delete:
- All transaction assignments
- All addresses

**But**: Deleting an address or assignment does NOT cascade up to delete the contact.

---

## User Experience Summary

| Action | Scope | Clear UI Messaging | Rationale |
|--------|-------|-------------------|-----------|
| **Delete Address** | Single address only | ✅ Info banner + confirmation | Addresses are metadata |
| **Unassign Contact** | Single transaction only | ✅ Preview with details | Focus on user's target |
| **Delete Contact** | Entire contact entity | ✅ Standard delete confirm | Complete cleanup expected |

---

## Future Enhancements

### Optional: Bulk Management View

If power users need more control, consider adding:
- "Manage Address Assignments" view
- Shows all transactions grouped by address
- Allows bulk unassignment operations
- Clear, explicit actions

### Optional: Warning for Last Address

When deleting a contact's only address:
- Show warning: "This is the last address for this contact. Transaction assignments will remain."
- Give user option to reconsider

---

## Testing Checklist

- [ ] Delete an address: verify transaction assignments remain
- [ ] Unassign contact from transaction: verify address stays in contact card
- [ ] Unassign contact: verify other transactions with same address remain assigned
- [ ] Delete contact: verify all addresses and assignments are cascade-deleted
- [ ] UI shows correct preview information before changes
- [ ] Confirmation dialogs display appropriate messaging
- [ ] Error handling works for all operations

---

## Summary

The implemented logic follows the **KISS principle** (Keep It Simple, Stupid):

1. Each action does exactly what the user clicked
2. No surprise cascades or bulk operations on deletion
3. Clear communication about what's NOT being changed
4. Historical transaction data is preserved by default
5. Users have full control through explicit, scoped actions

This approach is:
- ✅ **Least surprising** - predictable behavior
- ✅ **Reversible** - easy to undo by re-assigning
- ✅ **Safe** - no accidental data loss
- ✅ **Follows UX best practices** - delete what you see
- ✅ **Simpler code** - less complexity = fewer bugs

---

*Last updated: 2025-11-11*
