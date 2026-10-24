# Recipes

A recipe is a saved task that runs on a schedule and/or when something happens,
and reports to Gecko's inbox, a notification, or both. Recipes are **read-only**:
they run under the unattended profile (web search, web fetch only for domains you
list, Gecko's read-only tools; no shell, no file edits, no writes). Their reports
are scanned by the injection guard.

Bundled: **Daily briefing** (on, 08:00), **Deadline radar** (off, 20:00, notifies
only if something is due within 48 h), **Weekly review** (off, Sunday 18:00).
Toggle them on the Activity page.

## Your own

Put a `.toml` file in `~/.config/geckos-helper/recipes/` (a file with a bundled
recipe's name replaces it), or ask Gecko: "make a recipe that…".

```toml
name = "Gym check"
prompt = "Is the Laurier Athletic Complex open late tonight? Give hours."
daily_at = ["16:00"]            # or weekly_at = ["mon 07:00"], every_minutes = 120
model = "haiku"                 # sonnet for reports that need judgment
output = "notify"               # inbox | notify | both
fetch_domains = ["laurierathletics.com"]
enabled = true

[[triggers]]                    # optional; a recipe can be trigger-only
type = "event_soon"             # battery_below 15 | file_added "~/Downloads"
value = 15                      # event_soon 15 (minutes) | notification_from "Discord"
```

If a recipe has nothing worth reporting, it replies `NOTHING` and you see only an
Activity entry.

## Budget

Unattended runs (recipes and watchers) stop before they eat into your own chats:
`[budget]` in `config.toml` caps runs per day and pauses while the 5-hour or 7-day
usage windows are nearly used. The menu shows today's count and any pause.
