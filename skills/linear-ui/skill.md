---
name: linear-ui
description: "Design, implement or review coherent Linear-inspired application interfaces: compact navigation, useful density, themed menus, adaptive action icons and whole-surface accessibility. Use for Linear-style UI, dense workspaces, dashboards, consistent dropdowns, clipped toolbar labels, or a reusable interaction system. Preserve the product's brand, themes, palette, platform and business behavior; this is a design method, not a framework migration."
providers: [claude, copilot, codex]
---

# linear-ui

Build a calm, compact working interface, not a screenshot that resembles Linear.
Borrow hierarchy, alignment, navigation clarity and interaction consistency;
do not copy branding, artwork, exact colors or an entire product's layout.
This skill supplies a direction and acceptance method, not permission to publish.

## Fit and boundaries

- Use for application workspaces: lists, boards, timelines, reports, editors,
  administrative tools and desktop/web companions with recurring tasks.
- An explicitly approved alternative direction wins. Do not impose dashboard
  density on editorial, expressive, child-facing or voice-first experiences.
- Keep the existing framework and platform. Do not add a build step, component
  library or web wrapper merely to restyle controls.
- For Apple targets, also invoke the host-declared `apple-designer` skill, or
  read its [canonical guidance](../apple-designer/skill.md). Native interaction,
  accessibility, typography and materials remain platform-specific.
- Reuse the generic reference-analysis method in
  [visual-language.md](../apple-designer/visual-language.md), rather than
  inventing a competing design process.
- Use current public platform documentation for APIs and accessibility patterns.
  Do not inspect a signed-in workspace or copy private screenshots as references.

## 1. Establish the contract before changing pixels

Record a short contract in the task's existing state:

1. Audience, primary task, platform, input methods and supported environments.
2. What must remain unchanged: brand, themes, palette, fonts where required,
   navigation, filters, selection, calculations, permissions and write safeguards.
3. Existing component and icon systems, native controls, rendering lifecycle,
   offline/export hosts and optional or feature-gated surfaces.
4. The exact evidence required for visual preference, behavior and accessibility.

Inventory every reachable view and control family, not only the home screen.
Include shell/settings, search, filters, menus, editable suggestions, drawers,
dialogs, confirmations, loading/error/empty states and exported documents.
Track default and proposed presentations separately. A source inventory proves
what was found in source, not that the interface was exercised.

Do not change themes, colors, palette values, opacity or semantic color mappings
unless explicitly authorized. Reusing a token name is insufficient if its use
changes the meaning of selection, warning or error. If an existing color
constraint prevents adequate contrast, report the conflict; do not quietly
recolor the product or weaken the accessibility requirement.

## 2. Approve a small real slice, then propagate

Unless the direction is already approved, present two or three inexpensive
directions using identical synthetic content, dimensions, state and theme.
Recommend one. Show a primary workflow and a dense or narrow state, not just
an empty landing page.

Prefer an interactive slice with the real renderer. Label static mockups,
interactive prototypes and functional application evidence distinctly.
Measure useful changes: where content begins, rows visible, steps to an action,
readability and retained controls. Less vertical space is not success if a
button disappears, text becomes too small or meaning is removed.

Keep the existing presentation available behind the project's established
preview boundary. Do not invent persistent preferences or alter domain payloads
to carry a temporary presentation choice. Visual approval is not release
approval, permission for external writes or proof of accessibility.

## 3. The visual grammar

| Area | Linear-inspired rule |
|---|---|
| Shell | Stable, quiet navigation; clear active location; predictable keyboard entry points. |
| Header | One view title, compact context, explicit primary action; avoid stacked hero/header duplicates. |
| Content | Prefer aligned working surfaces over decorative card stacks. Keep related facts together. |
| Density | Remove repetition and excess spacing before reducing text or target sizes. |
| Typography | Clear hierarchy, readable secondary text, aligned numeric values, reliable font fallback. |
| Actions | Consistent placement, icon family and wording; primary, secondary and destructive roles remain distinct. |
| Filters | Group by purpose, show active state and a predictable reset without losing unrelated context. |
| Detail | Reveal supporting information progressively, without hiding the task or breaking return focus. |
| Status | Distinguish loading, unavailable, empty, partial and failed; never present missing data as zero. |

Preserve provenance and what counts actually mean. A compact summary must not
turn planned work into actuals, a partial result into complete coverage, or
different populations into interchangeable numbers.

Reuse existing primitives and renderers. When shared behavior is missing,
introduce a small shared primitive rather than independent per-view patches.
Do not replace routing or business logic just to obtain a new header.

## 4. Menus and suggestions belong to the same visual system

Style the open popup as well as the closed control. Changing a border or arrow
while the list still uses unrelated operating-system chrome is not complete
when a product-themed dropdown was requested.

First reuse a proven accessible component already present in the project.
Choose the control by semantics: select-only combobox, editable combobox,
multi-select listbox, action menu, disclosure and date picker are different.
Do not replace all of them with one generic dropdown.

For web adapters over native controls:

- Keep the native value and application event contract authoritative. Preserve
  form submission, validation, disabled/required states, labels and descriptions.
- Preserve `input.list` when existing application logic depends on it. Keep
  free text in an editable suggestion field unless the domain prohibits it.
- Synchronize programmatic value changes, dynamic options, disabled groups,
  empty options, reset and rerenders without duplicate events or observers.
- Provide the correct role, accessible name, expanded state, active option and
  selected state. Active navigation is not necessarily committed selection.
- Exercise arrows, Home/End, typeahead, Enter/Space as appropriate, Escape,
  Tab, outside dismissal, scrolling and focus restoration.
- Keep the popup inside the viewport and the owning modal's accessibility/focus
  boundary. Do not let clipping or stacking make options unreachable.

Platform APIs such as customizable native selects can help, but verify the
supported browser/platform matrix. Do not silently accept an OS popup on
unsupported engines while claiming consistent custom styling everywhere.
Do not sacrifice native accessibility merely to imitate another platform;
surface an unresolved platform tradeoff instead.

## 5. Adapt action labels to available space

Keep text when it fits. For familiar actions with an unambiguous existing icon,
use an icon-only presentation when the actual container cannot accommodate the
label. Measure the container and content, or use a proven container-aware
component; the global viewport or a matching media breakpoint is not proof.

- Preserve the original action, identifier, handler and full accessible name.
- Provide a discoverable label on keyboard focus as well as hover; touch users
  must not depend on hover to identify an unfamiliar action.
- Keep the icon through loading/retry label changes, with truthful visible or
  accessible status and correct disabled/busy state.
- Make the change reversible as space returns. Test font loading, localization,
  long labels, nested containers and rerenders.
- Do not collapse ambiguous, destructive or format-sensitive actions into the
  same glyph. Keep explicit labels, wrap or reorganize the toolbar instead.
- Do not force icons onto every button. Do not shrink targets to conceal overflow.

Refresh, spreadsheet export and a clearly named document export may be good
candidates; that is an example, not a universal hardcoded allowlist.

## 6. Validate every host and the actual outcome

Read [verification.md](verification.md) before implementation acceptance.
Carry the inventory into a matrix of implemented, exercised, intentionally
unchanged and unverified items, each with evidence or a reason.

Use real application journeys, not only isolated component demos. Verify the
result the user sees after an action: the new report rows and generation, the
file actually downloaded, the reopened detail or the restored focus.
A successful request, backend job or generated Blob alone is not that result.
Synthetic external boundaries are appropriate; replacing the implementation
under test is not an end-to-end check.

Offline exports are another host, not screenshots. Include their complete
dependency order, frozen selection/theme/reference state and input escaping.
Open the actual generated and extracted files without the app server or network.
If files are expected to match, compare their bytes. Keep offline documents
read-only where the product requires it.

## 7. Deliver quickly without inventing confidence

Make a coherent, clearly labelled preview available early, independently of
final certification. Freeze its source revision and isolate its data, profile,
port and write authority. Do not serve partially merged or actively edited files.

Follow [engineering-reference](../engineering-reference/skill.md) for parallel
ownership and integration. Separate working copies prevent file overwrite, not
semantic conflicts. Reconcile exact completed handoffs serially; a published
snapshot does not prove another agent has stopped working.

Give each author and reviewer a different owned evidence directory. Existing
inventories, logs and screenshots are read-only inputs, never templates to
overwrite with reviewer summaries. Record revision, method, environment,
scope, result and provenance. Reconstructed evidence must say it is reconstructed.

Use the project's review budget and required independent verifier. Do not add
endless rounds or quietly waive a literal requirement to get a green report.
Report working behavior, remaining failures and human/external limits separately.
Only the owner can approve subjective direction or release gates that belong
to them; only the project's authorized verifier can close its completion gate.

## 8. Reuse the method without copying the implementation

Keep three ownership layers distinct:

- **Canonical skill:** direction, interaction principles, evidence and acceptance.
  Use the existing generated wrappers; do not maintain copied skills in consumers.
- **Component system:** executable controls, semantic tokens, compositions and
  tests for its supported platform. Improve existing primitives, not a rival family.
- **Product adapter:** brand, domain language, platform-specific interaction and
  application state. Native and web products can share meanings and test scenarios
  without sharing a renderer, material or pixel value.

Before recommending a framework, inspect its actual distribution: source, runtime
styles, exported tokens, component registry and agent-facing documentation can
disagree. A package version or a monorepo build is not an isolated-consumer check.
Preserve the rendered appearance when reconciling distribution inconsistencies.
Do not extract private application code into a public shared library.

Record the guidance revision and the component release or immutable registry
snapshot used by each consumer. An update creates a candidate: run that consumer's
compatibility checks, review differences, preserve local adaptations and retain
rollback before adoption. Distinguish **available** from **adopted and verified**.
Do not implement automatic-latest adoption or cross-project edits without scope.

## Reference basis

Checked 2026-09-13; recheck guidance when the platform or interaction changes.

- [Linear's redesign process](https://linear.app/now/how-we-redesigned-the-linear-ui):
  hierarchy, alignment, working density, multiple view families and staged rollout.
- [WAI-ARIA combobox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/):
  interaction semantics, not a license to omit browser and assistive-technology tests.
- [Verification sources and exact criteria](verification.md#sources).
