# CloudKit Setup Checklist for Ark Wallet (Alpha)

## 🚀 Quick Setup (5 minutes)

### 1. Xcode Project Setup
- [ ] Open your Xcode project
- [ ] Select your app target → **Signing & Capabilities** tab
- [ ] Click **"+ Capability"** button
- [ ] Add **"iCloud"** capability
- [ ] Check the **"CloudKit"** checkbox
- [ ] ✅ Done! Your container identifier will be auto-generated (e.g., `iCloud.com.yourteam.Ark-wallet-prototype`)

### 2. Code Changes
- [x] ✅ **DONE:** `SwiftDataHelper.swift` already updated with CloudKit support
- [ ] Update your app's main file to pass `cloudKitEnabled: true` (see `AppWithCloudKitExample.swift`)
- [ ] Build and run!

### 3. Test It Works
- [ ] Sign in to iCloud on your Mac (System Settings → Apple ID)
- [ ] Run your app
- [ ] Create a tag, contact, or add a transaction note
- [ ] Open CloudKit Dashboard (see below) and verify data appears
- [ ] *Optional:* Run on second device/simulator to test sync

## 📊 CloudKit Dashboard

View your synced data:
1. Go to: https://icloud.developer.apple.com/dashboard
2. Select your app's container
3. Navigate to "Data" → "Records"
4. You'll see your SwiftData models (PersistentTransaction, PersistentTag, etc.)

## ⚡️ What's Syncing (Alpha Configuration)

For alpha testing, I recommend syncing everything to test the full experience:

- ✅ `PersistentTransaction` - All transaction data and metadata
- ✅ `PersistentTag` - User-created tags
- ✅ `PersistentContact` - Contact information
- ✅ `TransactionTagAssignment` - Tag relationships
- ✅ `TransactionContactAssignment` - Contact relationships
- ⚠️ `ArkBalanceModel` - Consider: balance is fetched from server, may not need sync
- ⚠️ `OnchainBalanceModel` - Consider: balance is fetched from server, may not need sync

**Note:** Since balances are cached from the server, you might want to exclude them from sync to avoid stale data. They'll refresh from the server anyway.

## 🐛 Common Issues

### "CloudKit not available"
- Make sure you're signed into iCloud
- Check System Settings → Apple ID
- Ensure "iCloud Drive" is enabled

### Data not syncing
- Wait up to 60 seconds (CloudKit can be slow)
- Check network connection
- Verify both devices use the same Apple ID
- Check CloudKit Dashboard to see if data reached the server

### Build errors
- Clean build folder (Cmd + Shift + K)
- Restart Xcode
- Make sure you added the iCloud capability correctly

## 🔒 Alpha Security Note

Since this is alpha, all transaction data (including amounts and addresses) will sync to iCloud. This is fine for testing, but for production you may want to:
- Only sync metadata (tags, notes, contacts)
- Exclude transaction amounts/addresses
- Add user consent flow

For alpha testing with testnet/small amounts, current setup is perfect!

## ✅ You're Done When...

1. ✅ iCloud capability added in Xcode
2. ✅ Code updated with `cloudKitEnabled: true`
3. ✅ App builds without errors
4. ✅ Test data appears in CloudKit Dashboard

That's it! CloudKit sync is now working. 🎉
