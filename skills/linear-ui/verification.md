# Verification for Linear-inspired interfaces

Use alongside [skill.md](skill.md). Adapt the matrix to the actual product;
do not copy a previous application's view count or declare a sampled matrix
exhaustive.

## Inventory and evidence matrix

Give each reachable view and each distinct control family an entry:

| Field | Required meaning |
|---|---|
| Surface | View, shared shell, overlay, feature-gated flow or offline host. |
| Entry/state | How it is reached, required data, role, flag and loading/error state. |
| Control | Semantics, accessible name, original handler and proposed presentation. |
| Behavior | Selection, navigation, focus, validation, loading and outcome to preserve. |
| Environment | Actual engine/platform, viewport, input method, theme and zoom. |
| Evidence | Revision, command or steps, observed result and owned artifact path. |
| Disposition | Exercised, unchanged with reason, failed, or unverified. |

Include enabled optional features, dialogs and detail panels; visiting their
parent page does not exercise them. A disabled feature can have a tested disabled
state while its enabled flow remains unverified. External embedded content is
a separate boundary: test the host's title, navigation and recovery without
certifying a third party's inaccessible or unauthenticated interior.

Source declarations and runtime observations answer different questions.
Report both denominators. A rendered control count does not establish coverage
of hidden states, all unique actions or every supported assistive technology.

## Exact geometry, not substitutes

Use the project's exact required dimensions. A useful web baseline is
**320, 375, 768 and 1440 CSS pixels**, plus content-specific widths and any
additional explicitly requested values. These are baseline probes, not a
claim that every device has those dimensions.

- Measure the actual viewport and control bounds, not just a requested window size.
- Check page overflow, popup bounds, text clipping and reachable actions.
- Exercise narrow containers inside wide pages as well as narrow pages.
- Keep meaningful two-dimensional surfaces, such as data tables or timelines,
  scrollable where necessary. That exception does not exempt their individual
  cells, action labels or surrounding page from reflow.
- Test both immediate and post-rerender layout, including loaded/fallback fonts.
- The same media-query branch is not equivalent to testing another width:
  content fit and container size vary continuously.

For web reflow, verify the equivalent of 320 CSS pixels at 400% zoom from a
1280-CSS-pixel viewport, with the applicable two-dimensional-content exceptions.
Separately exercise actual browser page zoom at 200%. A viewport resize,
device-scale override, pinch zoom, CSS `zoom` or root-font change alone is not
evidence of native browser page zoom.

Use a supported automation mechanism or a consented manual browser action.
Record the native zoom mechanism and observed geometry. Do not copy a
browser-version-specific preference recipe without validating it on that engine.
Never change the user's browser profile or operating-system settings just to
obtain a test result without the required approval.

## Text, targets and perception

For applicable web text-spacing checks, apply all four overrides together:

- Line height at least **1.5 times** the font size.
- Spacing following paragraphs at least **2 times** the font size.
- Letter spacing at least **0.12 times** the font size.
- Word spacing at least **0.16 times** the font size.

Confirm no lost content or functionality. These are adaptability test values,
not a requirement to ship the interface with those default settings.

For web WCAG 2.2 AA, check target size of at least **24 by 24 CSS pixels**, or
document the applicable exception and its evidence. Prefer larger targets for
important/touch actions, commonly 40-44 CSS pixels where appropriate. A project's
explicit 44-pixel requirement is not satisfied by citing the 24-pixel minimum.
Use platform-specific units and requirements for native applications; do not
treat CSS pixels, Apple points and Android density-independent pixels as identical.

Check computed contrast across all supported themes and states:

- Normal text: **4.5:1**; qualifying large text: **3:1**.
- Required non-text control/state indicators: **3:1** against adjacent colors,
  with the applicable exceptions documented.
- Selection, focus, warning, failure and availability must not depend on color alone.

Test keyboard focus visibility and whether sticky headers, drawers, tooltips or
popups obscure it. Honor reduced-motion and applicable platform accessibility
preferences. A stylesheet declaration is not proof of actual rendered behavior.

## Interaction and assistive technology

Test real sequences, not isolated `click()` calls:

1. Navigate to a view, filter/search, open a result, inspect its detail, close it
   and return to the original control with the expected state and scroll position.
2. Open each distinct popup family, navigate/select/cancel, tab away, update
   options or reset, then repeat after a rerender.
3. Run a primary action through loading, success and failure. Confirm the visible
   result and accessibility status, not merely the request response.

For menus and editable suggestions, verify the chosen pattern's arrows, Home/End,
typeahead, Enter/Space, Escape and Tab behavior. Disabled options/groups must stay
unavailable; active and committed selections must remain distinct where intended.
Do not apply select-only key handling to a free-text editor indiscriminately.

Inspect the browser/platform accessibility tree for names, roles, values,
expanded/selected/disabled states and descriptions. Then exercise the required
screen reader on the actual supported platform. The tree is useful evidence,
but **not screen-reader execution or a full accessibility certification**.
Do not add noisy live announcements just because a static audit cannot observe
an existing native or ARIA state announcement.

Document actual engine, operating system and reader versions. Untested engines,
devices, readers and gated states remain unverified. Do not silently convert a
required row into an optional limitation.

## Trustworthy journeys and offline evidence

- Use synthetic data and isolate every data home, not just a directory called
  `runtime`. Include preferences, manual overlays, local databases and caches.
- Keep real routing, controllers, persistence and confirmation guards under test.
  Stub external systems at their boundary, not the module whose behavior is claimed.
- Keep synthetic fixture reads explicitly allowlisted. A legitimate new read
  needs a deliberate fixture contract, not a wildcard exception or swallowed error.
- Await the rendered result for the exact operation/generation. If a publication
  callback can fail independently, a successful job or download is insufficient.
- Await download completion before ending the browser. Open the real HTML and
  the HTML extracted from its archive; verify expected byte equality and no-network
  operation where promised. A Blob or intercepted click is a narrower claim.
- Preserve dependency ordering, serialization and script/style terminator
  escaping in every standalone host. The live app's dependency list is not
  automatically the export's dependency list.
- Use owned browser profiles and exact process cleanup under the project's
  conventions. Cleanup failures remain visible; retries must be bounded and scoped.

## Acceptance and preservation

Keep author, reviewer and final-verifier reports in separate per-run directories.
Never overwrite inputs to make their shape match a review template. Preserve failed
runs and the later passing evidence; explain which result supersedes which.

Report commands, return codes, skips, observations and remaining gates accurately.
Do not reuse a stale log from a command that never ran after an earlier failure.
Measured performance data must come from actual measurements; do not fabricate
timings or loosen a test to manufacture a passing result.

Visual preference, functional tests, accessibility and release readiness are
different verdicts. Required failures or unverified rows prevent the corresponding
verdict, even if another category passed. An early useful preview can still be
shared when clearly labelled and safe; it does not waive final acceptance.

## Sources

Reference list maintained 2026-09-13; verify current wording and platform support.
An inaccessible or script-only documentation page is not evidence that its
current guidance was read.

- [WCAG 2.2 reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)
- [WCAG 2.2 text spacing](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html)
- [WCAG 2.2 target size, minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- [WCAG 2.2 text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [WCAG 2.2 non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- [WCAG 2.2 focus not obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html)
- [WAI-ARIA combobox patterns](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/)
- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
