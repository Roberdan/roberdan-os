# Visual-language method

Use with `skill.md` on any platform. The goal is a coherent, appropriate system,
not one signature style. Aesthetic judgment must point to the actual artifact.

## Read a reference before borrowing from it

Use representative content and more than one screen/state when available.
Record **observed rule / inferred purpose / adaptation / uncertainty** in the
existing task context. A screenshot cannot prove interaction, accessibility, or speed.

| Lens | Extract and question |
|---|---|
| Audience and purpose | Who is acting, with what expertise, urgency, and emotional context? What outcome matters? |
| Content hierarchy | What is read/acted on first, second, last? What is deliberately quiet? Does navigation explain location? |
| Typography and scale | Roles, family character, weight, line height/length, scale ratios, numeric alignment; behavior with long/localized text. |
| Space, grid, density | Alignment axes, columns, gutters, rhythm, grouping, reading versus working density; content-driven breakpoints. |
| Color and material | Semantic roles, contrast, brand accents, elevation, transparency, imagery; distinguish meaning from decoration. |
| Iconography | Stroke/weight, optical size, silhouette, labels, metaphor, family consistency; do not mix incompatible sets. |
| Interaction vocabulary | Affordances, navigation, selection, primary/secondary/destructive actions, focus, shortcuts, touch/hover differences. |
| Motion and feedback | Trigger, purpose, duration/easing, interruption, progress truthfulness, reduced-motion equivalent. |
| Responsive states | What reflows, collapses, disappears, or changes input mode? Inspect narrow/wide, zoom, populated, empty, and failure views. |

Copy principles only when they support this product. Never infer the audience's
preferences from an aesthetic trend or reproduce a brand asset without rights.
For example, dense analytical work may favor aligned tables and restrained motion;
editorial discovery may favor typographic hierarchy and imagery. Neither is universal.

## Turn a direction into a system

Agree these rules before multiplying screens; reuse existing tokens and components.
Use platform-native theme/assets/styles or the project's token system, not a new tool.

| Layer | Minimum useful contract |
|---|---|
| Semantic tokens | Text/surface/action/status roles, type roles, spacing steps, density, radii, borders/elevation, icon sizes, motion durations/easing. |
| Variants | Map semantic roles across appearance, contrast, brand accent, scale, and responsive contexts; avoid hardcoded color per screen. |
| Component grammar | Define when a component is used, anatomy, emphasis, allowed variants, content limits, and composition rules. |
| State grammar | Default, hover where available, focus, pressed, selected, disabled, pending, success, error; define transitions and accessible feedback. |
| Layout grammar | Shared alignment/spacing rules, navigation structure, responsive priorities, overflow/scrolling, and touch/keyboard behavior. |
| Copy grammar | Stable names, action verbs, label casing, tone, units, status language, errors with recovery, and localization constraints. |

Tokens express decisions, not arbitrary fashionable numbers. For example,
`text.primary`, `surface.raised`, and `action.destructive` describe intent; adapt
names to project conventions. A single accent must not mean both selection and danger.
Specify which components own state and how task context survives navigation.
Check the grammar on a realistic primary screen, a dense/long-content screen,
and a narrow or failure state before propagating it.

A direction contract can be a compact response or entry in an existing artifact:
**audience/task; visual thesis; hierarchy; token/component rules; responsive/state
rules; accessibility/performance constraints; anti-goals; approval/evidence**.
Write a separate durable design-system file only when requested or convention requires.

## Critique the real artifact

Mark each row **pass / defect / not observed** with a screenshot region, UI action,
or measurement. Rank defects by task impact, not personal stylistic preference.

| Test | Failure to catch |
|---|---|
| Product completeness | Beautiful isolated component, missing navigation/back path, lost context, unreachable primary action. |
| Coherence | Same role looks/behaves differently; incompatible typography/icons/materials; unexplained token exceptions. |
| Hierarchy and density | Competing focal points, decorative whitespace hiding work, cramped data, weak grouping or alignment. |
| Accessibility/adaptation | Contrast or non-color cues fail, invisible focus, tiny targets, clipped zoom/localization, hover-only touch controls. |
| State coverage | Missing empty/loading/error/offline/permissions states; no retry, cancellation, or honest partial-result treatment. |
| Interaction truth | Fake features, dead controls, unsupported import/model claims, simulated progress presented as real work. |
| Motion/performance | Ornamental or misleading motion, broken interruption, needless idle work, unmeasured speed/energy claims. |
| Copy/UI agreement | Button promises a different result; inconsistent names/units/tone; vague errors; hidden destructive consequences. |

Compare the implemented artifact to the approved direction, then exercise its tasks.
Distinguish an owner's aesthetic preference from observed functional/accessibility
defects and measured performance. Do not call a score or screenshot usability proof.
