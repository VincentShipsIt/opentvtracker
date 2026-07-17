---
status: temporary
last_verified: 2026-07-16
---

# Captured Rules - Pending Review

Rules automatically captured from conversations. Review and promote to permanent storage.

---

## Pending Rules

### 2026-07-16 13:36 - Workflow: Beta bugs are P0

**User said (redacted):**

> "bugs should be p0"

**Rule extracted:**

- **Type**: ALWAYS
- **Action**: Label every bug discovered during OpenTV Tracker beta testing as `P0` when creating or triaging the GitHub issue.
- **Context**: OpenTV Tracker beta feedback and acceptance testing until the user changes the policy.
- **Category**: workflow

**Example:**

```text
Good: bug issue created with labels `bug` and `P0`
Bad: beta bug entered as an unprioritized backlog issue
```

**Status**: PENDING_REVIEW

### 2026-07-15 11:00 - Design: Category browsing stays tile-first

**User said (redacted):**

> "Browse like a menu: dumb title. Tiles are still overlapping. Fix the design."

**Rule extracted:**

- **Type**: AVOID
- **Action**: Avoid marketing headings and descriptive filler above category browsing. Present categories as a clean, aligned tile grid whose artwork is strictly clipped to each card.
- **Context**: OpenTV discovery and category-selection interfaces.
- **Category**: patterns

**Example:**

```text
Good: aligned two-column category tiles with a short white label
Bad: promotional heading and horizontally colliding artwork cards
```

**Status**: PENDING_REVIEW

---

## Processed Rules
