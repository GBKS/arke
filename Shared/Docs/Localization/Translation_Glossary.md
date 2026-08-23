# Translation Glossary — German (de), Japanese (ja) & Traditional Chinese (zh-Hant)

Canonical terminology for translating Arké. **One meaning, one term, everywhere** —
translators and reviewers must not improvise alternatives per screen. Terms marked
⚠️ are proposals pending native-speaker review; everything else is decided.

Decisions locked 2026-08-18 (user):
- **German register: du** (informal — modern fintech standard; matches Arké's tone).
- **Balance names are translated**, not kept as English product terms.

zh-Hant added 2026-08-23 (Hong Kong conference demo). Conventions follow
Apple's Taiwan-flavored zh-Hant (網路, 匯入, 復原) — Hong Kong devices set to
中文(香港) resolve to zh-Hant when no zh-HK exists, and HK readers are fluent in
both conventions. Register mirrors the German du decision: plain 你, never 您.
The zh-Hant first pass is entirely ⚠️ pending native review.

---

## Core product terms

| English | German (du) | Japanese | Notes |
|---|---|---|---|
| Arké | Arké | Arké | Brand — never translated or transliterated. |
| Payments (balance) | Zahlungen | 支払い | Decided. The everyday-word metaphor is the point. |
| Savings (balance) | Erspartes | 貯蓄 | Decided. |
| wallet | Wallet (das) | ウォレット | Industry standard; never „Geldbörse". |
| bitcoin / Bitcoin | Bitcoin | ビットコイン | |
| sats / sat | Sats / Sat | sat | Unit stays Latin script in ja. |
| balance | Guthaben | 残高 | |
| transaction | Transaktion | 取引 | ⚠️ ja: 取引 in user-facing copy, トランザクション acceptable in Data/debug screens. |
| send | senden | 送金する | |
| receive | empfangen | 受け取る | ja noun form: 受取 |
| move (between balances) | verschieben | 移動 | The boarding/offboarding UX verb. |
| boarding (error contexts) | ⚠️ Übertrag | ⚠️ ボーディング | Only surfaces in errors ("Boarding Failed" → „Übertrag fehlgeschlagen"). Native review: is a coined term better than jargon? |
| forced move | erzwungene Verschiebung | 強制移動 | Arké's UX term for a unilateral exit. |
| exit (technical) | Exit | エグジット | Data/debug screens only; keep as jargon. |
| claim | einlösen | 回収 | Exit funds becoming spendable. |
| refresh (VTXO) | erneuern | 更新 | Never „aktualisieren" (that's UI refresh). |
| round (Ark round) | Runde | ラウンド | |
| check in (forced move) | vorbeischauen | アプリを開く | ja: describe the action, don't transliterate "check in". |
| Ark server | Ark-Server | Arkサーバー | |

## Keys, backup, devices

| English | German (du) | Japanese | Notes |
|---|---|---|---|
| recovery phrase | Wiederherstellungsphrase | リカバリーフレーズ | Industry standard in both. |
| seed | Seed | シード | Technical contexts only. |
| backup | Backup | バックアップ | |
| import / export | importieren / exportieren | インポート / エクスポート | |
| primary device | ⚠️ Hauptgerät | メインデバイス | du-register friendly (not „Primärgerät"). |
| secondary device | ⚠️ Zweitgerät | サブデバイス | |
| linked devices | Verknüpfte Geräte | 連携済みデバイス | |
| unlink | Verknüpfung aufheben | 連携を解除 | |
| read-only mode | Nur-Lesen-Modus | 閲覧専用モード | |

## Payments & network

| English | German (du) | Japanese | Notes |
|---|---|---|---|
| address | Adresse | アドレス | |
| invoice (Lightning) | ⚠️ Rechnung | インボイス | de native review: „Invoice" is also common in LN tooling. |
| Lightning | Lightning | ライトニング | Network name; ja prose uses katakana, technical rows may keep "Lightning". |
| onchain | On-Chain | オンチェーン | |
| fee | Gebühr | 手数料 | |
| network fee | Netzwerkgebühr | ネットワーク手数料 | |
| confirmation(s) | Bestätigung(en) | 承認 | Bitcoin-standard ja term. |
| block / block height | Block / Blockhöhe | ブロック / ブロック高 | |
| contact | Kontakt | 連絡先 | |
| tag | Tag (das) | タグ | |
| note | Notiz | メモ | |
| QR code | QR-Code | QRコード | |
| faucet / signet / testnet | Faucet / Signet / Testnet | フォーセット / Signet / テストネット | Developer-facing contexts. |
| VTXO / UTXO | VTXO / UTXO | VTXO / UTXO | Never translated. |

---

## Traditional Chinese (zh-Hant) terms

Same table structure, kept separate so the de/ja columns above stay stable.
One meaning, one term.

### Core product terms

| English | zh-Hant | Notes |
|---|---|---|
| Arké | Arké | Brand — never translated or transliterated. |
| Payments (balance) | 支付 | Everyday-word metaphor, mirrors Zahlungen/支払い. |
| Savings (balance) | 儲蓄 | |
| wallet | 錢包 | Universal in Chinese bitcoin usage — unlike de/ja, no loanword needed. |
| bitcoin / Bitcoin | 比特幣 | |
| sats / sat | ⚠️ 聰 | Established community translation of "satoshi"; native review whether Latin "sats" reads better in tight labels. |
| balance | 餘額 | |
| transaction | 交易 | |
| send | 傳送 | Apple TW convention; 交易-context reads fine. Never 發送 (mainland-flavored). |
| receive | 接收 | Noun contexts (receiving money): 收款. |
| move (between balances) | 轉移 | The boarding/offboarding UX verb. |
| boarding (error contexts) | ⚠️ 轉入 | Only surfaces in errors ("Boarding Failed" → 「轉入失敗」). |
| forced move | 強制轉移 | Arké's UX term for a unilateral exit. |
| exit (technical) | Exit | Data/debug screens only; keep as Latin jargon like de. |
| claim | 領取 | Exit funds becoming spendable. |
| refresh (VTXO) | 更新 | UI refresh (pull-to-refresh etc.) is 重新整理 — never conflate. |
| round (Ark round) | 回合 | |
| check in (forced move) | 開啟 App | Describe the action, like ja アプリを開く. |
| Ark server | Ark 伺服器 | |

### Keys, backup, devices

| English | zh-Hant | Notes |
|---|---|---|
| recovery phrase | ⚠️ 復原片語 | Ledger-style; native review vs community term 助記詞 (mnemonic). |
| seed | 種子 | Technical contexts only. |
| backup | 備份 | |
| import / export | 匯入 / 匯出 | TW standard. |
| primary device | 主要裝置 | |
| secondary device | 次要裝置 | |
| linked devices | 已連結的裝置 | |
| unlink | 解除連結 | |
| read-only mode | 唯讀模式 | |

### Payments & network

| English | zh-Hant | Notes |
|---|---|---|
| address | 地址 | Crypto convention; not the networking term 位址. |
| invoice (Lightning) | ⚠️ 付款請求 | Function-first, avoids the tax-receipt reading of 發票. |
| Lightning | 閃電網路 | Prose; technical rows may keep "Lightning". |
| onchain | 鏈上 | |
| fee | 手續費 | |
| network fee | 網路手續費 | |
| confirmation(s) | 確認 | |
| block / block height | 區塊 / 區塊高度 | |
| contact | 聯絡人 | Apple TW. |
| tag | 標籤 | |
| note | 備註 | |
| QR code | QR Code | Latin, with surrounding spaces per style rule. |
| faucet / signet / testnet | 水龍頭 / Signet / 測試網 | Developer-facing contexts. |
| VTXO / UTXO | VTXO / UTXO | Never translated. |

## Style rules — Traditional Chinese

- **Plain 你 register**, never 您 — matches the German du decision. Imperatives
  without pronoun where natural (「輕點…」, not 「你必須輕點…」).
- **Traditional characters only** — no simplified leakage (网/发/转/钱/请 are
  bugs), and Taiwan vocabulary (網路 not 網絡, 軟體 not 軟件).
- **One half-width space between CJK and Latin/digit runs** (「3 筆交易」,
  「Ark 伺服器」), including around format specifiers whose values are Latin or
  numeric. No space before full-width punctuation.
- Full-width punctuation （，。？！、）in sentences; half-width in bare
  technical strings (URLs, key-value rows).
- **No plural forms**: every English plural-variation key collapses to a single
  form. Measure words: 筆 for transactions/payments, 部 for devices, 個 as
  general fallback (「%lld 筆交易」).
- Button labels stay short; zh runs shorter than English — don't pad
  (「刪除」, not 「立即刪除」 unless English has the emphasis).

---

## Style rules — German

- **du, always lowercase** („du", „dein", „dir"). Imperatives without pronoun where
  natural („Tippe auf…", not „Du musst tippen auf…").
- Compounds joined with a hyphen when one part is English: Lightning-Rechnung,
  Ark-Server, QR-Code.
- Button labels stay short — German runs ~30% longer; prefer „Löschen" over
  „Jetzt löschen" unless English has the emphasis.
- Decimal/thousands separators and dates come from formatters — never hardcode.

## Style rules — Japanese

- **です・ます register** throughout; no plain form except tight labels.
- Full-width punctuation（。、）in sentences; no spaces around interpolated values
  unless the value is Latin script (then one space each side is acceptable).
- No plural forms exist: every English plural-variation key collapses to a single
  "other" form in ja. Counters: prefer 「件」 for transactions/items where a bare
  number reads oddly (「3件の取引」).
- Avoid stacking katakana loanwords where a plain term exists (受け取る not
  レシーブ), but keep established bitcoin vocabulary (ウォレット, アドレス).

---

## Mechanics (both languages)

1. **Reordering arguments**: use positional specifiers in your value —
   `%1$@`, `%2$lld` — whenever your word order differs from English. The guard
   test (`LocalizationCatalogTests.specifierParity`) fails mismatched types.
2. **Never leave a value empty** — delete the entry instead (falls back to
   English). Empty values render blank text; the guard test fails them.
3. **`^[…](inflect: true)` in English values is English-only.** Keys using it
   (`activity_confirmation_count %lld`, `accessibility_vtxo_graph_bar %@ %lld`)
   need explicit plural variations in German and a single form in Japanese.
4. **Do not translate** keys marked `shouldTranslate: false` (symbols, `app_name`,
   bare format strings) — they're hidden from export anyway.
5. English source values live in code (`defaultValue:` / `L10n`) — if the English
   itself needs fixing, that's a code change, not a catalog edit
   (see `Localization_Guidelines.md`).
6. **Ambiguous short strings** ("Change", "Status", "Open"): check the key's
   prefix for context (`button_` = action, `label_` = noun, `status_` = state).
   If still ambiguous, flag it — we add a translator `comment:` in code rather
   than guessing.
