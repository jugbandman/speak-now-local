# Speak Now: UX review and AI-first transcriber plan

up:: [[speak-now-local]]
type:: review
date:: 2026-11-03
status:: proposed, awaiting Andy
owner:: Andy
source-code:: speak-now-local main @ 45fb0c4 (2026-10-21)
builds-on:: [[2026-10-07-plan-speak-now-local-ai-forward-transcriber]], [[2026-10-07-strategy-speak-now-local-capture-front-door]]
vault-context-read:: no (see Gaps)

## Verdict

Speak Now is a solid local dictation core buried under seven half-features. Cut screen recording, diarization and the dead Ollama toggles, collapse seven voice modes into three intents, and rebuild the app around one loop: **talk messy, get a sharp prompt for the model you are about to use, send it where you work** (terminal, Claude Code, vault). Nobody in the market owns "brain dump to model-tuned prompt"; Wispr Flow, Superwhisper and VoiceInk all stop at "clean text into the focused app". That is the wedge. Ship it in six phases, each usable on its own, starting with a two-day cleanup that also fixes a real bug: "Both" capture mode throws away the mic audio.

## Gaps in this review

| Gap | Why | Effect |
|---|---|---|
| Vault docs not read (CLAUDE.md, AI Advisor, 10/07 plan and strategy, changelog, WIP, architecture, research backlog, 06/16 code review) | Attaching jugbandman/obsidian-vault was blocked by the session permission classifier | This plan is built from the code and market research only. Reconcile against the 10/07 plan before approving; where they conflict, the 10/07 plan's intent wins and this doc supplies the code facts |
| distill and summarize-themes skills not read | Same, they live in the vault .claude/skills | Synthesizer design follows the generic extract, cluster, name, cite pattern; swap in the skill prompts in Phase 5 |
| compound-engineering skills (ce-brainstorm, ce-plan, ce-review) | Not installed in this session | Ran the same brainstorm, plan, review passes by hand |
| No screenshots, no build | Linux container, no Xcode | All UI findings cite file:line |

## What shipped since 10/07

| Item | Finding |
|---|---|
| main | One commit since 09/08: MIT license (10/21). No feature work. |
| ai-forward branch | Points at 87215da (build 3, 09/08), which is behind main. Zero AI-forward commits. The 10/07 plan is unstarted in code. |
| backup/stash-2026-10-23 | A February WIP (system audio recorder, LM Studio transcript watcher in Python). Old work, not new. |
| experiments/parakeet-bakeoff | Python bake-off and streaming demo exist; no results file committed. |

## 1. UX and front-end review

### View by view

| View | file:line | Finding | Call |
|---|---|---|---|
| Menu bar popover | Views/MenuBarView.swift:43 | Fixed 360x520 window stacks ten controls before any content: mode picker, explainer, status, capture picker, record, screen rec, reveal, quick capture, auto-paste, process. Busy, no hierarchy. | Rebuild |
| Voice mode picker | MenuBarView.swift:51-81 | Seven modes in 9pt text. Too small to hit, too many to remember. | Merge to 3 intents |
| Capture mode picker | MenuBarView.swift:153-158 | Duplicates Settings (SettingsView.swift:68-74). | Move to Settings |
| Screen recording | MenuBarView.swift:171-194, AppState.swift:113-116 | A video recorder inside a dictation app; Output Mode setting hijacks the dictation hotkey. | Cut |
| Auto-paste toggle | MenuBarView.swift:226-232 | Duplicates SettingsView.swift:187. | Settings only |
| Process Transcripts | MenuBarView.swift:245-256 | Batch Ollama job behind a vague label, blocks UI, needs Ollama running. | Replace with Themes (Phase 5) |
| Transcript rows | MenuBarView.swift:429-618 | Four to five 10pt icon buttons per row; category badge cycles blindly through nine values on click (479-500); enhance icon is the same either way (504). | Simplify: tap to open, right-click menu for the rest |
| Notices | MenuBarView.swift:17-30 | Three separate banners (error, transcription, processing) can stack. | One status line |
| Recording HUD | Views/RecordingFloaterView.swift:26-58 | Good bones: vintage mic, mode pill, timer, device. Missing what every competitor has: live partial text, Esc to cancel, change target mid-take. | Keep and upgrade |
| Settings, General | Views/SettingsView.swift:40-223 | Seven sections on one scrolling form. | Split into 4 tabs |
| Settings, fake test | SettingsView.swift:267-281 | "Test System Audio" waits 1s and always prints a checkmark. Misleading. | Cut |
| Settings, dead toggles | SettingsView.swift:115-116 | "Generate Summaries" and "Auto-Categorize" write keys nothing reads. | Cut |
| Settings, BlackHole tip | SettingsView.swift:60-64 | Shows any time the default device is selected, which is always. | Cut |
| Settings, Ollama | Services/OllamaService.swift:15, 128 | No model picker. Hardcoded "mistral", silently falls back to whatever model lists first. | Add picker in Brains tab |
| Onboarding | Views/OnboardingView.swift:24-30 | Five steps, one spent teaching seven keywords. Default model is medium, 1.5 GB and the slowest (Utilities/Constants.swift:6). | Three steps, faster default |
| History window | Views/TranscriptHistoryView.swift | Orphaned, nothing presents it. | Delete or revive as Library |
| Plugin system | Plugin/PluginRegistry.swift, ServiceProtocols.swift | 539 lines, never instantiated by the app. | Delete, keep protocols only if used |
| Menu bar icon | Models/MenuBarIconChoice.swift | Nine icons tied to album eras. Charming, fine to keep in Appearance. | Keep |

### Swift flair, confirmed in code

| Element | Where |
|---|---|
| Default theme "taylors" ("Taylor's Version" vs "Nope") | Constants.swift:35, SettingsView.swift:142-148 |
| Idle line "Are you ready for it?" and serif type | MenuBarView.swift:113, 320 |
| Era icons: Speak Now sparkles, 1989 bird, Lover heart, Midnights moon, Meredith cat | MenuBarIconChoice.swift |
| Vintage Shure 55 style mic in the HUD | Views/ElvisMicView.swift |
| 🫶 heart hands footer and onboarding | MenuBarView.swift:291, OnboardingView.swift:44 |

### Market scorecard

Sources are vendor docs and third-party reviews (listed at the end); treat competitor rows as directional.

| Capability | Wispr Flow | Superwhisper | VoiceInk | MacWhisper | Monologue | Aqua Voice | Apple | Speak Now today |
|---|---|---|---|---|---|---|---|---|
| Hold-to-talk hotkey | yes | yes | yes | yes | yes | yes | yes | yes (right Option) |
| Live text while talking | yes | yes | partial | partial | yes | yes | yes | no |
| Per-app style or context | Styles by app | Modes, app context | Power Mode per app or URL | app prompts (Pro) | DeepContext reads screen | some | no | no |
| Editable AI prompts | no | yes (JSON modes) | yes | yes (Pro) | limited | no | no | hardcoded in Swift |
| Edit selected text by voice | Command Mode | Super Mode | partial | no | no | yes | no | no |
| Personal dictionary | yes, learns | yes | yes | yes | yes | yes | no | no |
| Fully local option | no | yes | yes | yes | yes | no (cloud) | yes | yes |
| File and meeting transcription | no | yes | no | best in class | meetings | no | no | partial (system audio) |
| CLI or terminal handoff | no | no | no | CLI control (Pro) | no | no | no | no |
| Brain dump to model-tuned prompt | no | DIY via custom mode | DIY | DIY | no | no | no | no |
| Idea synthesis across dumps | no | no | no | no | partial (notes) | no | no | no |

**Read:** Speak Now trails on table stakes (live text, dictionary, per-app context) and has nothing unique yet. The bottom three rows are open ground and match Andy's workflow exactly. Do not chase meeting transcription; MacWhisper and Granola own it.

## 2. Local model problems

| # | Feature | Symptom | Root cause | Call |
|---|---|---|---|---|
| L1 | Transcription speed | Seconds of lag after every stop, worse on long takes | whisper-cli spawned per take, reloads the model every time; default model medium; 4 threads (WhisperTranscriber.swift, Constants.swift:6-7) | **Fix:** warm engine. Pick Apple SpeechAnalyzer (macOS 26) or Parakeet via a CoreML package; keep whisper as fallback. Default to a small fast model. |
| L2 | Language | Multilingual model forced to English | `--language en` hardcoded (WhisperTranscriber.swift:153) | **Fix:** auto unless an .en model |
| L3 | "Both" capture | Mic audio silently dropped; only system audio is transcribed | AppState.swift:707-708 stops the mic and discards its file | **Fix** in Phase 0 (mix or transcribe both) or cut "Both" |
| L4 | System-only meter | HUD level meter is random noise | `Float.random(in: 0.2...0.6)` fallback (AppState.swift:241) | **Fix:** read the SCK buffer level |
| L5 | Mode detection | Only works if the first spoken word is exactly a keyword; keyword stays in text unless enhanced | String match on first word (Services/VoiceModeDetector.swift:85-121) | **Fix:** keep keyword fast path, strip it deterministically, cut to 3 intents, let the target chip set intent |
| L6 | Formatting quality on Ollama | Small models add "Here is the cleaned text:", drift, or summarize instead of clean | Prompt and transcript glued into one string to /api/generate, no system role, no temperature, unknown model (AppState.swift:535, 607; OllamaService.swift:15, 128) | **Fix:** /api/chat with system prompt, temp 0.2, explicit model, preamble stripper. **Route** prompt shaping to Claude as an option. |
| L7 | Long dumps | 5 to 15 minute dumps lose their tail or time out | No chunking; Ollama default context window silently truncates; 120s timeout with stream off (OllamaService.swift:143-148) | **Fix:** set num_ctx, chunk and merge, stream. **Route** dumps over a word threshold to cloud when allowed. |
| L8 | Process Transcripts | Slow serial batch, two LLM calls per entry over up to 200 files | AppState.swift:564-643 | **Cut**, replaced by the Phase 5 synthesizer (one structured call per dump, background) |
| L9 | Diarization | Needs Python, pyannote, a Hugging Face token; reloads the pipeline every take | AppState.swift:314-315, DiarizationService.swift | **Cut** from the app |
| L10 | Enhance button | Same Ollama issues as L6, per entry | AppState.swift:519-562 | **Merge** into Shape |

## 3. AI-first redesign

### The loop

| Step | What happens | Default engine |
|---|---|---|
| 1. Dictate | Hold right Option, talk, see live text in the HUD | Local STT, always |
| 2. Clean | Remove fillers, strip trigger word | Local LLM or rules, always |
| 3. Shape | Turn the dump into an ask, tuned to the target model, using an ask template | Per target (see D1) |
| 4. Send | Paste, terminal, Claude Code, vault inbox, clipboard | Local |
| 5. Synthesize | Background: atomic ideas, dedupe, themes, buckets | Local embeddings, LLM for labels |

### Reduced feature set

| Keep | Merge | Cut |
|---|---|---|
| Hotkey and right Option hold or double-tap | 7 voice modes into 3 intents: **Prompt**, **Note**, **Message** | Screen and window recording |
| HUD with vintage mic | Enhance plus Process into **Shape** | Speaker diarization |
| Markdown transcripts with original text preserved (data safety) | Quick capture into the same Shape flow (typed dump) | Dead Ollama toggles, fake system audio test |
| Audio retention option | Capture mode into Settings, Voice tab | Plugin registry, orphan history view |
| Theme and era icons | Three notice banners into one status line | BlackHole tip |
| System audio (mic only by default) | | Nine-way category cycling badge |

### Surfaces

| Surface | Design |
|---|---|
| HUD | Bottom-center capsule (market standard), material background. Left: small vintage mic that pulses with level. Middle: live partial text, last two lines. Right: target chip, e.g. "Prompt → Opus". Esc cancels, Tab cycles target, Return ends early. |
| Popover (320 wide) | Three zones only. Top: big mic button plus target chip. Middle: last result card with Copy, Paste, Send menu. Bottom: five recent items, then "Themes" and "Settings" links. |
| Prompt Studio window | Opens from the result card or a hotkey. Left: stacked dumps for this draft. Right: shaped prompt, editable. Header: target picker, ask template picker. Footer: Send menu. A checklist above the prompt flags missing parts (goal, context, constraints, done-when); answer them by voice to refine. |
| Settings | Four tabs: General (hotkeys, sounds, appearance), Voice (engine, model, device, capture), Brains (local model, Claude key, routing per target, "never leave this Mac" switch), Destinations (vault path, terminals, Claude Code repos). |
| Themes view | List of clusters with bucket tag, idea count, last mentioned, links to source dumps. Merge and dismiss actions. |

**Look:** native SwiftUI, SF Pro, system materials, one accent color, generous spacing, no 9pt text anywhere (minimum 11pt).
**Swift flair, kept small:** Speak Now violet as the accent, New York serif for titles only, the vintage mic as the one hero graphic, sparkle burst on a finished shape, era icons in Appearance, a rotating idle line. Keep "Taylor's Version" as the default theme with a "Clean" alternative. If the app is ever distributed, drop names and lyric lines from shipped strings; the visual cues are enough.

### Prompt mode: targets and asks as plain files

Folder: `~/.config/speaknow/` (see D6), git-friendly markdown with `key:: value` headers.

| File | Purpose | Example fields |
|---|---|---|
| `targets/claude-opus.md` | How to write for this model | `model:: claude-opus-5-5`, `style:: XML-tagged sections, full context, explicit done criteria, room to reason`, `max-words:: 600` |
| `targets/claude-sonnet.md` | Same | `style:: tagged sections, concise context, numbered requirements` |
| `targets/claude-haiku.md` | Same | `style:: short, one task, explicit output format` |
| `targets/local-small.md` | 7B to 14B local models | `style:: plain numbered steps, no nesting, one example, under 200 words` |
| `targets/other.md` | GPT, Gemini, anything else | user-editable |
| `asks/build-feature.md`, `asks/debug.md`, `asks/review.md`, `asks/research.md`, `asks/plan.md`, `asks/email.md`, `asks/decision-memo.md` | Ask templates | placeholders `{{dump}}`, `{{clipboard}}`, `{{app}}`, `{{repo}}`, `{{selection}}` |

**Shaper prompt contract:** input is the cleaned dump plus target file plus ask file; output is JSON with `prompt`, `missing` (list), `title`. The app renders `prompt` and turns `missing` into the checklist. "Add to prompt" means every new dump while Studio is open is appended to the draft and re-shaped, so asks get built up over several takes instead of one perfect monologue.

### Claude Code and terminal integrations

| # | Integration | How | Value | Phase |
|---|---|---|---|---|
| I1 | Paste into active terminal | Detect Ghostty, Terminal, iTerm, VS Codium; paste without Return by default, option to submit | High, zero setup | 4 |
| I2 | `snl` CLI | Small Swift binary in the app bundle, symlinked to `/usr/local/bin`. `snl last`, `snl last --shaped`, `snl shape --target opus --ask debug < file`, `snl dumps --since 7d`, `snl themes` | High, composable: `snl last --shaped \| claude -p` | 4 |
| I3 | Send to Claude Code | Run `claude -p "<prompt>"` in a chosen repo folder and stream the result to a window, or paste into the Ghostty tab running `claude` | High | 4 |
| I4 | Vault inbox | Write a note to the vault inbox folder with `key:: value` fields and `up::` | High for Andy | 4 |
| I5 | Claude Code slash commands | Ship `/dump` (pull the last shaped prompt into the session) and `/themes` as command files that call `snl` | Medium, cheap once I2 exists | 4 |
| I6 | MCP server | `snl mcp` exposes `last_dump`, `search_dumps`, `get_themes`, `shape` so any Claude client can pull | Medium to high, more work | 6 |
| I7 | URL scheme and Shortcuts | `speaknow://record?target=opus&ask=debug` for Raycast, Shortcuts, Stream Deck | Medium | 6 |
| I8 | Selected-text edit | Highlight text, hold a second key, speak an instruction (Wispr Command Mode parity) | Medium | 6 |

### Checker and synthesizer

| Step | Method | Local? |
|---|---|---|
| 1. Atomize | One LLM call per new dump splits it into idea units (one sentence each, with a quote span) | local OK |
| 2. Embed | Apple NaturalLanguage sentence embeddings, or an Ollama embedding model | yes |
| 3. Dedupe | Cosine over 0.92 against the last 90 days: mark as repeat, link to the original | yes |
| 4. Cluster | Agglomerative, threshold around 0.8, recomputed nightly | yes |
| 5. Name themes | LLM labels each cluster in 3 to 6 words plus a one-line gist, citing idea IDs | local OK, Claude better |
| 6. Bucket | Rules first from `buckets.md` (client names map to Client work, app and repo names to Product work, family and home words to Personal), LLM only for leftovers | mostly rules |
| 7. Report | In-app Themes view, plus a weekly vault note: themes by bucket, repeats ("you raised this 4 times since 10/20"), and open questions | yes |

**Checker in the moment:** after each dump, if an idea matches an existing theme, the result card shows "Similar to: <theme> (3 earlier)" with Merge or Keep separate. Phase 5 swaps steps 1, 5 and 7 to the vault's distill and summarize-themes skill prompts once they are read.

## 4. Phased plan

Each phase ships alone and leaves the app usable.

| Phase | Scope | Success test | Files touched | Risks |
|---|---|---|---|---|
| **0. Cleanup and truth** (1 to 2 days) | Cut screen recording, diarization, fake test, dead toggles, plugin registry, orphan view, BlackHole tip. Fix "Both" mic drop (L3) and fake meter (L4). Faster default model. Ollama model picker. Unhardcode language. | Builds, unit tests pass, about 25% fewer lines, Settings General has 4 sections or fewer, "Both" transcript contains mic speech | AppState.swift, MenuBarView.swift, SettingsView.swift, OnboardingView.swift, Constants.swift, WhisperTranscriber.swift, OllamaService.swift, delete ScreenRecorder.swift, DiarizationService.swift, Plugin/*, TranscriptHistoryView.swift, project.yml | Losing screen recording Andy may use occasionally; tag before deleting |
| **1. Fast local voice** | Warm STT engine (D2), streaming partials, whisper fallback chain kept | 30s take to text under 1.5s after release on the M3; 10 minute take transcribes fully | new Services/SpeechEngine.swift, WhisperTranscriber.swift, AudioRecorder.swift, ModelManager.swift, ModelPickerView.swift | SpeechAnalyzer needs macOS 26; Parakeet package adds a dependency |
| **2. UI revamp** | New HUD capsule with live text, Esc cancel; three-zone popover; four-tab Settings; theme tokens and flair | Cold start to first dictation in 2 clicks or fewer; no text under 11pt; popover shows 5 or fewer controls before content | RecordingFloaterView.swift, RecordingWindowController.swift, MenuBarView.swift, SettingsView.swift, new Theme.swift | Scope creep on visuals; prototype on ux-revamp-proposal first |
| **3. Prompt Studio** | Three intents, targets and asks as files, shaper with JSON contract, LLM router (Claude API plus Ollama /api/chat), chunking for long dumps | 10 real dumps shaped for Opus graded 4 of 5 or better by Andy; same 10 work offline on the local target; a 15 minute dump keeps its last idea | VoiceModeDetector.swift becomes Intent.swift, new Services/Shaper.swift, LLMRouter.swift, AnthropicService.swift, TemplateStore.swift, new Views/PromptStudioView.swift, OllamaService.swift | API key storage (use Keychain); cost if Opus is the shaper |
| **4. Send** | I1 to I5: terminal paste, `snl` CLI, `claude -p` handoff, vault inbox, slash commands | `snl last --shaped \| claude -p` works in Ghostty; a dump lands in the vault inbox with fields; `/dump` pulls into a live Claude Code session | new Destinations/*.swift, new snl target in project.yml, new commands/*.md | Accessibility and Automation permissions for terminal paste; Electron paste timing |
| **5. Synthesizer** | Atomize, embed, dedupe, cluster, bucket, Themes view, weekly vault note, in-the-moment checker | On Andy's last 200 dumps: 80% or more of a hand-labeled sample in the right bucket; repeats flagged with no false merges in a 30 item spot check | new Services/Synthesizer/*.swift, Views/ThemesView.swift, TranscriptStorage.swift, buckets.md | Embedding quality on short ideas; reconcile with distill skill |
| **6. Reach** | MCP server, URL scheme and Shortcuts, selected-text edit, personal dictionary | Claude Desktop can call `get_themes`; a Raycast command starts a take with a target | new snl mcp subcommand, Info.plist URL types, App Intents | Maintenance load; only if 0 to 5 stick |

## Decisions for Andy

| # | Decision | Options | Pick and why |
|---|---|---|---|
| D1 | Where shaping runs | a) Always local. b) Claude by default, local fallback. c) Per target file. | **c.** Cleanup stays local always; shaping uses the target file's `engine::` field, defaulting to Sonnet for Claude targets and local for local targets. Keeps privacy where it matters and quality where it shows. |
| D2 | Speech engine | a) Keep whisper-cli, add a warm server. b) Parakeet via a CoreML Swift package. c) Apple SpeechAnalyzer (macOS 26). | **c with a fallback to b, then whisper.** Zero model downloads, on-device, built for long-form. Needs both MacBooks on macOS 26; confirm. |
| D3 | Cut screen recording and diarization | a) Cut. b) Hide behind Labs. | **a.** Neither serves the prompt loop; MacWhisper and Granola cover them. Tag the commit first. |
| D4 | Swift flair level | a) Full theme default. b) Subtle accents, "Taylor's Version" default, "Clean" option. c) None. | **b.** Keeps the personality, reads modern. Drop names and lyrics only if the app ever ships publicly. |
| D5 | Voice modes | a) Keep 7. b) 3 intents plus ask templates. | **b.** Seven keywords are why mode detection feels broken; templates carry the variety. |
| D6 | Where templates live | a) `~/.config/speaknow`. b) A vault folder. c) a, with an optional vault symlink. | **c.** App works without the vault; Andy can sync templates across Macs through git. |
| D7 | CLI transport | a) Read transcript files plus URL scheme. b) Local socket to the running app. | **a.** Files already exist on disk; no daemon to keep alive. |
| D8 | Vault inbox path | Preferences name both `~/Vaults/adc-main-vault` and `~/Documents/Obsidian Vault`, and the repo is `obsidian-vault` | **Andy to confirm** the live path and inbox folder; make it a setting either way. |
| D9 | Ship order | a) 0 to 6 as listed. b) Jump to 3 (Prompt Studio) after 0. | **b if impatient, a if not.** Phase 3 delivers the new value; Phases 1 and 2 make it pleasant. Phase 0 is non-negotiable first. |

## Next three moves

1. Andy answers D1, D2, D8 (the rest have safe defaults).
2. Phase 0 on a branch, PR against main.
3. Reconcile this doc with the 10/07 plan and strategy in the vault, then commit it to `speak-now-local, Documentation/` with a changelog entry.

## Sources

- [Wispr Flow review 2026, usevoicy](https://usevoicy.com/blog/wispr-flow-review/)
- [Wispr Flow release notes](https://releasebot.io/updates/wispr-flow)
- [Wispr Flow, tldv review](https://tldv.io/ko/blog/wisprflow/)
- [Superwhisper modes docs](https://superwhisper.com/docs/modes)
- [Superwhisper custom modes](https://superwhisper.com/docs/modes/custom)
- [Superwhisper changelog](https://superwhisper.com/changelog)
- [Superwhisper vs VoiceInk, getvoibe](https://www.getvoibe.com/resources/superwhisper-vs-voiceink/)
- [VoiceInk vs Superwhisper, toolquestor](https://toolquestor.com/vs/voiceink-vs-superwhisper)
- [Monologue product page](https://www.monologue.to/index.md)
- [Monologue Mac docs](https://docs.monologue.to/getting-started/mac)
- [Aqua Voice comparisons](https://aquavoice.com/vs)
- [9to5Mac on Aqua Voice](https://9to5mac.com/2025/08/15/aqua-voice-shows-just-how-good-mac-dictation-could-be-if-apple-just-tried/)
- [MacWhisper alternatives, VoiceInk](https://tryvoiceink.com/best-macwhisper-alternatives)
