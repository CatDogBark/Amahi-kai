# jQuery UJS → Turbo/Stimulus Migration Plan

## Current State
- **38 remote forms** (`remote: true`) across all plugins
- **~73 jQuery AJAX calls** in plugin JS files
- **4 custom AJAX wrappers**: RemoteCheckbox, RemoteRadio, RemoteSelect, FormHelpers
- **1,940 total lines** of JavaScript across all plugins
- **jQuery UI** used for: highlight effects, templates
- **Sprockets** asset pipeline (can't switch to importmap without dropping bootstrap gem)

## Strategy: Incremental, Plugin by Plugin

### Why not a big bang?
- 38 forms + 73 AJAX handlers = too many failure points at once
- Each plugin is self-contained (own JS, views, controller)
- We can migrate one plugin, verify, then move to the next
- jQuery and Turbo can coexist during transition

### Phase 0: Foundation (do first)
1. Wire up `turbo-rails` in the asset pipeline (gem already installed)
2. Add `stimulus-rails` for controller-based JS
3. Keep jQuery loaded alongside Turbo (they coexist fine)
4. Add `data-turbo="false"` to `<body>` to disable Turbo Drive globally (opt-in per page)
5. Create Stimulus equivalents of RemoteCheckbox, RemoteRadio, RemoteSelect

### Phase 1: Easiest plugins first
**Disks** (1 line of JS, 2 controller actions) → trivial
**Settings** (40 lines, mostly server start/stop/restart toggles)

### Phase 2: Medium complexity
**Users** (176 lines) — new user form, delete, toggle admin, edit name/password/pin/pubkey
**Network** (258 lines) — hosts CRUD, DNS aliases CRUD, settings toggles

### Phase 3: Hardest
**Shares** (256 lines) — most complex interactions (toggles, permissions, disk pool, extras)
**Apps** (197 lines) — install/uninstall progress polling (needs Turbo Streams or Stimulus polling)

### Phase 4: Cleanup
- Remove `jquery_ujs`
- Remove custom AJAX wrappers (RemoteCheckbox etc.) once all converted
- Remove `jquery-ui` if no longer needed
- Remove `data-turbo="false"` from body (enable Turbo Drive globally)
- Optionally remove jQuery entirely if no remaining uses

## Pattern Mapping

| jQuery UJS Pattern | Turbo/Stimulus Equivalent |
|---|---|
| `remote: true` on forms | `data-turbo-frame` or Turbo Stream response |
| `ajax:success` event | Turbo Stream replace/update, or Stimulus `connect()` |
| `ajax:beforeSend` | Stimulus action `turbo:before-fetch-request` |
| `$.ajax({ type: "PUT" })` | `fetch()` in Stimulus controller |
| RemoteCheckbox (PUT + toggle) | Stimulus `toggle_controller` with `fetch` |
| `confirm:` data attribute | `data-turbo-confirm` |
| `$(element).hide("slow")` | CSS transitions + Stimulus |
| `$(element).effect("highlight")` | CSS animation class |

## Stimulus Controllers Needed

1. **toggle_controller** — replaces RemoteCheckbox/RemoteRadio (PUT request, toggle state)
2. **inline_edit_controller** — replaces SmartLinks (show/hide edit forms)
3. **delete_controller** — replaces delete button AJAX (DELETE request, remove element)
4. **form_controller** — replaces remote form success/error handling
5. **progress_controller** — replaces app install/uninstall polling

## Risks
- **jQuery UI templates** (`jquery.ui.templates.js`, 483 lines) — used for inline edit forms; need to convert to `<template>` tags or Stimulus
- **Spinner logic** — deeply integrated; needs a Stimulus approach
- **Bootstrap JS** — currently loaded via Sprockets; works fine with or without Turbo

## Test Coverage Required Before Starting
- ✅ All controllers have request specs
- ✅ Toggle actions tested
- Need: Feature specs for JS interactions (create user, delete share, etc.)
- The existing 35 feature specs cover basic navigation; need more for AJAX flows

## Decision Points
1. **Sprockets or importmap?** — Bootstrap gem forces Sprockets. We can use Stimulus with Sprockets (just add the JS files to the pipeline). No importmap needed.
2. **Turbo Frames vs Turbo Streams?** — Most interactions are "update one element" → Turbo Streams via `turbo_stream.replace` is cleanest
3. **Keep jQuery during transition?** — Yes, mandatory. Remove only after all plugins migrated.
