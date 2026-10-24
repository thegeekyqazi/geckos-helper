# Projects, goals and ideas (Obsidian)

Gecko tracks projects and personal goals as notes in your vault, in the same style
as your own notes, so they work fine without Gecko too.

## Where things live

| | |
|-|-|
| `Projects/<name>.md` | new projects and goals |
| `Projects/Ideas.md` | your ideas list (`/idea …`, or "save this idea") |
| `Projects/Projects Hub.md` | a progress table Gecko keeps up to date |
| anywhere | existing notes you ask Gecko to **adopt** stay where they are |

Change the folder or ideas note under `[desktop]` in `config.toml`
(`projects_folder`, `obsidian_inbox`).

## A tracked note

```markdown
---
type: project            # or goal
status: active           # idea | active | on-hold | done
category: 💻 Tech & Projects
created: 2026-10-24
due: 2026-12-01
tags: [project, active]
---
# 📦 Inventory Prediction

**Category:** 💻 Tech & Projects
**Status:** 🟡 Active

## 🎯 Goal
## 📋 Plan
- [ ] Pick a dataset 📅 2026-11-01
## 💡 Ideas & Notes
## 📈 Progress Log
- 2026-10-24: Created
```

Tasks use the Obsidian Tasks format, so they also show in your Tasks and
Dataview queries. Gecko keeps the frontmatter, the **Status:** line and the tags
in sync when the status changes.

## What you can say

- "Let's start a project: …" / "I want to get to the gym 3× a week" (a goal)
- "Track my Inventory Prediction note as a project" (adopt)
- "I finished the dataset part" (ticks the task, logs progress)
- "Put CP312 prep on hold" / "What should I do next?" (`/next`)
- `/idea …`, then **Start** on the Projects page to turn it into a project

## To-dos from projects

The **Project check-in** recipe (Mon and Thu, 08:30) and the **Daily briefing**
can suggest to-dos. They show in the Inbox with checkboxes; **Add N to to-dos**
puts the ones you tick on your to-do list (end-4's sidebar, and the desktop widget
if you use Gecko's dots). Suggestions from a report the injection guard flagged are dropped.
