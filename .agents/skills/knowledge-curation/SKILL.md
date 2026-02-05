---
name: paa-knowledge-curation
description: Curate, read, and persist long-term precision-alignment knowledge into `.paa/memory/` as flat, topic-based files (usually API-agnostic), and help agents retrieve it.
---

## `.paa/memory/` layout (long-term, topic-based)

All **long-term** knowledge (cross-task patterns, conclusions, lessons) SHOULD be stored under `.paa/memory/` as **flat Markdown files**, each file representing **one topic** (similar to a skill).
Topic filenames should use conceptual names and **avoid API names**, for example:

- `accuracy-compatible-kernel.md`
- `elementwise-reduction-precision.md`
- `gpu-compile-error-patterns.md`
- `precision-testing-high-signal-cases.md`

Agents (Planner / Diagnostician / Validator / Reviewer) use this skill to:

- Read topic files from `.paa/memory/` by filename and/or tags.
- Append new, abstracted lessons from `.paa/sessions/...` into existing topics, or create new topics when needed.

Each topic file is a standalone Markdown file with:

- Optional YAML frontmatter, for example:

```markdown
---
category: precision-comparison    # or: basic-diagnosis | precision-testing | workflow | other
owner: P                          # P | D | V | R
created_at: 2026-02-02T10:00:00+08:00
tags: [broadcast, float32, gpu, backward, accuracy-compatible]
summary: Brief outcome-focused summary of the core pattern or lesson.
---
```

- Free-form body content, recommended sections:
  - Summary & Recommendations
  - Key Observations / Patterns
  - Representative Examples
  - Recommended Procedures (diagnosis / fix / testing)

## Reading knowledge (used by agents)

When starting or updating a precision-alignment task, agents call this skill to load **topic-level**, API-agnostic guidance:

- Search within `.paa/memory/` using `glob` + `grep` (or equivalent) by:
  - topic filename (e.g. `accuracy-compatible-kernel`)
  - tags (e.g. `broadcast`, `float16`, `gpu`, `compile`, `accuracy-compatible`)
- Prioritize:
  - Topics that clearly match the current operator family or pattern (e.g. elementwise, normalization, reduction).
  - Topics that match key tags from the current task (dtype, device, error type).
- Extract and summarize:
  - Common precision/diagnosis/testing patterns and validated strategies.
  - Known pitfalls to avoid (fragile shapes/dtypes/devices, tricky flags).
  - Recommended test combinations (Paddle unit tests, PaddleTest, PaddleAPITest) for this pattern.

The output should be a **short, actionable knowledge brief**:

- 3–7 bullet points of key lessons, constraints, and do/don’t.
- A short list of the most relevant `.paa/memory/*.md` topic files for deeper reading.

## Writing and updating knowledge (from sessions to memory)

At the end of a task (or when a milestone reveals a high-value, **reusable** pattern), agents can use this skill to **promote** session-level findings into long-term memory:

- Choose or create a `topic` name that describes the pattern (no API names), e.g.:
  - `accuracy-compatible-kernel`
  - `elementwise-reduction-precision`
  - `gpu-compile-error-patterns`
  - `precision-testing-high-signal-cases`
- Update `.paa/memory/{topic}.md` by:
  - Appending a new dated entry with summary, key observations, and procedures; or
  - Refining existing content if it is clearly the same pattern.

When writing or updating topics:

- Prefer **updating an existing topic** (same concept/tags) instead of creating near-duplicates.
- Keep content API-agnostic; mention specific APIs only as examples inside the body, not in the filename.
- Maintain a stable tag vocabulary to make future lookup reliable.
