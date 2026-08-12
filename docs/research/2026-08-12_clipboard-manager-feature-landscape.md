# Clipboard Manager Feature Landscape for Stow

- Research date: 2026-08-12
- Scope: clipboard managers, launcher-integrated clipboard histories, built-in operating-system histories, and adjacent local-first memory tools.
- Primary platforms: macOS, iOS/iPadOS, Windows, and Linux.
- Product goal: identify the feature space and prioritize ideas that fit Stow's local-first universal content inbox.

## 中文摘要

這份研究涵蓋 20 多款 clipboard manager、系統內建剪貼簿與相鄰的 AI 工作記憶產品。

市場的共同基礎已從「保存歷史」進化為安全擷取、快速檢索、長期整理、結構化貼上、隱私控制與可選自動化。

Stow 現有優勢是快捷面板、內容原生預覽、Inbox/Archive/Trash 生命週期、直接貼上降級策略、Apple 裝置同步與受限的本機 agent CLI。

最優先缺口不是重新設計介面，而是先處理敏感資料排除、依 App 忽略、保留原始 pasteboard 格式、重複內容合併與歷史保留策略。

下一層高價值功能是 sequential Paste Queue、本機 OCR、使用者 collections、多項文字合併與完整備份還原。

文字轉換、smart collections、本機語意搜尋與更多 agent commands 適合放在基礎可靠性完成後。

不建議近期加入任意腳本執行、原始 clipboard 協作分享、持續螢幕或音訊錄製，或讓 AI 成為唯一搜尋路徑。

## Evidence standard

- **A — strong:** current official manual, first-party product page, first-party repository, or operating-system documentation.
- **B — useful:** current App Store listing, first-party changelog, or first-party marketing claim without detailed implementation documentation.
- **C — directional:** App Store review, vendor-authored comparison, third-party review, or older documentation.
- A blank or “not verified” entry means the research did not find reliable evidence, not that the feature definitely does not exist.
- Prices and packaging change frequently, so this report emphasizes business model rather than exact regional price.

## Executive conclusion

The market no longer competes only on keeping a clipboard history.

Strong products combine six layers: safe capture, fast retrieval, reusable organization, structured paste workflows, privacy controls, and optional automation or intelligence.

Stow already has an unusually strong retrieval and durable-library foundation.

Its largest competitive gaps are not visual polish.

They are safe capture controls, original-format preservation, duplicate handling, sequential paste, OCR retrieval, and reusable collections or templates.

The best near-term direction is to make Stow the safest and most dependable path from transient clipboard data to a durable inbox.

Stow should not become a launcher, macro IDE, passive screen recorder, or AI memory system merely because adjacent products offer those capabilities.

## Market archetypes

| Archetype | Representative products | Main promise | Typical tradeoff |
| --- | --- | --- | --- |
| Minimal history | Maccy, Clipy, Flycut | Keep recent copies and retrieve them quickly | Little organization, sync, or automation |
| Visual Apple clipboard | Paste, PastePal, PasteNow, CleanClip | Rich previews, Apple-device sync, and polished retrieval | Subscription or larger feature surface |
| Workflow clipboard | Pastebot, Copy 'Em, LaunchBar, Keyboard Maestro | Transform, merge, queue, and paste many items efficiently | More concepts and configuration |
| Launcher-integrated | Raycast, Alfred, LaunchBar | Clipboard access inside an existing keyboard command surface | Clipboard is not the product's only responsibility |
| Power-user programmable | CopyQ, Keyboard Maestro, ClipboardFusion | Scripts, triggers, commands, macros, and custom actions | High cognitive load and security surface |
| OS built-in | Windows 11 Clipboard, macOS Tahoe Spotlight | No installation and familiar system entry point | Short retention, shallow organization, limited formats |
| Privacy-first intelligent | Deck, Pastery | OCR, semantic retrieval, local AI, and stronger security controls | Newer products with maturity or packaging risk |
| Universal content workspace | Stow, PasteBar | Clipboard plus durable content organization and lifecycle | Risk of blurring history, inbox, and knowledge-base roles |
| Passive work memory | Pieces | Searchable cross-app context and AI recall | Very broad capture permissions and a different privacy model |

## Complete feature taxonomy

| Area | Features found across the market |
| --- | --- |
| Capture | Background monitoring, explicit save, pause/resume, app exclusions, window-title rules, regular expressions, content-type rules, size limits, secret-marker detection, sensitive-number detection, screen-share hiding, multi-file capture |
| Content fidelity | Plain text, rich text, HTML, RTF, links, images, files, colors, email addresses, code, emoji, source-app identity, device identity, IDE file/line anchors, multiple original pasteboard representations |
| History policy | Fixed or unlimited history, age retention, storage thresholds, per-type limits, recopy-to-top, duplicate coalescing, remove-after-use, transient sessions, named histories, persistent or memory-only storage |
| Retrieval | Type-to-search, full-text search, title and note search, type/app/device/date filters, regular expressions, OCR, semantic search, conversational search, context-aware ranking, recent-use ranking |
| Organization | Pin/favorite, custom collections, folders, nested groups, tabs, boards, named clipboards, tags, aliases, custom titles, smart collections, templates, snippets, Inbox/Archive/Trash lifecycle |
| Preview and edit | Content-aware cards, Quick Look, large preview, link metadata, image dimensions, source/time metadata, word/line/character counts, inline text edit, notes, rename, QR display |
| Single-item use | Copy, direct paste, copy-only fallback, paste without changing the current clipboard, paste as plain text, paste using a selected original format, quick number keys, item-specific global hotkeys, open link/file, reveal in Finder, drag and drop |
| Multi-item use | FIFO queue, LIFO stack, sequential paste, paste-and-remove, paste all, batch selection, custom ordering, merge copies, delimiter selection, join/reverse, multi-file clipboard creation, horizontal or vertical image merge |
| Transform | Case conversion, whitespace cleanup, line sort/deduplicate, prepend/append, find/replace, JSON format/minify, Base64, URL encode/decode, tracking-parameter removal, hash, timestamp parsing, image conversion, custom filter chains |
| Sync and sharing | Private iCloud, vendor cloud, Universal Clipboard, account sync, manual sync, encrypted LAN peer transfer, direct IP transfer, Mac-to-Mac send, shared collections, team administration |
| Mobile access | Custom keyboard, share/action extension, iMessage extension, widget, Control Center control, Live Activity, Dynamic Island, Siri Shortcuts, explicit save-on-open |
| Privacy and security | Local-only mode, encryption at rest, private-cloud storage, biometric or passcode lock, protected collections, ignored apps, concealed-data handling, emergency recent-history deletion, scoped deletion, clipboard auto-clear |
| Recovery and migration | Backup/restore, import/export, custom data location, database migration, history migration from competitors, index rebuild, missing-file repair, conflict handling |
| Automation | Apple Shortcuts, App Intents, CLI, URL scheme, macros, triggers, script plugins, automatic rules, API extraction, MCP, typed agent commands |
| Intelligence | OCR, code-language detection, smart content detection, semantic embeddings, AI summarize/translate/transform, natural-language actions, automatic summaries |
| Administration and accessibility | Configurable global shortcuts, keyboard-only operation, VoiceOver, large text, dark/high-contrast UI, reduced motion, managed policy, data-loss-prevention boundaries |

## Product landscape

| Product | Platform and model | Verified feature emphasis | Evidence |
| --- | --- | --- | --- |
| Paste | Mac, iPhone, iPad; subscription or lifetime | Infinite searchable history, pinboards, shared pinboards, iCloud, multi-item paste, plain-text paste, previews, editing, app exclusions, Siri Shortcuts, iOS keyboard | A/B |
| CleanClip | Mac, iPhone, iPad; commercial | Cursor-adjacent quick menu, paste queue, lists and smart lists, OCR search, batch actions, rich ignore rules, cleanup rules, iCloud, backup | A/B |
| PastePal | Mac, iPhone, iPad, Vision Pro; one-time universal purchase | Collections, type/date filtering, 75+ transforms, iOS keyboard, iMessage, share extension, widgets, Live Activity, Shortcuts, optional iCloud | B |
| PasteNow | Mac, iPhone, iPad; commercial | Smart lists, drag-out, full keyboard control, exclusions, preview/edit, iCloud, iOS keyboard, import/export | A/B |
| Pastebot 3 | Mac; direct lifetime-style purchase or App Store subscription | Custom and smart pastebins, notes, composable filters, quick-paste numbers, sequential stack, Shortcuts, CLI, Mac-to-Mac iCloud | A |
| Copy 'Em | Mac with Apple-device companion support; commercial | Saved lists, batch paste, paste queue companion, plain-text mode, transformations, global shortcuts, source/type filters, Quick Look | B/C |
| Maccy | Mac; free and open source | Minimal, fast, keyboard-first searchable local history with native UI and password-manager-aware deletion | A |
| Raycast Clipboard History | Mac documentation researched; free core and Pro retention | Rich type filters, direct paste, paste-as formats, sequential paste, OCR, QR extraction, editing, pinning, rename, snippet conversion, AI handoff | A |
| Alfred Clipboard | Mac; Powerpack | Searchable text/image/file history, configurable retention, clipboard merge, app exclusions, concealed-data handling, snippets and text expansion | A |
| LaunchBar Clipboard | Mac; commercial launcher | Configurable copy/paste action, plain text, LIFO paste-and-remove, ClipMerge, Quick Look, drag/send actions, ignore list | A |
| Keyboard Maestro | Mac; commercial automation suite | History and named clipboards, multi-select merge/paste, delimiters, image merge, custom filters/macros, favorites, Mac-to-Mac send, password heuristics | A |
| CopyQ | Windows, macOS, Linux; free and open source | Tabs, tags, pins, image tools, editing, scripting, CLI, commands, backup/export, optional encryption, secret-marker handling | A |
| Ditto | Windows; free and open source | Search, groups, sticky clips, item/global hotkeys, multiple selection, special paste, QR, encrypted LAN sharing | B/C |
| Windows 11 Clipboard | Windows; built in | Win-V history, pinning, cloud sync, manual or automatic text sync, individual deletion, clear device/cloud history | A |
| macOS Tahoe Spotlight Clipboard | macOS 26; built in | Opt-in searchable clipboard browse mode, copy previous item, clear history | A |
| GPaste | GNOME Linux; free and open source | Named histories, rich types, search/merge/edit, GUI/Shell/CLI, optional encrypted storage, password items, backend migration | A |
| Pano | GNOME Linux; free and open source, no longer maintained | Horizontal rich previews, type cycling, favorites, incognito mode, keyboard numbers, content-aware notifications | A, but stale |
| PasteBar | Mac and Windows; source available under a noncommercial license | Unlimited history, collections/tabs/boards, notes, protected collections, backup, custom data location, forms/templates, code detection | A/B |
| Deck | Mac; free, mostly source available | Keyword/regex/semantic search, OCR, tags, smart categories/rules, queue mode, templates, transforms, Touch ID, sensitive-data filters, encrypted LAN | A/B, with packaging warning |
| Pastery | Mac; commercial | Retrieval-first filters, screenshot OCR, inline developer transforms, local-only storage | B |
| Pieces | macOS, Windows, Linux; commercial adjacent product | On-device clipboard/screen/audio/app capture, semantic indexing, timeline, conversational search, MCP access, scoped deletion | A, adjacent rather than direct |
| Stow | Mac, iPhone, iPad; local-first project | Clipboard-to-Inbox capture, horizontal quick panel, durable lifecycle, typed previews, search filters, direct-paste fallback, share extensions, iCloud, agent CLI | A, repository evidence |

## Detailed findings by capability

### 1. Capture and history

The baseline feature is automatic capture of clipboard changes while the app runs.

Mature products add controls for history size, retention time, item size, supported type, and application source.

Windows keeps only 25 entries and supports text, HTML, and bitmap items up to 4 MB.

Alfred exposes retention windows and a maximum clip size.

Raycast exposes retention from one day through unlimited, with longer retention in Pro.

CleanClip exposes time-based and storage-threshold cleanup, with preservation rules for favorites and aliases.

CopyQ can disable capture entirely, ignore matching source windows, and limit data size through configuration or commands.

GPaste supports several named histories and multiple storage backends, including an intentionally non-persistent mode.

**Product lesson:** retention is not only storage management.

It is a privacy control and a promise about whether a copied item is transient or durable.

### 2. Captured content types

Text-only capture is no longer competitive for a visual clipboard product.

Common documented types include plain text, rich text, HTML, links, images, files, colors, emails, and code.

Raycast preserves all original clipboard formats and lets the user choose a representation at paste time.

Paste, PasteNow, CleanClip, CopyQ, GPaste, PasteBar, and Deck all document multiple rich content types.

Pano demonstrates content-aware presentation for image, link, text, code, color, emoji, and file items.

Deck adds Figma-specific recognition and IDE source anchors.

**Product lesson:** a clipboard item should preserve its representations first and classify them second.

Flattening rich clipboard data to a string makes later plain-text paste easy but permanently removes the user's original formatting choice.

### 3. Retrieval and search

Instant search after opening the panel is table stakes for keyboard-first tools.

Useful search dimensions include content text, title, user note, source application, content type, date, device, and collection.

Raycast filters text, images, files, links, emails, and colors.

Paste's Power Search and Pastebot search include metadata dimensions such as app, date, device, or type.

PastePal documents filters by type, collection, and date range.

PasteNow and CleanClip provide smart or rule-based lists.

Deck adds regex, slash-triggered include/exclude rules, semantic search, and context-aware ranking for the current app.

Pieces turns retrieval into conversational queries over time, source, and topic.

**Product lesson:** exact text search should remain the reliable primary path.

OCR and semantic retrieval should enrich it without making results inexplicable or network-dependent.

### 4. OCR and visual retrieval

OCR is becoming a differentiator because screenshots often contain the only copy of an error, serial number, address, or design note.

Raycast can automatically index text from copied images and offers fast or accurate recognition modes.

CleanClip added image-text search in 2024.

Deck and Pastery describe on-device OCR using Apple frameworks.

Pieces applies OCR as part of a much broader screen-memory pipeline.

**Product lesson:** clipboard-image OCR is a narrow, defensible local-first feature.

Continuous screen OCR is a different product category with much higher permission, storage, and trust costs.

### 5. Organization and long-term reuse

Most products distinguish transient history from durable reuse.

Paste uses pinboards.

Pastebot uses custom and smart pastebins.

PastePal uses collections.

PasteNow uses normal and smart lists.

CleanClip uses favorite lists, smart lists, groups, pins, and aliases.

Alfred separates history from snippets and snippet collections.

Keyboard Maestro separates history from named clipboards.

CopyQ uses tabs, tags, and pins.

Ditto uses nested groups and sticky clips.

PasteBar uses collections, tabs, and boards.

Deck uses tags, smart categories, and reusable templates.

**Product lesson:** a pin is sufficient for a small favorites set but not for a durable library of snippets, prompts, code, links, and assets.

Stow's Inbox/Archive/Trash lifecycle is stronger than most clipboard managers, but it does not replace user-defined collections.

### 6. Paste behavior

The mature model exposes at least two distinct actions: paste into the active app and copy back to the system clipboard.

Plain-text paste is nearly universal among power-user products.

Raycast now lets the user choose among original representations such as rich text, plain text, RTF, or HTML.

Paste can paste multiple selected items and choose original or plain formatting.

LaunchBar separates Copy, Copy and Paste, and Paste without changing the current clipboard.

Keyboard Maestro maps normal, plain-text, and copy-only behavior to modifiers and number keys.

**Product lesson:** the panel must make the result of Return predictable.

Copy-only fallback should be a first-class state rather than a failure disguised as paste.

### 7. Sequential paste, queues, stacks, and merge

This is the largest repeated workflow pattern across otherwise different products.

Pastebot Stack lets users collect or select items and paste them in order with one repeated shortcut.

Raycast Paste Sequentially walks backward through recent history and resets after a configurable timeout or clipboard change.

CleanClip Paste Queue supports multiple orders, batch operations, paste-all, remove-after-paste, and optional keystrokes after each paste.

LaunchBar offers a LIFO paste-and-remove shortcut.

Ditto supports multi-selection and pasting several clips.

Keyboard Maestro merges or pastes selected entries with a chosen delimiter and can merge images horizontally or vertically.

Alfred ClipMerge appends a new copy to the previous clipboard after a double Command-C.

LaunchBar ClipMerge similarly combines text, rich text, files, or folders.

**Product lesson:** two different jobs are often conflated.

A **queue** fills several destination fields one at a time.

A **merge** combines several source items into one destination payload.

Stow should model them separately if it implements either.

### 8. Transformations

Transformations range from simple formatting to arbitrary code execution.

PastePal advertises more than 75 built-in transforms, including case, JSON, Base64, URL encoding, sorting, and hashing.

Pastebot lets users stack base filters into custom filters and preview the output live.

Copy 'Em, LaunchBar, Keyboard Maestro, CopyQ, ClipboardFusion, PasteBar, Pastery, and Deck all expose transform or macro concepts.

Common low-risk transforms are plain text, case conversion, whitespace cleanup, line sort/deduplicate, JSON formatting, URL encode/decode, and tracking-parameter removal.

High-risk transforms include arbitrary scripts, network requests, AI providers, shell commands, or invisible steganographic changes.

**Product lesson:** a curated local transform set can solve common problems without turning Stow into a code-execution host.

### 9. Preview, editing, and metadata

Rich preview is a meaningful retrieval tool, not decoration.

Paste, Pastebot, CleanClip, PasteNow, Pano, LaunchBar, Keyboard Maestro, and Stow all surface type-specific previews.

Pastebot and Keyboard Maestro show useful metadata such as source app, dimensions, size, word count, line count, and character count.

Several products allow text editing before paste.

Pastebot, PastePal, and PasteNow also support searchable notes or custom titles.

Deck adds a source anchor back to the original IDE file and line.

**Product lesson:** metadata should help recognition or action.

Technical metadata belongs in preview or detail, not on every compact card.

### 10. Sync and mobile access

Apple-focused products commonly use the user's private iCloud rather than a vendor clipboard server.

Paste, CleanClip, PastePal, and PasteNow provide Mac/iPhone/iPad continuity.

Pastebot documents iCloud sync among Macs and relies on Universal Clipboard for phone interoperability.

Paste also supports shared pinboards and collaboration.

Ditto supports direct encrypted sharing among trusted computers on a LAN.

Deck supports AES-GCM LAN sharing with verification.

Windows supports cloud clipboard sync tied to a Microsoft or work account.

SwiftKey can expose the latest cloud clip on Android for one hour.

**Product lesson:** sync reliability is part of data integrity.

App Store reviews repeatedly treat late, missing, or duplicated sync as worse than having no sync at all.

### 11. Mobile surfaces

An iOS clipboard manager cannot behave exactly like a continuously running macOS monitor.

Products work around this through custom keyboards, share extensions, widgets, Shortcuts, Live Activities, Dynamic Island, and explicit save-on-open behavior.

Paste and PastePal provide custom keyboards.

PastePal additionally documents iMessage, share/action extensions, widgets, Siri Shortcuts, Live Activity, and Control Center monitoring controls.

PasteNow and CleanClip provide keyboards and share-based capture.

**Product lesson:** mobile should optimize deliberate capture and deliberate reuse.

Pretending iOS provides unlimited reliable background clipboard monitoring creates misleading expectations.

### 12. Privacy and secret handling

Clipboard data frequently contains passwords, one-time codes, tokens, private messages, account numbers, and personal files.

The strongest baseline is to honor platform secret or concealed markers.

CopyQ documents exact secret markers for Linux, macOS, and Windows and ignores marked data before history or automatic commands process it.

Maccy follows password-manager clipboard clearing.

Raycast ignores passwords and transient data by default, encrypts local history, and supports disabled applications.

Alfred ignores popular password apps and concealed clipboard data and lets users add ignored apps.

Keyboard Maestro obscures password-like entries, avoids saving them to disk, and deletes them early from history.

Deck claims card-number and identity-number detection, sensitive-window detection, biometric locking, pause mode, and panel hiding during screen sharing.

GPaste supports password items and optional encrypted histories.

PasteBar supports application and collection locking.

**Product lesson:** local-first storage does not make indiscriminate capture safe.

Capture exclusion must happen before persistence, indexing, sync, previews, automation, or analytics.

### 13. Encryption and protected storage

Several products explicitly encrypt local history or protected subsets.

Raycast states that local clipboard history is encrypted.

CopyQ supports built-in all-tab encryption with a password and optional use of the operating-system credential store.

GPaste supports libsodium-backed encrypted histories and optional keyring storage.

Deck claims Touch ID gating and encryption for sharing.

PasteBar supports PIN-protected collections.

Paste, CleanClip, PastePal, and PasteNow emphasize device storage and private iCloud rather than a vendor server.

**Product lesson:** database encryption, interface locking, and sync encryption solve different threats.

A product should state which one it provides instead of using “secure” as an undifferentiated claim.

### 14. Deletion, cleanup, and recovery

Strong products expose individual delete, scoped delete, clear-all, and retention policies.

Raycast can delete by recent time window.

Windows clears device and cloud history while preserving pins.

CleanClip can preserve favorites and aliases during cleanup.

Pieces can delete by time range, modality, application, or combinations of those dimensions.

PasteNow and CopyQ support export/import or backup.

GPaste supports independent named-history backup and deletion.

**Product lesson:** users need both emergency privacy deletion and ordinary storage cleanup.

The two actions should not share ambiguous copy or silently remove protected items.

### 15. Automation and extensibility

Alfred workflows, LaunchBar actions, Keyboard Maestro macros, CopyQ scripting, ClipboardFusion macros, Pastebot CLI/Shortcuts, Raycast actions, Deck CLI/App Intents, and GPaste CLI all expose clipboard automation.

Pastebot provides a concrete local CLI helper.

CopyQ provides the deepest programmable model, including automatic commands, scripting APIs, command-line operations, and shared commands.

Pieces exports memory to AI clients through MCP.

Stow already has a bounded local agent CLI for add, search, get, and export.

**Product lesson:** Stow's existing CLI is a stronger strategic fit than embedded arbitrary scripting.

Future automation should extend typed, inspectable commands rather than execute user or clipboard code inside the app.

### 16. Collaboration

Paste explicitly supports shared pinboards and team plans.

Pieces moves from personal memory toward shared organizational knowledge.

Ditto and Deck focus on peer or LAN transfer rather than shared editing.

Most clipboard managers avoid collaboration because clipboard contents are highly sensitive and hard to permission safely.

**Product lesson:** collaboration is not table stakes for a personal clipboard manager.

For Stow, explicit sharing of curated collections could be coherent later, while automatic sharing of raw clipboard history would conflict with local-first safety.

### 17. AI and semantic retrieval

Deck offers semantic search and an optional AI clipboard assistant.

Raycast can send an item to AI Chat and offers Ask Clipboard for the latest item.

Pieces makes semantic and conversational retrieval the core product.

AI can summarize, translate, classify, transform, or retrieve by meaning.

It also creates new disclosure, consent, cost, data-transfer, hallucination, and latency problems.

**Product lesson:** semantic retrieval can be local and optional.

Cloud AI actions should never be the only way to find or transform a clipboard item.

## Competitive assessment of Stow

### Current strengths

Stow already covers several features that many clipboard managers split across separate products.

- It automatically captures new text, links, images, and regular files on macOS.
- It sends captured content into a real Inbox instead of treating all history as equally durable.
- Its quick panel is bottom-anchored, keyboard-first, resizable, and compactable.
- It has Clipboard, Inbox, and Pinned retrieval modes.
- It supports type, source-app, and date filtering.
- It has content-native text, code, image, link, and file presentation.
- It supports direct paste with an explicit copy-only permission fallback.
- It supports copy, open, preview, edit, archive, pin, drag, and lifecycle actions.
- Its Library owns durable management, multi-selection, Archive, Trash, Restore, and metadata work.
- It supports deliberate mobile capture through share extensions and Quick Add.
- It uses local storage and private Apple sync rather than exposing an HTTP clipboard service.
- It exposes a bounded same-user local CLI for coding agents without opening the data store directly.

### Verified gaps in the current implementation

Repository inspection found the following capture limitations in `Sources/StowApp/macOS/MacAppCoordinator.swift`.

- The monitor does not currently check macOS concealed clipboard markers before reading content.
- The settings do not currently expose per-app capture exclusions.
- Text capture reads `.string` and trims leading and trailing whitespace.
- Rich text, HTML, and alternative clipboard representations are not preserved.
- Image capture converts the current image to PNG or TIFF rather than retaining all original representations.
- File capture reads only the first URL and therefore does not preserve a multi-file clipboard as one item.
- The monitor does not classify colors, emails, or copied code automatically.
- The repository does not expose clipboard-history retention, item-size, or storage-threshold controls beyond the attachment limit.
- The product does not expose a paste queue, sequential paste, or multi-item merge workflow.
- The product does not expose OCR search, transforms, user collections, or reusable templates.
- The product does not expose backup/export of the full library as a user-facing recovery workflow.

## Recommended roadmap

### P0 — safety and fidelity

| Recommendation | User problem | Precedent | Cost and risk | Why now |
| --- | --- | --- | --- | --- |
| Honor concealed/secret clipboard markers before reading or persisting | Passwords and tokens can enter history silently | CopyQ, Raycast, Alfred, Maccy | Low-to-medium implementation risk, very high trust value | Safety baseline for any clipboard monitor |
| Add per-app exclusion rules with sensible password-manager defaults | Users cannot safely exclude banking, password, remote-desktop, or noisy apps | Paste, Raycast, Alfred, Pastebot, CopyQ | Requires source-app identity and clear precedence | Widely expected table stakes |
| Preserve original clipboard representations | Users lose rich formatting and cannot choose original versus plain paste | Raycast, Paste, GPaste | Schema and pasteboard complexity | Prevents irreversible data loss |
| Add duplicate coalescing with recopy-to-top behavior | Repeated copies and sync can flood the timeline | PastePal, PasteNow, CleanClip | Identity rules must respect files and edited items | Directly improves trust and retrieval speed |
| Add capture retention and size controls | Users need predictable privacy and storage behavior | Alfred, Raycast, CleanClip, Windows | Must distinguish history from durable Inbox items | Clarifies Stow's transient-to-durable model |

### P1 — high-value workflow capability

| Recommendation | User problem | Precedent | Cost and risk | Product fit |
| --- | --- | --- | --- | --- |
| Add an explicit sequential Paste Queue | Filling forms or moving structured data requires constant app switching | Pastebot, CleanClip, Raycast, LaunchBar | Medium state and focus complexity | Excellent fit for the existing quick panel |
| Add local OCR for captured images | Screenshots are impossible to find by remembered text | Raycast, CleanClip, Deck, Pastery | CPU, indexing, language, and storage cost | Strong local-first retrieval feature |
| Add user collections for promoted reusable content | Pinning does not scale to templates, prompts, code, and assets | Paste, PastePal, Pastebot, PasteNow, Alfred | New data model and navigation | Fits the durable Library better than the quick panel |
| Add multi-select merge with explicit delimiter | Users repeatedly combine copied fragments into lists or documents | Keyboard Maestro, LaunchBar, Alfred, CleanClip | Low-to-medium if limited to text | Useful without requiring arbitrary scripting |
| Add full-library export and restore | Local-first users need migration and disaster recovery | CopyQ, PasteNow, PasteBar, GPaste | High correctness and versioning responsibility | Necessary before users entrust long-lived libraries |

### P2 — differentiation after the foundation

| Recommendation | User problem | Precedent | Guardrail |
| --- | --- | --- | --- |
| Curated local text transforms | Common JSON, URL, case, and whitespace tasks cause context switching | PastePal, Pastebot, Deck, Pastery | No arbitrary code execution in the first version |
| Smart collections | Manually organizing a large durable library becomes repetitive | Pastebot, PasteNow, CleanClip, Deck | Rules must be inspectable and reversible |
| Optional local semantic search | Users remember meaning but not exact wording | Deck, Pieces | Exact search remains primary and results explain why they matched |
| Context-aware source anchors | Developers want to return to the file or app where code came from | Deck | Store only explicit, useful metadata and avoid passive screen capture |
| Time-scoped privacy deletion | Users need to erase what they copied during a sensitive session | Raycast, Pieces | Make scope and sync consequences explicit |
| Typed agent actions over the local CLI | Agents need safe transform, pin, archive, or collection operations | Pastebot, CopyQ, Pieces MCP | Extend bounded commands instead of adding a remote service |

## Ideas to avoid or defer

### Do not make raw history collaborative by default

Clipboard history contains too much accidental private data for automatic team sharing.

Curated collection sharing is safer but still requires a separate permission and revocation design.

### Do not add arbitrary script execution merely to match CopyQ

CopyQ's scripting power is valuable for its audience, but it expands Stow's attack surface and conflicts with the current bounded CLI design.

A curated transform library and typed CLI commands cover the most common workflows with less risk.

### Do not adopt continuous screen or audio capture

Pieces demonstrates the value of comprehensive work memory, but that is a different consent, permission, storage, battery, and trust model.

Clipboard and explicit share capture are much easier for users to understand and control.

### Do not put all advanced features in the quick panel

The quick panel's primary task is retrieval and immediate use.

Queue state and the current paste consequence may need to remain visible while transforms, collection editing, retention rules, backup, and security configuration belong in contextual menus, previews, Library, or Settings.

### Do not promise intelligent capture before fidelity is solved

Semantic search, AI classification, and automatic code detection cannot recover rich formats or secret data that were captured incorrectly.

Safety, exactness, and recovery should precede intelligence.

## Suggested product structure

The quick panel should remain optimized for search, selection, paste, copy, preview, and a visible queue state.

The Library should own promotion from transient history into durable collections, editing, bulk lifecycle, export, and recovery.

Settings should own capture exclusions, retention, size limits, sync, permissions, OCR, and privacy deletion.

Contextual item actions should own plain/original paste, merge, transform, pin, promote to collection, and delete.

The CLI should own typed local automation for add, search, get, export, lifecycle, and future collection or transform commands.

This separation preserves capability without turning the primary retrieval surface into a control panel.

## Highest-value validation questions

1. How often do current Stow users retrieve screenshots by text rather than by visual scanning?
2. Do users treat every automatic clipboard capture as Inbox work, or do they expect a separate transient history that expires automatically?
3. Which apps do users most need to exclude from monitoring?
4. Do users more often need FIFO form filling, LIFO transfer, or multi-item merge?
5. How often is original rich formatting required compared with plain text?
6. What should happen when a recopy matches an archived, pinned, edited, or manually titled item?
7. Should collections sync to mobile even when raw clipboard history does not?
8. Which local transforms cover most demand without user scripting?

## Sources

### Apple-focused standalone products

- Paste product page: https://pasteapp.io/
- Paste Power Search and comparison material: https://pasteapp.io/blog/best-clipboard-manager-for-mac
- CleanClip privacy: https://cleanclip.cc/docs/privacy
- CleanClip release notes: https://cleanclip.cc/docs/changelog
- CleanClip iOS product page: https://ios.cleanclip.cc/en
- PastePal App Store listing: https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680
- PastePal product page: https://indiegoodies.com/pastepal
- PasteNow product page: https://pastenow.app/
- PasteNow App Store listing: https://apps.apple.com/gb/app/pastenow-instant-clipboard/id1552536109
- Pastebot 3 product page: https://tapbots.com/pastebot/
- Copy 'Em App Store listing and reviews: https://apps.apple.com/us/app/copy-em-ultimate-clipboard/id876540291
- Maccy product page: https://maccy.app/
- Deck product explanation: https://deckclip.app/what-is-deck-clipboard-manager
- Deck first-party repository: https://github.com/yuzeguitarist/Deck
- Pastery product research: https://pasteryapp.com/blog/complete-guide-mac-clipboard-managers/

### Launcher and automation products

- Raycast Clipboard History product page: https://www.raycast.com/core-features/clipboard-history
- Raycast Clipboard History manual: https://manual.raycast.com/clipboard-history
- Alfred Clipboard History: https://www.alfredapp.com/help/features/clipboard/
- Alfred Snippets: https://www.alfredapp.com/help/features/snippets/
- LaunchBar Clipboard History: https://www.obdev.at/resources/launchbar/help/ClipboardHistory.html
- LaunchBar features: https://www.obdev.at/products/launchbar/features.html
- Keyboard Maestro Clipboard History Switcher: https://wiki.keyboardmaestro.com/manual/Clipboard_History_Switcher
- Keyboard Maestro clipboards: https://wiki.keyboardmaestro.com/Clipboards

### Windows, Linux, and cross-platform products

- CopyQ documentation: https://copyq.readthedocs.io/en/latest/
- CopyQ security: https://copyq.readthedocs.io/en/latest/security.html
- CopyQ encryption: https://copyq.readthedocs.io/en/latest/password-protection.html
- Ditto project page: https://sourceforge.net/projects/ditto-cp/
- Windows Clipboard: https://support.microsoft.com/en-us/windows/apps/using-the-clipboard
- SwiftKey Cloud Clipboard: https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-microsoft-swiftkey-keyboard-to-copy-and-paste-text-between-swiftkey-and-windows
- GPaste first-party repository: https://github.com/Keruspe/GPaste
- Pano first-party repository: https://github.com/oae/gnome-shell-pano
- PasteBar first-party repository: https://github.com/PasteBar/PasteBarApp
- ClipboardFusion first-party product and macro documentation: https://www.clipboardfusion.com/

### Operating-system and adjacent products

- macOS Tahoe Spotlight Clipboard: https://support.apple.com/guide/mac-help/search-your-clipboard-history-mchl40d5b86b/mac
- Pieces Long-Term Memory: https://docs.pieces.app/products/desktop/long-term-memory
- Pieces product page: https://pieces.app/

### Stow evidence

- Current behavior: `README.md`
- Clipboard monitor implementation: `Sources/StowApp/macOS/MacAppCoordinator.swift`
- Capture normalization and fidelity: `Packages/StowCore/Sources/StowCore/CaptureDraft.swift`
- Persistence and duplicate behavior: `Packages/StowCore/Sources/StowCore/StowRepository.swift`
- Current macOS redesign rationale: `docs/plans/2026-08-09_paste-inspired-macos-redesign-plan.md`
- Current v0.1 scope: `docs/release/v0.1-scope-audit.md`
