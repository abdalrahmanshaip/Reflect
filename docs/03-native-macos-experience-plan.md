# Native macOS experience implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for authorized native execution, or `superpowers:subagent-driven-development` when subagent execution is explicitly authorized. Execute task by task using checkbox tracking. Layouts and component names are proposals for review. Do not commit automatically.

**Goal:** Give Reflect a coherent, elegant desktop experience whose interactions are as dependable as its appearance.\
**Architecture:** Keep SwiftUI scenes and native navigation; centralize route/window state and commands. Use AppKit narrowly for a demonstrated platform gap, with availability handling for macOS 13.\
**Tech stack:** SwiftUI, AppKit, Foundation, SF Symbols, SwiftPM.\
**Spec:** [01 — Product vision and requirements](01-product-vision-and-requirements.md), especially sections 4–7.

## Global constraints

Spec section 9 applies in full. All screenshots use a dedicated synthetic fixture and temporary home/store/secrets. No deployment-floor increase, custom dependency, external asset download, or real history read is implied by this plan.

## Review focus

1. Settings must open from both the footer and application menu while discovery is slow.
2. Switching routes or windows must preserve unsent text and conversation position.
3. The entire daily/chat workflow must be possible using keyboard and VoiceOver.
4. Narrow windows, large text, Dark Mode, and long responses must remain usable.
5. Visible loading, canceled, failed, unsaved, and offline states must match actual operations.

## 1. Taste references and design direction

The user explicitly likes WhatsApp on Mac, Cursor, and Dia. Borrow qualities rather than copying layouts or branding:

| Reference | Quality to study | Reflect application |
| --- | --- | --- |
| WhatsApp | Familiar conversation structure, readable messages, straightforward navigation. | A conversational workspace that needs little explanation. |
| Cursor | A capable workspace with context nearby and actions that have visible effects. | Follow-up questions, remembered context, clear agent/run controls, useful keyboard access. |
| Dia | Calm proportions, restrained chrome, a strong visual identity. | Quiet surfaces, deliberate spacing, and a content area that feels owned by Reflect. |

The target is warm, precise, and capable. Avoid a decorative dashboard of counts, oversized empty cards, excessive status prose, or glass layered over every surface. Elegance must survive ordinary error and loading states.

The earlier journal-like Today design and Design A artifacts are reference material. The latest conversation establishes a new primary workflow; implementing an old mockup unchanged would not satisfy it.

## 2. Proposed information architecture

### Main window

- A resizable native sidebar with conversations and a compact entry into personal progress.
- A primary conversation area with readable messages and a persistent composer.
- A compact daily-question surface that appears when relevant and opens one focused answer experience.
- Secondary Sources and diagnostic access; these do not dominate navigation or home content.
- A footer Settings entry that opens the same native Settings experience as the application menu.

Exact sidebar labels, whether Progress is a separate destination or contextual surface, and the visual placement of the daily question remain review choices. Do not add destinations solely to preserve existing Today/This Week/Patterns/All Records screens.

### Conversation anatomy

Use a concise header with conversation title and context scope; messages; a clear composer; send/stop state; and a compact agent/status control when relevant. Explain the current context in human language such as an approved date range, not a wall of event IDs.

Supporting context opens on request and returns to the conversation without losing text or scroll position. Messages with unsupported conclusions show uncertainty in the answer itself; a hidden diagnostic panel cannot substitute for honest language.

### First use

Explain the core benefit in a few sentences. Let the user connect an approved source and configure an agent without asking for a permanent job title or market. Existing local notes/reflections remain usable while AI is disabled.

If no evidence is available, say what is missing and offer an explicit import or user explanation. Do not seed convincing fictional progress in the real app.

## 3. Visual system

Define shared roles rather than scattered one-off styling:

- System typography for controls and navigation; a deliberate reading hierarchy for conversation content.
- Native semantic colors and one Reflect accent with verified contrast in Light and Dark modes.
- Consistent spacing, corner treatments, separator usage, icon weight, and control height.
- Distinct hierarchy for user text, generated responses, daily questions, and operational status.
- A comfortable reading width that adapts to the window; large windows should not become a tiny centered note, and narrow windows should not clip controls.
- Restrained animation for state transitions; respect Reduce Motion and Reduce Transparency.

Do not choose a font, palette, animation system, or fixed mockup solely because it is fashionable. Show synthetic Light/Dark concepts for the actual conversation and daily-question flow before locking the composition.

## 4. Native behavior contract

### Settings

Add a SwiftUI `Settings` scene. Both sidebar and Command-comma must reach the same settings state. Use the current SDK's documented opening API with appropriate availability checks; modern Settings-opening APIs require a tested macOS 13 fallback. Keep any AppKit bridge in one focused file rather than dispatching guessed selectors throughout views.

Settings should contain understandable source/privacy, agent/model, appearance, and daily-reminder preferences. Do not require legacy endpoint/price controls for a CLI-based agent unless a separate supported API provider is introduced.

The window appears before agent discovery finishes. Show checking status, retain the last-known result with its time, and allow explicit refresh. A timeout must not freeze navigation or trigger hidden analysis.

### Menus and shortcuts

Proposed command map, subject to system shortcut conflict review:

| Command | Proposed access | Behavior |
| --- | --- | --- |
| New conversation | File menu, Command-N | Creates a local empty conversation and focuses its composer. |
| Find in current conversation | Edit menu, Command-F | Searches loaded conversation content without a new AI request. |
| Settings | Application menu, Command-comma | Opens the native Settings scene. |
| Import approved sources | File menu | Uses the existing explicit import boundary, with per-source outcomes. |
| Daily reflection | View menu | Opens the existing day's primary question/draft. |
| Toggle sidebar | View menu | Uses native sidebar behavior and preserves selected conversation. |
| Stop response | Visible stop button and context-appropriate Escape handling | Cancels the active run without deleting submitted messages. |
| About Reflect | Application menu | Shows version/build information with standard dismissal. |

Do not install a global Escape handler that breaks sheet dismissal or editing. Text submission behavior must account for multiline composition and input-method composition; propose Return to send and Shift-Return for a newline only after verifying accessibility and IME behavior. A visible Send button remains available.

### Pointer and interaction feedback

Apple's normal macOS arrow is appropriate for ordinary controls and sidebar rows. A pointing hand is appropriate for links; custom clickable surfaces need context-appropriate treatment. Audit Today/This Week/Patterns/Settings and their replacements for semantic roles and activation instead of enforcing a hand everywhere.

Selected, hovered, pressed, focused, disabled, and loading states must be distinguishable without relying on color alone. Do not maintain a cursor push/pop stack with unbalanced transitions. Test the cursor and activation on actual rendered controls; a Boolean helper test cannot establish them.

### Windows, focus, and restoration

Use standard titlebar controls, dragging, minimum size, resizable panes, and full-screen behavior. Preserve selected conversation, draft, relevant scroll anchor, and sidebar state across navigation and relaunch. Define what happens when a second window is requested before enabling multiple windows; do not assume all mutable state should be duplicated.

Settings can open independently. Closing its window must not clear the main conversation or relaunch the application. Focus returns to a useful location after dismissing a sheet, stopping a run, or opening supporting context.

### Accessibility

Prefer native Button/List/TextField semantics. Expose message speaker and meaningful grouping; label icon-only controls; announce completed/failed actions without reading every streamed token. Use keyboard traversal, visible focus, sufficient contrast, and long-content scrolling. Test a complete task with VoiceOver rather than only testing generated labels.

## 5. Files and boundaries

Modify `Sources/ReflectAppMain/AppMain.swift` for scenes and commands, and `Sources/ReflectLib/Views/ContentView.swift` for the new shell. Adapt `ReflectSidebarView.swift`, `SettingsView.swift`, `AboutView.swift`, and shared `Components.swift` where appropriate.

Proposed new files:

- `Models/AppRoute.swift`: route identity separate from business state.
- `Stores/NavigationStore.swift`: selected conversation, view state, and restoration.
- `Views/ConversationView.swift` and `Views/ConversationComposer.swift`: message presentation and composition.
- `Views/DailyQuestionView.swift`: one question and saved/unsaved answer state.
- `Support/SettingsWindowBridge.swift`: macOS availability fallback only.
- `Support/ReflectCommands.swift`: menu definitions and command routing.
- `Tests/ReflectTestRunner/NavigationRestorationTests.swift` and `SettingsDiscoveryTests.swift`: state and asynchronous behavior.
- Existing `Tests/ReflectUIFixtureMain/AppMain.swift`: dedicated synthetic scenarios.

Domain ownership remains in plans 05–07; the shell must not implement import parsing, assessment generation, or provider invocation itself.

## 6. Tasks

### Task N1: Lock the primary flow with synthetic design references

- [ ] Produce conversation, daily question, no-evidence, and failed-run concepts using fictional content.
- [ ] Compare Light/Dark and wide/narrow compositions against the user-valued reference qualities.
- [ ] Record the selected labels, typography roles, minimum window size, and state hierarchy as implementation decisions.
- [ ] Review the entire journey rather than approving a single attractive static home screen.

### Task N2: Implement native Settings and command routing

**Interfaces:** Introduce `SettingsOpening.openSettings()` at the UI boundary; both footer and command route through it. Its implementation owns version branching. `NavigationStore` exposes `selectConversation(id: UUID)` and preserves route state.

- [ ] Add route/restoration tests and slow-discovery tests before changing scene wiring.
- [ ] Implement the Settings scene and minimal opening bridge; verify both entry points on supported systems.
- [ ] Route commands through store actions; commands must be disabled when their operation is unavailable.
- [ ] Run `swift run reflect-test-runner` and `swift build --product reflect-ui-fixture`.
- [ ] Click the footer, use Command-comma, close Settings, and repeat while fake discovery is delayed.

### Task N3: Build the conversation shell with durable composition

- [ ] Test `switchConversationRetainsDraft`, `restorationKeepsSelection`, and `dismissContextRestoresComposerFocus` with synthetic state.
- [ ] Implement the composer and transcript against `ConversationStore` from plan 06; connect stop/retry/error states to actual operations.
- [ ] Integrate the daily surface from plan 07 without making its draft disposable route state.
- [ ] Preserve migration access to older reports and answers; no legacy content is deleted merely because navigation changes.
- [ ] Verify long messages, code blocks, paste, multiline text, IME composition, and scrolling.

### Task N4: Prove desktop polish

- [ ] Complete keyboard-only new-conversation, send, stop, Settings, reflection, and recovery journeys.
- [ ] Complete equivalent VoiceOver tasks with synthetic content and record actual results.
- [ ] Validate 760- and 1280-point-wide reference layouts as proposed comparison sizes, resizing beyond them, Dark/Light, larger text, Reduce Motion, and Reduce Transparency.
- [ ] Verify menus, titlebar dragging, focus, sidebar collapse, full-screen, window closing, and relaunch restoration.
- [ ] Distinguish unsupported OS checks from completed checks; do not claim macOS 13 runtime proof from a newer host.

## 7. Acceptance

The product must feel capable when empty, loading, offline, or recovering, not only in a polished synthetic success screenshot. Settings works through real UI actions; drafts remain intact; the normal pointer is accompanied by clear interaction feedback; and conversation/reflection are easier to reach than diagnostic records.

## 8. Research references

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) — desktop conventions and task-centered design.
- [Apple pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices) — normal pointer meanings.
- [Apple Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings) and [SettingsLink documentation](https://developer.apple.com/documentation/swiftui/settingslink) — scene and settings entry patterns; verify API availability before implementation.
- [SwiftUI AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration) — narrow native bridges.

These references support behavior, not a claim that adding native chrome alone guarantees a high-quality product.
