# Passkey Integration Plan — Review Transcript

> **📦 Archived 2026-07-09 — not pursued.** Raw review transcript for `PASSKEY_INTEGRATION_PLAN.md`, which was archived unimplemented (passkeys were judged not to bring enough benefit to Arke).

From bark repo:

I’m reviewing the passkey integration plan against the repo’s own agent instructions and the existing code/docs first, then I’ll give you a findings-first evaluation with concrete gaps and risks.

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#1-1), lines 1 to 400

Read memory

Read [](file:///Users/christoph/workspace/bark/contrib/agents/agents.md)

The plan is already making claims about Bark recovery paths and iOS integration points, so I’m checking those claims against the actual Rust/server code next rather than treating the document as self-consistent.

Searched for regex `importVtxo|import-vtxo|encodedVtxo|getEncodedVtxo` (`bark`), 70 results

Searched for regex `recovery mailbox|recovery_mailbox|sync_mailbox|mailbox` (`bark`), 200 results

Searched for regex `vtxos/.*/encoded|encoded.*vtxo|wallet/vtxos` (`bark`), 83 results

I’ve confirmed the Bark-side mailbox and import endpoints largely exist. The bigger question now is whether the plan’s Passkey design is technically valid on iOS, because that’s where the highest-risk assumptions usually hide.



Searched for regex `relying party|rpId|Associated Domains|apple-app-site-association|passkey|AuthenticationServices|ASAuthorization` (`bark` · `docs/PASSKEY_INTEGRATION_PLAN.md`), 112 results

Read [](file:///Users/christoph/workspace/bark/server-rpc/protos/mailbox_server.proto)

Fetched 2 resources

Read [](file:///Users/christoph/workspace/bark/bark/src/vtxo/mod.rs#110-110), lines 110 to 170

I have enough to separate two things now: the Bark recovery assumptions are partly grounded, but the Passkey section is mixing authentication APIs with local secret storage in a way that looks unsound. I’m verifying whether the Bark client already exposes enough mailbox machinery or whether the plan understates required Rust/FFI work.

Searched for regex `RecoveryVtxoIdsMessage|post_recovery_vtxo_ids|ReadMailbox|read_mailbox|subscribe_process_mailbox_messages|sync_mailbox` (`bark` · `bark/src/**`), 9 results

Read [](file:///Users/christoph/workspace/bark/bark/src/mailbox.rs#1-1), lines 1 to 260

Read [](file:///Users/christoph/workspace/bark/bark/src/lib.rs#1580-1580), lines 1580 to 1665

Read [](file:///Users/christoph/workspace/bark/bark-rest/src/api/v1/wallet.rs#418-418), lines 418 to 455

The strongest Bark-side issue is now clear: the plan treats the encoded-VTXO endpoint as a server recovery lookup, but the actual handler only re-encodes a VTXO already present in the wallet DB. I’m pulling the exact sections of the plan that make that mistake so the evaluation can be specific.

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#210-210), lines 210 to 270

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#600-600), lines 600 to 620

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#938-938), lines 938 to 985

Searched for regex `fn get_vtxo_by_id|get_vtxo_by_id\(` (`bark` · `bark/src/**`), 6 results

I have the two core technical mismatches pinned down now: the plan’s recovery path assumes a server lookup API that the repo does not provide, and its “passkey-derived encryption” design treats a WebAuthn credential ID as if it were a recoverable symmetric secret. I’m confirming one last Bark detail around `get_vtxo_by_id` so the review can be precise about why the endpoint won’t work for cold recovery.

Read [](file:///Users/christoph/workspace/bark/bark/src/lib.rs#1196-1196), lines 1196 to 1222

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#316-316), lines 316 to 345

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#430-430), lines 430 to 470

One practical gap remains: this repo does not contain the Arke iOS code the plan names, so several “file changes required” sections are unverifiable from this workspace. I’m checking that explicitly so I can separate repo-backed findings from iOS-app assumptions.

Searched for files matching `bark` · `Arke/**`, no matches

Read [](file:///Users/christoph/workspace/bark/CHANGELOG.md#50-50), lines 50 to 65

Read [](file:///Users/christoph/workspace/bark/bark-rest/openapi.json#1646-1646), lines 1646 to 1668

I want to avoid overstating the iOS limitation. Apple’s newer passkey APIs expose things like PRF and large-blob support, so I’m checking whether the document could be salvaged by using those extensions instead of the credential ID hack.





Fetched 2 resources

Fetched 2 resources

I’m checking one more interface boundary: the plan assumes Swift can “just” read the recovery mailbox, but in this repo that capability is gRPC/mailbox-level, not a documented REST wallet endpoint. That affects whether your iOS app can realistically do this with existing Swift bindings.

Searched for text `mailbox` (`bark` · `bark-rest/src/**`), 3 results

Searched for regex `recovery_mailbox_identifier|mailbox_authorization|mailbox_identifier` (`bark` · `bark/src/**`), 9 results

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#296-296), lines 296 to 310

I’m at the point of writing the evaluation. I’m pulling exact line numbers for the Bark-side evidence so the findings can point to the precise mismatch instead of summarizing loosely.

Read [](file:///Users/christoph/workspace/bark/bark/src/mailbox.rs#200-200), lines 200 to 245

Read [](file:///Users/christoph/workspace/bark/bark/src/mailbox.rs#320-320), lines 320 to 345

Read [](file:///Users/christoph/workspace/bark/bark-rest/src/api/v1/wallet.rs#432-432), lines 432 to 446

Read [](file:///Users/christoph/workspace/bark/docs/PASSKEY_INTEGRATION_PLAN.md#120-120), lines 120 to 165

I have the substance. I’m just tightening the line references for the final review so you can jump straight to the mismatches in the repo and plan.

Searched for text `Received recovery VTXO IDs, ignoring` (`bark` · `bark/src/mailbox.rs`), 1 result

Searched for text `Post vtxo IDs to the server's recovery mailbox` (`bark` · `bark/src/mailbox.rs`), 1 result

Searched for text `pub async fn get_vtxo_by_id` (`bark` · `bark/src/lib.rs`), 1 result

Searched for regex `Passkey-derived encryption|Use Passkey credential ID as key derivation material|relyingPartyIdentifier` (`bark` · `docs/PASSKEY_INTEGRATION_PLAN.md`), 3 results

I’m storing one repo note because this is the sort of false assumption that can recur: Bark does post recovery VTXO IDs, but the wallet still ignores those mailbox messages, and the encoded-VTXO REST endpoint only works for VTXOs already in the local wallet DB.

Created memory file [](file:///Users/christoph/Library/Application%20Support/Code/User/workspaceStorage/92052b77a6d68d1593db301e2bc54291/GitHub.copilot-chat/memory-tool/memories/repo/bark-recovery-mailbox.md)

**Findings**

1. High: the recovery flow in the plan is not implementable with the current Bark APIs. The plan says a recovered client can read recovery-mailbox VTXO IDs and then fetch each VTXO through PASSKEY_INTEGRATION_PLAN.md. But the encoded-VTXO endpoint in Bark only re-encodes a VTXO already present in the wallet database, as shown in wallet.rs and lib.rs. On a fresh recovery, those round and board VTXOs are exactly what is missing from the DB, so this will return not found. As written, the document’s “complete wallet recovery” claim is false unless you add a true server-side fetch-by-ID recovery endpoint or change the mailbox to carry full encoded VTXOs.

2. High: the passkey cryptography design is wrong. The document derives an encryption key from the passkey credential ID in PASSKEY_INTEGRATION_PLAN.md. A credential ID is an identifier, not a stable exported secret. That means the proposed mnemonic encryption scheme is not something you should rely on for recovery. If you want passkey-backed local encryption, the right Apple mechanism is the WebAuthn PRF extension, not HKDF over credentialID, and that only exists on newer OS versions. The current plan should be treated as cryptographically unsound until that section is rewritten.

3. High: the plan understates the backend and relying-party requirements for passkeys. In PASSKEY_INTEGRATION_PLAN.md, the flow is presented almost like a local device feature, but Apple passkeys are WebAuthn credentials for a relying party. You need a real associated domain, server-generated challenges, and server-side registration and assertion verification. The repo here does not contain that app/backend stack, and the line between “wallet backup” and “service authentication” is not modeled clearly in the plan. This is not just an iOS UI task.

4. Medium: the Bark-side recovery direction is real, but the client gap is larger than the document suggests. The server mailbox protocol does support recovery-ID messages in mailbox_server.proto, Bark does post those IDs in mailbox.rs, and the wallet currently ignores them in mailbox.rs. That supports the general direction of the plan. But reading that mailbox from Swift is not a free “existing API” call: in this repo it is mailbox-level gRPC plus wallet-derived authorization, not a ready-made wallet REST endpoint. So “no Rust FFI changes needed” and “implement in BarkWalletFFI” are in tension with each other in PASSKEY_INTEGRATION_PLAN.md.

5. Medium: the document is not implementation-ready from this workspace because the Arke iOS files it names are not present here. I can evaluate the Bark assumptions, but I cannot verify the proposed Swift file changes, entitlements, or current app architecture against the actual app code from this repo because those paths are absent.

**Assessment**

The Bark-side premise is partly sound: recovery VTXO IDs do exist, import exists, and the current wallet ignores recovery mailbox messages. That is a legitimate product opportunity.

The plan still needs a substantial rewrite before you should build from it. Right now it overclaims recoverability, uses the wrong passkey primitive for encryption, and compresses a real server-side WebAuthn project into what reads like a local iOS feature. I would not treat PASSKEY_INTEGRATION_PLAN.md as an execution-ready design.

**What I would change**

1. Rewrite the recovery section around the actual Bark gap: recovery mailbox IDs are posted, but there is no cold-recovery path from ID to encoded VTXO with the current wallet REST API. Decide whether to add a new server endpoint, include full encoded VTXOs in recovery transport, or implement recovery handling inside Bark itself.

2. Rewrite the passkey section as either:
   a. passkeys for account authentication to your backend, with encrypted mnemonic stored separately, or
   b. iOS 18+ only, using PRF explicitly for symmetric-key derivation.
   Do not use credential ID as key material.

3. Split the plan into three deliverables: Bark protocol and server changes, Swift binding or transport changes, and app UX changes. That will make the real dependencies visible.

If you want, I can turn this into a revised plan structure that is actually implementable for an iOS app on top of this repo.

---

From bark swift bindings repo:

I’m reviewing the passkey integration plan as a design/code review task. I’ll read the plan and pull a small amount of surrounding repo context so I can evaluate whether the proposal fits the current Swift bindings and likely iOS integration points.

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/PASSKEY_INTEGRATION_PLAN.md#1-1), lines 1 to 400

Searched for regex `passkey|webauthn|AuthenticationServices|ASAuthorization|credential|biometric` (`**/{swift/**,README.md,PASSKEY_INTEGRATION_PLAN.md}`), 158 results

Read memory

The plan is more than a high-level roadmap; it makes specific API, security, and file-structure claims. I’m checking the riskiest parts against the bindings in this repo and the Apple passkey model so the review is grounded rather than speculative.

Searched for regex `importVtxo|import_vtxo|exportVtxo|export_vtxo` (`**/swift/**`), 4 results

Searched for regex `protocol BarkWalletProtocol|class WalletManager|func sync\(|importVtxo` (`**/swift/**`), 6 results

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/PASSKEY_INTEGRATION_PLAN.md#560-560), lines 560 to 1040

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/swift/Sources)

I’ve confirmed the bindings expose `importVtxo()` and `sync()`, but the plan also assumes new recovery-mailbox methods and an app-side file layout that do not exist in this repo. I’m reading the relevant Swift interface and the rest of the plan sections now to separate viable pieces from incorrect assumptions.

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/PASSKEY_INTEGRATION_PLAN.md#1040-1040), lines 1040 to 1290

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/swift/Sources/Bark/Bark.swift#740-740), lines 740 to 980

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/swift/Sources/Bark/Bark.swift#1228-1228), lines 1228 to 1262

The main risk is whether the plan’s passkey design matches Apple’s security model at all. I’m checking that now, because if the credential model is wrong, most of the document’s crypto and recovery flow needs to be reworked rather than refined.



Fetched 2 resources

I’ve confirmed the passkey design section is the biggest problem: it treats a WebAuthn credential as if it were a local encryption key, which is not how Apple passkeys work. I’m doing one more pass through the Rust/Swift surface to see whether the proposed recovery-mailbox path is actually available via bindings or would require separate client code.

Searched for text `recovery mailbox|sync_mailbox|mailbox|encoded|import-vtxo|wallet/vtxos|recovery` (`**/{swift/**,rust/**,golang/rust/**,kotlin/rust/**,dart/**,README.md}`), 200 results

Searched for regex `getRecoveryVtxoIds|getEncodedVtxo|exportVtxo|exportAllVtxos` (`**/{swift/**,rust/**,golang/rust/**,kotlin/rust/**,dart/**}`), no results

Searched for regex `ASAuthorizationPlatformPublicKeyCredentialProvider|AuthenticationServices|CryptoKit|kSecAttrSynchronizable` (`**/swift/**`), no results

There is one useful surprise: the bindings already expose mailbox identity and authorization, which could support an app-side recovery client. That makes the recovery-mailbox idea more plausible than the plan states, but it also means the proposed API additions are not the minimal integration path.

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/swift/Sources/Bark/Bark.swift#1260-1260), lines 1260 to 1290

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/swift/Sources/Bark/Bark.swift#2436-2436), lines 2436 to 2468

Searched for regex `mailboxAuthorization|mailboxIdentifier` (`**/swift/**`), 4 results

Searched for text `mailbox` (`**/README.md|swift/README.md|swift/Sources/Bark/Bark.swift`), no results

Read [](file:///Users/christoph/workspace/bark-ffi-bindings/PASSKEY_INTEGRATION_PLAN.md#1-1), lines 1 to 220

I have enough to review it now. I’m writing up the concrete issues first, then I’ll add a short set of open assumptions and the most defensible direction for revising the plan.

Created memory file [](file:///Users/christoph/Library/Application%20Support/Code/User/workspaceStorage/187e51365fd416f1e3da5b879fdf4a0a/GitHub.copilot-chat/memory-tool/memories/repo/bark-bindings-notes.md)

**Findings**

- Critical: The plan’s core crypto model is not compatible with Apple passkeys. It proposes deriving a symmetric key from a passkey credential ID and using that to encrypt the mnemonic in PASSKEY_INTEGRATION_PLAN.md and again in the appendix example at PASSKEY_INTEGRATION_PLAN.md. But the same document’s API section shows standard WebAuthn-style registration and assertion flows with a relying party and challenge in PASSKEY_INTEGRATION_PLAN.md. Those credentials authenticate to a relying party; they are not app-local secret material you can turn into an encryption key. As written, the main “encrypt mnemonic with passkey” design is not implementable securely.

- High: The document contradicts itself on whether bindings work is needed for mailbox recovery. It claims the pragmatic path requires no Rust FFI changes in PASSKEY_INTEGRATION_PLAN.md, then Phase 1 immediately requires new wallet protocol and FFI methods in PASSKEY_INTEGRATION_PLAN.md. In this repo, the Swift bindings already expose importVtxo at Bark.swift plus mailboxAuthorization and mailboxIdentifier at Bark.swift. So the least-risk plan is either:
  1. app-side mailbox client using existing bindings plus direct server calls, or
  2. explicit new bindings work.
  The plan currently mixes both.

- High: Passkey mode still keeps an unencrypted local mnemonic copy, which materially weakens the whole security story. The data flow and storage sections say passkey mode stores a local plaintext mnemonic for speed in PASSKEY_INTEGRATION_PLAN.md and PASSKEY_INTEGRATION_PLAN.md. If that item is available after ordinary device unlock, the passkey layer becomes mostly decorative: an attacker who gets app/keychain access on-device bypasses the “secure recovery” path entirely.

- Medium: The plan overstates current self-custody capabilities. It presents “Pure Manual” as including manual VTXO export/import and “Full self-sovereignty” in PASSKEY_INTEGRATION_PLAN.md, but later acknowledges export is missing and would need new implementation in PASSKEY_INTEGRATION_PLAN.md. That is a product and UX mismatch. If export does not exist today, Level 3 should not be described as already available.

- Medium: The execution details are not scoped to this repo, which makes the plan hard to act on from bark-ffi-bindings alone. The file-change sections target Arke app paths outside this workspace in PASSKEY_INTEGRATION_PLAN.md and elsewhere, while the only verified binding surface in this repo is the generated Swift package under Bark.swift. The plan should separate:
  1. bindings repo work,
  2. iOS app work,
  3. server/API assumptions.

**Open Questions**

- Is the real goal passkeys, or just iCloud-synced secure backup with biometric gating? Those are not the same thing. If the goal is “recover wallet on another Apple device,” synchronizable Keychain plus access control is a much cleaner primitive than WebAuthn passkeys.

- What is the actual recovery-mailbox transport the app will use? The current bindings expose mailbox identity/authorization, but not mailbox read helpers. That suggests an app-side network client may be enough, but the plan should name the concrete endpoint or protocol instead of relying on conversation notes.

- Is the encrypted mnemonic meant to sync as a Keychain item, or live on your backend keyed by a verified passkey account? The plan currently reads like both.

**Recommended Direction**

Reframe the design around iCloud-synced secret storage, not passkey-derived encryption. Then keep mailbox recovery as a separate app-side recovery feature built around the existing binding surface: sync, importVtxo, mailboxAuthorization, and mailboxIdentifier.

If you want, I can turn this into a revised version of the plan with the invalid passkey sections replaced by an implementable iOS architecture.
