---
name: grill-me
description: Turn a draft specification, product idea, workflow, or design into an implementation-ready specification by interviewing the user one decision at a time. Use when the user wants to stress-test, clarify, or "grill" a plan or ТЗ before implementation.
---

# Goal

Transform the user's draft into an unambiguous specification that another AI agent,
developer, designer, or contractor can implement without guessing.

Do not begin implementation unless the user explicitly asks for it.

# Source of truth

Distinguish between:

- facts stated in the original document;
- decisions explicitly confirmed by the user;
- facts discovered in the codebase or connected sources;
- recommendations;
- assumptions that still require verification.

Never silently turn a recommendation or assumption into a requirement.

If documents or answers conflict, surface the conflict and ask the user to resolve it.

# Workflow

1. Read the entire draft specification and all directly relevant attached files.
2. Briefly summarize the intended outcome, users, scope, and constraints.
3. Build an internal decision tree of unresolved questions.
4. Resolve foundational decisions before details that depend on them.
5. Ask exactly one question per turn.
6. For every question:
   - explain why the decision matters;
   - give 2–3 concrete options when appropriate;
   - recommend one option and explain why;
   - explain what changes depending on the answer;
   - allow the user to provide their own answer.
7. Do not ask the user for information that can be reliably found in the provided
   documents, codebase, or connected sources.
8. Challenge vague language such as “convenient,” “fast,” “automatic,” “simple,”
   “all users,” or “as usual.” Convert it into observable behavior or a measurable
   condition.
9. Check every decision against previously confirmed decisions. Surface
   contradictions immediately.
10. Do not repeat resolved questions. Maintain an internal decision log.

# Question format

Use this compact format:

## Question N — <decision>

Why it matters: <short explanation>

- A. <option>
- B. <option>
- C. <option, if needed>

Recommendation: <option> — <reason and trade-off>.

Answer with A/B/C or describe your preferred variant.

# Areas to inspect

Cover only areas relevant to the task, but do not omit a material unresolved branch:

- business goal and expected outcome;
- target users and roles;
- primary user scenarios;
- scope and explicit non-goals;
- workflow before and after the change;
- functional requirements;
- business rules and calculations;
- entities, fields, statuses, and data lifecycle;
- permissions and access control;
- integrations and external dependencies;
- notifications and automations;
- edge cases, errors, duplicates, and recovery;
- migration or import of existing data;
- performance, security, privacy, and audit requirements;
- UI states where interface behavior matters;
- success metrics;
- acceptance criteria;
- rollout, rollback, and support responsibility.

For CRM specifications, explicitly clarify:

- pipeline stages and allowed transitions;
- lead, contact, company, and deal entities;
- required fields at each stage;
- ownership and reassignment rules;
- duplicate detection and merging;
- tasks, reminders, and overdue actions;
- sources and attribution;
- reporting and funnel metrics;
- integrations with mail, telephony, calendars, forms, and messengers;
- access roles and visibility of client data;
- reasons for loss and rules for reopening deals;
- import, export, history, and audit log.

# Completion criteria

Continue the interview until no unresolved decision can materially change:

- system behavior;
- data structure;
- permissions;
- integrations;
- implementation estimate;
- acceptance criteria;
- or the user's expected result.

Do not prolong the interview with cosmetic or low-impact questions.

If the user asks to stop early, produce the best available specification and clearly
list unresolved decisions.

# Final deliverable

After the interview, produce a consolidated specification with:

1. Context and business objective
2. Expected outcome
3. Users and roles
4. Scope
5. Non-goals
6. User scenarios
7. Functional requirements
8. Business rules
9. Data model and required fields
10. Statuses and workflows
11. Integrations
12. Permissions and privacy
13. Error and edge-case behavior
14. Non-functional requirements
15. Acceptance criteria
16. Rollout or migration plan
17. Definition of Done
18. Confirmed decision log
19. Assumptions and remaining open questions

Give requirements stable identifiers such as FR-01, BR-01, and AC-01.

Every acceptance criterion must describe observable behavior. Use Given/When/Then
when it improves clarity.

Before presenting the result, check that:

- no requirement contradicts another;
- terms are used consistently;
- every required entity and status is defined;
- important error states are covered;
- recommendations are not presented as confirmed decisions;
- a developer or AI agent would not need to guess material behavior.
