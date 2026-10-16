---
date: <YYYY-MM-DD>
title: <one line the index shows>
kind: change               # incident | release | change | decision | investigation | handoff
environments: [dev]        # dev | qa | prod - every environment involved
outcome: done              # done | partial | open | rolled-back
memory: []                 # memories this entry created or changed, e.g. [memory/<name>.md]
---
**What happened:** <symptom or goal, when, who was affected - as roles>

**What was done:** <the steps, in order, with the environment of each>

**Evidence:** <commits, PRs, versions, flow run ids, queries - links, not data>

**Follow-ups:** <open items, with the role that owns each; mirror lasting ones in a memory>
