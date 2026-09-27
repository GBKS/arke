# Default Contact Implementation

## Overview
Implemented `createDefaultContactsIfNeeded()` functionality to automatically create a faucet contact "Faucetto Signetto" when the wallet is first initialized, mirroring the existing default tags pattern.

## Changes Made

### 1. Contact Type System

#### ContactType.swift (NEW)
- **Added**: `ContactType` enum with cases:
  - `.standard` - Regular user-created contacts
  - `.faucet` - Signet faucet contact (Faucetto Signetto)
  - `.selfContact` - Reserved for future use (user's own contact)
  - `.developer` - Reserved for future use (developer/donation contact)
- **Added**: Computed properties:
  - `var isSpecialType: Bool` - Returns true for non-standard types
  - `var canBeEdited: Bool` - Returns true only for standard contacts
  - `var canBeDeleted: Bool` - Returns true only for standard contacts

### 2. Schema Changes

#### PersistentContact.swift
- **Removed**: `var isSystemContact: Bool`
- **Added**: `var contactType: String = ContactType.standard.rawValue` property
  - Stored as String rawValue for CloudKit compatibility
  - Default value `.standard` for CloudKit compatibility
- **Added**: Computed property `var type: ContactType` for type-safe access
- **Updated**: `init()` to include `contactType: ContactType` parameter (defaults to `.standard`)

#### ContactModel.swift
- **Removed**: `let isSystemContact: Bool` property
- **Added**: `let contactType: ContactType` property
  - Strongly typed enum instead of boolean
  - Supports multiple special contact types
- **Updated**: All initializers to include this field:
  - Main `init()` - uses `contactType: ContactType = .standard`
  - `init(from persistentContact:)` - uses `persistentContact.type`
  - `toPersistentContact()` - sets via `contactType.rawValue`
  - `withUpdatedTimestamp()` - preserves `contactType`

### 3. Service Layer

#### ContactService.swift
- **Added**: `createDefaultContactsIfNeeded()` public method
  - Checks if `contactCount == 0` before creating
  - Uses task manager for deduplication
  - Delegates to private implementation

- **Added**: `performCreateDefaultContacts()` private method
  - Creates "Faucetto Signetto" contact with:
    - Name: `"Faucetto Signetto"`
    - Notes: `"I'll help you test Arké. You can request free test bitcoin from me, and send me some back."`
    - `contactType: .faucet`
  - Adds two placeholder addresses:
    - **Ark Address**: `tark1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs4wuzwu` (primary)
    - **Onchain Address**: `tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx`
  - Uses `ContactAddressService` to properly validate and create addresses
  - Gracefully handles address creation failures (logs warning but continues)
  - Reloads contacts after creation to update in-memory cache

### 4. Manager Layer

#### WalletManager.swift
- **Added**: `createDefaultContactsIfNeeded()` delegation method
  - Simply delegates to `contactService.createDefaultContactsIfNeeded()`
  - Follows the same pattern as `createDefaultTagsIfNeeded()`

- **Updated**: `performInitialization()`
  - Added call to `await createDefaultContactsIfNeeded()` after `createDefaultTagsIfNeeded()`
  - Only executes when wallet exists and after successful refresh

## Implementation Flow

```
WalletManager.performInitialization()
  ↓
await refresh() // Load existing wallet data
  ↓
await createDefaultTagsIfNeeded()
  ↓
await createDefaultContactsIfNeeded() // NEW
  ↓
  → ContactService.createDefaultContactsIfNeeded()
      ↓
      → Check if contactCount == 0
      ↓
      → performCreateDefaultContacts()
          ↓
          → Create ContactModel with contactType = .faucet
          ↓
          → Insert PersistentContact into ModelContext
          ↓
          → Save to SwiftData
          ↓
          → Add Ark address (primary) via ContactAddressService
          ↓
          → Add Onchain address via ContactAddressService
          ↓
          → Reload contacts to refresh cache
```

## Default Contact Details

**Name**: Faucetto Signetto  
**Notes**: I'll help you test Arké. You can request free test bitcoin from me, and send me some back.  
**Contact Type**: Faucet (`contactType = .faucet`)  
**Profile Image**: Configured (asset name: "faucetto-signetto")

### Addresses

1. **Ark Address** (Primary)
   - Address: `tark1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs4wuzwu`
   - Label: "Ark Address"
   - Format: Ark
   - Type: Primary

2. **Onchain Address**
   - Address: `tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx`
   - Label: "Onchain Address"
   - Format: Bitcoin (Signet)
   - Type: Secondary

### 5. UI Layer Updates

#### ContactDetailView_iOS.swift
- **Updated**: Toolbar edit button check - uses `contact.contactType.canBeEdited`
- **Updated**: Faucet section visibility - checks `contact.contactType == .faucet`
- **Updated**: Contact details section - uses `contact.contactType.canBeEdited`
- **Updated**: Management section - uses `contact.contactType.canBeDeleted`
- **Updated**: Preview - uses `contactType: .faucet`

#### ContactsView_iOS.swift
- **Updated**: Swipe actions - uses `contact.contactType.canBeDeleted` to conditionally show delete

#### ContactAddressesSection.swift
- **Updated**: Add address button - uses `contact.contactType.canBeEdited`
- **Updated**: Address edit ability - uses `contact.contactType.canBeEdited`

## TODO: Next Steps

### 1. Replace Placeholder Addresses
The current implementation uses placeholder addresses. Replace with actual faucet addresses:
- Update `arkAddress` in `ContactService.performCreateDefaultContacts()`
- Update `onchainAddress` in `ContactService.performCreateDefaultContacts()`

### 2. Future Contact Types
The `ContactType` enum is ready for expansion:
- **Self Contact** (`.selfContact`): User's own contact information
  - Could be created on first launch or on-demand
  - Use case: Share with others, self-reference in UI
  - Implementation: Add `createSelfContact()` method when needed
  
- **Developer Contact** (`.developer`): Support/donation contact
  - Could be opt-in via Settings
  - Use case: Easy way for users to support development
  - Implementation: Add `createDeveloperContact()` method when needed

### 3. UI Enhancements (Optional Future Work)
While basic protection is in place, could add visual indicators:
- Display badge for special contact types (e.g., "Faucet", "Me", "Developer")
- Show system icons based on type (using `ContactType.systemIcon`)
- Add visual distinction (border color, background tint)
- Show "Special Contact" indicator in contact list

Example UI additions:
```swift
// In ContactRow or ContactDetailView
if contact.contactType != .standard {
    HStack {
        if let icon = contact.contactType.systemIcon {
            Image(systemName: icon)
        }
        if let badge = contact.contactType.displayBadge {
            Text(badge)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.Arke.blue.opacity(0.2))
                .cornerRadius(8)
        }
    }
}
```

## Testing

### Verification Steps
1. **Fresh wallet**: Delete existing wallet and create new one
2. **Check contact created**: Navigate to Contacts view
3. **Verify details**: 
   - Name should be "Faucetto Signetto"
   - Should have 2 addresses (1 Ark, 1 Onchain)
   - Ark address should be marked as primary
   - Contact type should be `.faucet`
4. **Check protection**: 
   - Should NOT be able to delete via swipe
   - Should NOT see Edit button in toolbar
   - Should NOT be able to add/edit addresses
5. **Existing wallets**: Opening existing wallet should NOT create duplicate

### Console Output
Look for these logs:
```
✅ Created default system contact: Faucetto Signetto
✅ Added primary Ark address to contact: tark1qyq...
✅ Added onchain address to contact: tb1qw50...
✅ Default contact setup complete
👥 Loaded 1 contacts with addresses from SwiftData
```

## Notes

- **Type System**: Using enum instead of boolean for extensibility
  - Easy to add new contact types (self, developer, etc.)
  - Type-safe with computed properties for permissions
  - Stored as String rawValue for CloudKit compatibility
- **No Migration**: Old `isSystemContact` property completely removed
- **CloudKit Sync**: Faucet contact will sync across devices via iCloud
- **Idempotent**: Safe to call multiple times - checks `contactCount == 0`
- **Addresses**: Uses `ContactAddressService` for proper validation and format detection
- **Error Handling**: Address creation failures are logged but don't fail the entire operation
- **UI Protection**: Edit/delete operations disabled for non-standard contact types
- **Future Ready**: Enum structure supports additional special contact types without refactoring
