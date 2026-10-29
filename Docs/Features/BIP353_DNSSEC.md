# BIP-353: DNSSEC Validation So Human-Readable Addresses Work Again

**Status: DONE 2026-10-29 (Tier 0 "Send inputs"), option B. Merging the
Tier 0 "stop sending the query" entry and the Tier 1 "full DNSSEC
implementation" entry into one item was DECIDED 2026-10-29. Probes on the
Mac, the simulator, and the phone on home Wi-Fi and on cellular (§3) all
show the OS validator hanging, so option A is off the table. Christoph
chose B the same day so BIP-353 names work again; the plan records B as a
documented deviation from the BIP's "MUST NOT trust a remote resolver"
(§4), with a PROPOSED route to close it through bark-ffi (§4). Built,
reviewed and fixed the same day (§5, §6): 24 new tests, full mobile suite
607/607, live check against both resolvers, and Christoph's phone check
(§6) all green. Moved to the Done log 2026-10-29.**

## 1. What is wrong today

Verified by reading `BIP353Resolver` (unchanged since commit 0bae6ad):

- `resolve` runs `performDNSLookup` first and `validateDNSSEC` second.
  `validateDNSSEC` is a stub that returns false, so every BIP-353 lookup
  throws `dnssecValidationFailed`. The TXT query is still sent and its answer
  thrown away: the network's resolver learns who the user is about to pay
  and the user gets nothing for it. That is the Tier 0 complaint.
- The failure is invisible in practice. All five callers
  (`SendViewModel+Clipboard` twice, `SendViewModel+Initialization`,
  `ManualSendView.resolveBIP353Address`,
  `ContactPaymentView.resolveBIP353Address`) fall back to
  `LightningAddressResolver`, which is authenticated by TLS, and for a
  `user@domain` name that usually succeeds. A `₿user@domain` name has no
  fallback and fails with "DNSSEC validation failed - address may be
  compromised", which blames the payee for the app's missing feature.
- The stub's comment claims the DNS Service Discovery API does not expose
  DNSSEC results. The iOS 27.1 SDK header says otherwise (§2).
- Two more defects in `performDNSLookup`, recorded 2026-10-08 and now
  confirmed against live records (§3): only the first character-string of
  the TXT RDATA is read, and the socket is serviced with one `select` plus
  one `DNSServiceProcessResult`, so a reply split across callbacks with
  `kDNSServiceFlagsMoreComing` can leave the continuation hanging until the
  10 s timer.
- No test anywhere in the repo touches the resolver.

Related but out of scope: `detectFormatOrNil` accepts a plain
`user@domain`, which is the shared root of the Tier 0 paste-fallback item
and the Tier 1 address-header proposal (d). One detector fix serves those
two; this plan does not change the detector.

## 2. What the platform offers (claims labelled)

| Claim | Label | Source |
|---|---|---|
| `DNSServiceQueryRecord` accepts `kDNSServiceFlagsValidate` (0x200000) and reports `kDNSServiceFlagsSecure` / `Insecure` / `Bogus` / `Indeterminate` in the callback flags; the status may arrive in a later callback carrying zero-length rdata and applies to the whole RRset | verified | iOS 27.1 SDK `dns_sd.h`, flag block after `kDNSServiceFlagsIncludeAWDL` |
| The header calls the flag "temporary" and the client API "not finalized" | verified | same block, `kDNSServiceFlagsEnableDNSSEC` comment |
| `kDNSServiceFlagsValidateOptional` falls back to no validation when the chain cannot be fetched, and the header says it MUST NOT be used when validation is required | verified | header and DocumentationSearch |
| Foundation and Network expose the same validator (`URLRequest.requiresDNSSECValidation`, `NWParameters` `dnssecValidationRequired`) | verified | DocumentationSearch |
| The OS validator answers on real iPhone networks (Wi-Fi behind a home router, cellular) | **assumed, contradicted on the Mac** (§3) | needs the phone probe |
| bark or the bindings resolve BIP-353 | verified no | bark server only carries a `bip353` field on offers; bindings have no symbol |
| BIP-353 rules (read from the BIP text 2026-10-29): the name is `user.user._bitcoin-payment.domain`; "all payment instructions MUST be DNSSEC-signed"; "clients MUST fully validate DNSSEC signatures leading to the DNS root"; "clients MUST NOT trust a remote resolver to validate DNSSEC records on their behalf"; TXT character-strings are concatenated "in RDATA order, without inserting separators"; records not beginning with `bitcoin:` (ignoring case) are ignored; "multiple bitcoin:-matching TXT records at the same label" make the answer invalid; the result "MUST NOT" be cached longer than the TTL; verified names "SHOULD" be displayed with a ₿ prefix | verified | WebFetch of bip-0353.mediawiki |
| Cloudflare and Google DNS-over-HTTPS JSON: both return `Status` (0 NOERROR, 3 NXDOMAIN), `AD`, `TC` and an `Answer` array of `{type, TTL, data}`; Cloudflare's TXT `data` is one or more double-quoted strings separated by a space, Google's is the already-concatenated unquoted text; an unsigned zone gets `AD: false`, a signed NXDOMAIN `AD: true` with `Status: 3` | verified | curl 2026-10-29, both endpoints, three names |

## 3. Probe results, 2026-10-29

Throwaway probe compiled from `/tmp/arke-dnssec-probe/probe.swift` (not in
the repo): `DNSServiceQueryRecord` for TXT with the flag under test,
serviced by `DNSServiceSetDispatchQueue`, against two live BIP-353 names
and a signed control zone. Mac: macOS 27.2, resolver 192.168.178.26 (the
router), which passes RRSIGs but does not set the AD bit.

| Flag | Result |
|---|---|
| none | both records arrive within milliseconds. The first TXT record is 492 bytes in two character-strings, so today's first-string-only parser truncates real BIP-353 records. The first callback carries `MoreComing`. The decoy record ("as long as it doesn't start with bitcoin:…") arrives second and is correctly ignored by the `bitcoin:` prefix filter |
| `kDNSServiceFlagsValidate` | no callback at all in 25 s, for the BIP-353 name and for `example.com` |
| `kDNSServiceFlagsValidateOptional` | records arrive with no status bits; the only extra bit is `kDNSServiceFlagAnsweredFromCache`. Falls back to unvalidated exactly as the header warns |
| `DNSServiceGetAddrInfo` + Validate | no callback in 20 s for `www.example.com` |
| `URLRequest.requiresDNSSECValidation` | both requests time out after 20 s |

Same machine, same minute: `dig +dnssec` through the router returns the
RRSIGs; `dig @1.1.1.1` and Cloudflare's DNS-over-HTTPS JSON endpoint return
the answer with AD set. So the data is there and a validating resolver is
reachable; the OS validator itself does not complete behind this router.
Mandatory validation on the Mac means a 10 s hang and a timeout error, not a
clean "Insecure".

Simulator run of the probe screen (§6), iPhone 17e simulator, iOS 27.0,
same Mac and router, 2026-10-29 15:57: identical outcome. All four names
hung for the full 15 s under the validate flag, the plain queries answered
in under 0.1 s, the optional flag answered from cache with no status bits,
both URL loads timed out at about 16 s. The simulator shares the Mac's
mDNSResponder, so this verifies the probe tool, not iOS.

**Phone, home Wi-Fi** (iPhone, iOS 27.2, same router, 2026-10-29 15:03Z,
report pasted by Christoph): identical to the Mac and the simulator. All
four names hung the full 15 s under the validate flag, including the signed
and the unsigned control, so the validator returns neither SECURE nor
INSECURE on this network. Plain queries answered in about 0.1 s with the
same two-string records. The optional flag answered from cache with no
status bits. Both URL loads with `requiresDNSSECValidation` timed out at
about 16 s. Consequence: option A alone cannot serve users on home Wi-Fi
behind a non-validating router, which is the common case. The validator
still has to be tried on a network with a validating resolver before A is
declared dead.

**Phone, cellular** (same iPhone, Wi-Fi off, path "cellular, expensive",
2026-10-29 15:05Z): identical again. All four names hung the full 15 s
under the validate flag, plain queries answered in about 0.1 s, the
optional flag returned cached records without status bits, both URL loads
timed out. So the validator fails on the carrier's resolver as well, not
only behind the home router.

**Probe plumbing verified, 2026-10-29 16:18 (after a second reviewer
asked whether the hang could be the probe's own fault).** A second Mac
probe serviced the socket by hand with `select` and
`DNSServiceProcessResult`, so no dispatch queue was involved, and printed
every return value: `DNSServiceQueryRecord` returned 0 with the reference
set, the socket descriptor was valid, and `DNSServiceProcessResult` was
never reached because the socket never became readable. The callback logs
every invocation including error codes and empty rdata, so nothing was
filtered. Adding `kDNSServiceFlagsReturnIntermediates`, alone or with
`kDNSServiceFlagsUnicastResponse`, changed nothing: zero callbacks in 12 s
under the validate flag, two callbacks within 10 ms without it, same
binary. mDNSResponder's own log for the validate run (`log show --info
--debug`, process `mDNSResponder`) settles where the time goes: it logged
the query as "DNSSEC enabled, flags: 0x200000", received the TXT RRset with
its RRSIG from the router within 50 ms, then started validation
sub-queries for the zone DNSKEY (fetched over UDP), the zone DS, the `.com`
DNSKEY and DS, and the root DNSKEY (the last four served from its cache).
Every record was logged "validated: no", no verdict, trust-anchor or error
line ever followed, and the chain sat idle until our deallocate cancelled
it twelve seconds later ("Canceling the existing validation key
requestor"). The stall is inside mDNSResponder's validator after it holds
the complete chain, not in the client. Note for re-runs: the DNSSEC lines
are Info level and were gone from the log store within minutes; capture
them in the same minute as the probe.

Conclusion: on iOS 27.2 and macOS 27.2 the mandatory-validation flag is
accepted, the validator fetches the chain, and it never reaches a verdict,
on every network tried; the optional flag never validates. Option A is not
buildable today. Not verified: a network whose resolver validates (AD bit
set), where mDNSResponder might behave differently; nothing in the app
should depend on that.

## 4. Options

**A. OS validator.** Pass `kDNSServiceFlagsValidate`, accept only Secure.
Real chain validation to the system trust anchor, no new trust, no new
dependency. Risk: §3. If the phone behaves like the Mac on home Wi-Fi,
BIP-353 works on cellular and fails slowly on most home networks.

**B. Validating DNS-over-HTTPS resolver.** Query a public validating
resolver over HTTPS and require AD=1 and NOERROR. Works wherever HTTPS does,
deterministic, fast, easy to test with a stubbed transport. Cost: trusts the
resolver operator to validate honestly; that is a different adversary than
the LAN or ISP the BIP guards against, but it is not the BIP's "MUST
validate". Querying two independent resolvers and requiring identical
RRsets with AD set narrows the trust to collusion. The payee name is
revealed to the resolver operator, as it is to any resolver.

**C. Offline proof verification.** Fetch a DNSSEC proof from a proof server
and verify RRSIG, DNSKEY and DS up to the root anchor in-app (the approach
BIP-353's reference tooling takes). Full validation with no resolver trust,
but it is ECDSA, Ed25519 and RSA signature checks plus DNS wire parsing in
Swift, and no Swift library exists in the project. Not proposed now.

**Recommendation (final after both phone reports, §3).** Build B: a
validating DNS-over-HTTPS lookup, two independent resolvers (Cloudflare and
Google, both set AD for the test names), accept only when both answer
NOERROR with AD set and the TXT RRsets are identical after character-string
concatenation. Put it behind a protocol-typed validation step so A can be
slotted in if Apple ships a working validator. A is not built now. The
first-resolver-only shortcut is not proposed: two operators colluding is the
residual trust, and that is the point of the pair.

**Documented deviation from BIP-353 (DECIDED 2026-10-29).** The BIP says
clients "MUST fully validate DNSSEC signatures leading to the DNS root" and
"MUST NOT trust a remote resolver to validate DNSSEC records on their
behalf". B does trust remote resolvers, two of them, over TLS, and requires
both to agree. It does not verify the chain in-app, and the BIP's rule
against SHA-1 and short RSA keys is therefore delegated to the resolvers as
well. This is stronger than today's "refuse everything" and than the
Lightning-address path's TLS-only trust, and weaker than the BIP's letter.
The residual risk is both resolver operators lying in concert, or both
being compromised at once, or (review F4) a root certificate the user or an
MDM profile installed on the device, which lets whoever holds it forge both
HTTPS endpoints from the LAN; the app does not pin certificates, like every
other HTTPS call it makes. Option C removes those residuals and is the
route if the deviation is ever to be closed; the validation step is a
protocol so C can replace B without touching the callers.

**PROPOSED (2026-10-29): close the deviation through bark-ffi.** The
reference validator, Matt Corallo's `dnssec-prover` 0.6.8, is already
linked into the app: bark depends on LDK's `lightning` 0.2.2, which
depends on it (verified in the bindings' `swift/rust/Cargo.lock`). It is
not exposed by the FFI. One bark-ffi function that resolves a BIP-353 name
with a verified RFC 9102 proof, or returns the proof for the app to check,
would become a third `DNSTXTSource` with no new dependency and no Rust
toolchain on our side. Alternatives surveyed the same day: building our own
UniFFI Swift package from the crate's `uniffi` directory (needs a Rust
build pipeline the project lacks), `bip353-rs` (same), and `DNSKit`, the
one Swift-native validator, which is LGPL-3.0 and would need a licensing
ruling first. Recorded in the backlog under Tier 4 "Bindings adoption";
the ask to Second is Christoph's.

## 5. What was built (2026-10-29, option B)

1. `Shared/Helpers/BIP353Resolver.swift` rewritten. The dnssd lookup, its
   `fd_set` helpers and the stub are gone. `DNSTXTSource` is the protocol
   (name, `queryTXT`), `DoHJSONSource` the DNS-over-HTTPS JSON implementation
   with an injectable fetch closure and two static instances (Cloudflare with
   the `application/dns-json` Accept header, Google without), and
   `TXTRecordData.concatenated` turns the presentation form into the
   BIP's concatenated string by working on bytes, so `\DDD` escapes and
   multi-byte UTF-8 come out identical to Google's already-decoded text.
2. `BIP353Validation.combine` is the policy, in this order: fewer than two
   answers → lookup failed; any SERVFAIL → `resolverFailure` (SERVFAIL
   carries AD=false by definition, so it must not read as "unsigned", review
   F1); all NXDOMAIN → `noDNSRecord` when authenticated, else
   `dnssecValidationFailed`; mixed response codes → `resolversDisagree`; any
   AD=false → `dnssecValidationFailed`; all record sets empty →
   `noDNSRecord`; then the `bitcoin:` candidates (case-insensitive) must be
   identical across resolvers, sibling records are not compared (review
   F2/F3: the providers escape them differently and they carry no payment).
   `selectBitcoinURI` then requires exactly one candidate.
3. Error text: seven localized `BIP353Error` descriptions, none of which
   calls the address compromised for a lookup problem. The three callers
   that show both the BIP-353 and the Lightning reason
   (`SendViewModel+Initialization`, `ManualSendView`, `ContactPaymentView`)
   keep both, localized under one key; the reasons are now human sentences,
   so the earlier "log only" idea was dropped.
4. Callers unchanged otherwise. `ResolvedBIP353.dnssecVerified` is gone with
   its two dead branches in `SendViewModel+Clipboard`; a success now means
   both resolvers authenticated. The `user@domain` race in
   `tryParallelResolution` can now be won by BIP-353 (review F6; see §6).
   Cancellation from a lost race is rethrown without an error log.
5. Cache: per address, no longer than the smallest TTL, capped at 10
   minutes, not written on failure.
6. Tests: `Tests/Shared/BIP353ResolverTests.swift`, four suites, 24 tests,
   fixtures are the real dns-json bodies from both providers captured on
   2026-10-29. No test touches the network.

## 6. Verification owed

- Phone probe before building: DONE 2026-10-29, results in §3. The tool was
  a DEBUG-only `DNSSECProbeView` behind a "DNSSEC probe" row under Settings
  → Behind the curtain, smoke-run on the simulator, run twice on the phone,
  then deleted from the tree the same day without being committed. It ran
  the validate flag first (cold), then plain, then the optional flag,
  against the two BIP-353 names and two controls (`example.com` signed,
  `google.com` unsigned), then two URL loads with
  `requiresDNSSECValidation`, and reported the network path. Rebuild it from
  this description if Apple's validator needs re-testing after an iOS
  update.
- Live check from the Mac, 2026-10-29 16:55, the resolver file compiled
  standalone against the real endpoints: `₿matt@mattcorallo.com` resolved
  to its 490-character URI in 0.19 s (TTL 3600, cache capped at 600 s);
  `satoshi@twelve.cash` was refused as `multipleBitcoinRecords` in 0.47 s,
  correctly, because that zone publishes five `bitcoin:` TXT records and
  the BIP declares that invalid; `nobody@mattcorallo.com` gave
  `noDNSRecord` and `someone@google.com` gave `dnssecValidationFailed`
  (unsigned zone), each in under 0.1 s; the repeat lookup was served from
  the cache. The in-app snippet runner cannot launch the app here (static
  bark framework), hence the standalone build.
- On the phone, DONE 2026-10-29 (Christoph): `₿matt@mattcorallo.com`
  resolved and worked; `satoshi@twelve.cash` was reported invalid, as the
  five-record zone must be; a working plain Lightning address resolved and
  worked, so the BIP-353 leg's "no payment instructions" failure let the
  Lightning leg win as intended (review F6 closed).
  Type a plain Lightning address such as the one from a Wallet of Satoshi
  user: the BIP-353 leg must fail with "no payment instructions" and the
  Lightning leg must win. Try once with Wi-Fi on a network that blocks
  `dns.google` if one is at hand: BIP-353 must fail closed within ten
  seconds and the Lightning path still work (review F6 and the blocked-
  resolver case are the two unverified behaviours).
- Adversarial pass: done 2026-10-29 by the fault-class reviewer on the
  uncommitted diff. F1 (SERVFAIL read as "unsigned") and F5 (third error
  string missed by the sweep) CONFIRMED and fixed; F2/F3 (provider escaping
  differences) fixed by byte-level decoding and comparing payment records
  only; F4 (user-installed root CA) recorded in §4; F6 (race now winnable)
  is a device item above. Its own unverified list: Google's escaping of
  quotes and non-ASCII in TXT data, behaviour on networks that block a
  resolver, the full mobile suite.
- Not seed-touching; no two-device step.

## 7. Backlog bookkeeping

Tier 0 holds the merged entry; the Tier 1 "BIP-353 DNSSEC validation" entry
was removed 2026-10-29 and its two resolver defects live in §1 here. The
Tier 3 lines it blocked (BIP-353 vs Lightning-address logic, resolved-address
display, header proposal (d)) now point at this plan.
