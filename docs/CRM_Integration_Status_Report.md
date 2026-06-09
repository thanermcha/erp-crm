# CRM Integration Status Report

Date: 2026-06-04
Branch observed: `integracao`

## 1. Consolidated State

The repository is not in a clean production-ready state yet, but the CRM integration path is now clearer:

- The CRM menu and onboarding scaffolding already exist in the product.
- The `growerp_freelabot_integration.md` document now describes the target integration model in detail.
- The local working tree contains CRM-related seed/config changes that appear to move the stack toward a `Blah Software`-specific campaign setup.
- The start/stop operational checklist exists, but it is still a planning artifact, not an implemented automation path.

## 2. What Has Been Done

### Documentation and architecture

- Defined the staging flow for external leads and deduplication before canonical writes.
- Defined HubSpot webhook-based sync instead of polling.
- Defined `ownerPartyId` multi-tenant isolation as the governing model.
- Documented a target sequence for daily sync, campaign filtering, weekly cleanup, and monthly archival.

### Product scaffolding already present

- The admin CRM entry is present in menu seed data.
- The onboarding prompt catalog already includes `/crm` as a supported route.
- The backend has explicit `AppSupport` handling in service logic, which matters for login and URL discovery.

### Local configuration changes observed

- `backend/data/GrowerpFreelabotCrmData.xml`
  - switched campaign/landing seed records from `DEMO` to `_NA_`
  - this moves the sample data away from tenant-specific demo ownership
- `backend/data/GrowerpSupport.xml`
  - added `SYSTEM_SUPPORT -> AppAdmin`
  - this expands the support account's access scope
- `flutter/packages/admin/assets/cfg/app_settings.json`
  - changed `classificationId` from `AppAdmin` to `AppSupport`
  - changed backend/chat endpoints to `127.0.0.1:18081`

## 3. Proposed Changes

### Immediate

1. Stabilize the branch base before adding more changes.
2. Decide whether the admin app should run as `AppAdmin` or `AppSupport` locally.
3. Keep tenant seed data and example data clearly separated.
4. Add `.gitignore` rules for generated/ephemeral files that are not part of the product.

### Next implementation slice

1. Implement a real CRM import/staging service instead of only describing it.
2. Add a deterministic loader for `source_records` or the equivalent canonical import path.
3. Add a dry-run preview for merge/dedup decisions before canonical write.
4. Add a minimal CRM screen that can surface sample messages, segments, and landing page mappings.

### Operationalization

1. Convert the start/stop checklist into executable scripts or systemd units.
2. Add a repeatable local bootstrap flow for the backend and admin UI.
3. Add a health-check and a post-start verification step for `/crm`.

## 4. Diagnosis

### High confidence issues

1. `AppSupport` vs `AppAdmin` mismatch in the admin config
   - `flutter/packages/admin/assets/cfg/app_settings.json` now identifies the admin app as `AppSupport`.
   - The codebase uses `classificationId` to drive backend discovery and onboarding behavior.
   - Risk: the admin UI may resolve the wrong backend policy, menu profile, or startup prompt set.

2. Support account has widened access
   - `backend/data/GrowerpSupport.xml` now grants `SYSTEM_SUPPORT` both `AppSupport` and `AppAdmin`.
   - Risk: support login may see more than intended, which can mask authorization bugs during local testing.

3. Seed data ownership changed to `_NA_`
   - `backend/data/GrowerpFreelabotCrmData.xml` now uses `_NA_` for the CRM campaign/persona seeds.
   - Risk: if the import path expects `DEMO` or `GROWERP`, these records may stop appearing in the intended tenant context.

4. Generated and ephemeral files are present in the worktree
   - `.antigravitycli/` and `flutter/packages/growerp_catalog/example/macos/Flutter/ephemeral/flutter_native_integration.env`
   - Risk: accidental commit noise, unstable diffs, and platform-specific build leakage.

### Medium confidence issues

1. Local branch divergence is significant
   - The local branch is not aligned with the remote baseline.
   - Risk: new work may be built on top of an outdated branch tip, creating painful merge conflicts later.

2. CRM integration is still documentation-first
   - The architecture exists on paper, but the code path for `crm_core.py`, webhook ingestion, and `source_records` persistence is not yet confirmed in the repository.
   - Risk: the team may assume the import pipeline already exists when it is still only a plan.

3. Local Docker/bootstrap state is not guaranteed
   - Previous installation attempts showed the host needed privilege handling and runtime setup.
   - Risk: the environment can mislead debugging if Docker or compose services are not consistently running.

## 5. Conflict Watchlist

- `classificationId` choice must be consistent across:
  - backend login discovery
  - frontend `app_settings.json`
  - seed user/group assignments
  - onboarding prompts
- `ownerPartyId` must be consistent across:
  - demo/import data
  - landing pages
  - marketing campaigns
  - actual tenant-owned records
- Generated build artifacts must stay out of commits.

## 6. Recommended Next Step

The safest next step is:

1. normalize the branch base,
2. decide the local app classification model,
3. then implement the first real import path for CRM data.

That sequence minimizes the chance of building on a misclassified or partially broken local configuration.

---

## 7. tasks+data Trace Report - 2026-06-04T03:21:01-03:00

### Human Summary

- Workspace: `/home/moore/growerp`
- IDE observed: Cursor / Codex panel, web preview for `http://localhost:18081/admin/#/crm`
- Active branch: `integracao`
- Main repository HEAD: `ea3e25fb3177166e6d34f8ebce3cee86118be99f`
- Local branch commits above `master`: `2`
- Branch diff from `master..integracao`: `10 files changed`, `2241 insertions`, `5 deletions`
- Current uncommitted tracked diff: `3 files changed`, `26 insertions`, `24 deletions`
- Runtime validation: `SystemSupport / moqui` login succeeded with `AppSupport`; landing page API returned `7` records, including all `blah-*` pages.
- Runtime services observed: `growerp-backend` healthy, `growerp-database` running, Docker `28.2.2`, Docker Compose `2.37.1+ds1-0ubuntu2~25.04.1`

### Repositories

- `/home/moore/growerp`
  - Remote: `https://github.com/growerp/growerp`
  - Branch: `integracao`
  - HEAD: `ea3e25fb3177166e6d34f8ebce3cee86118be99f`
  - Status: modified CRM seed/support/admin config; untracked report and generated files
- `/home/moore/growerp/moqui/runtime`
  - Remote: `https://github.com/growerp/moqui-runtime.git`
  - Branch: `growerp`
  - HEAD: `c2732620400689951ac7f20d52cd5463424709f7`
  - Status: clean against `origin/growerp`

### Commits Included In `integracao`

- `28b694a8d0f5105b971566ee1c99535aa7c6bf0a` - `feat: add Freelabot CRM integration`
- `ea3e25fb3177166e6d34f8ebce3cee86118be99f` - `feat: add interactive CRM dashboard`

### Files Created Or Added In Branch Diff

- `backend/data/GrowerpFreelabotCrmData.xml` - 554 lines
- `crm-dashboard/app.js` - 225 lines
- `crm-dashboard/data.js` - 261 lines
- `crm-dashboard/index.html` - 133 lines
- `crm-dashboard/style.css` - 752 lines
- `docs/TaskChecklist_growerp-start-stop.md` - 49 lines
- `docs/growerp_freelabot_integration.md` - 214 lines
- `growerp-crm.md` - 47 lines

### Files Modified In Current Uncommitted Runtime Fix

- `backend/data/GrowerpFreelabotCrmData.xml` - owner changed from `DEMO` to `_NA_` for local `SystemSupport` visibility
- `backend/data/GrowerpSupport.xml` - added `SYSTEM_SUPPORT -> AppAdmin` classification
- `flutter/packages/admin/assets/cfg/app_settings.json` - local admin now uses `AppSupport` and `http://127.0.0.1:18081`

### Structured JSON

```json
{
  "report_type": "tasks+data",
  "report_version": "1.0",
  "created_at": "2026-06-04T03:21:01-03:00",
  "created_by": {
    "agent": "Codex",
    "model": "GPT-5 Codex",
    "model_effort_observed": "5.5 Extra High",
    "token_usage": {
      "exact_current_session_available": false,
      "observed_prior_turn_total_tokens": 134991,
      "observed_prior_turn_input_tokens": 125791,
      "observed_prior_turn_cached_input_tokens": 274560,
      "observed_prior_turn_output_tokens": 9200,
      "observed_prior_turn_reasoning_tokens": 6407,
      "source": "user-pasted Codex UI token usage; exact aggregate for this full session is not exposed in local CLI/runtime"
    }
  },
  "environment": {
    "host": "Moore-Laptop-63",
    "user": "moore",
    "timezone": "America/Belem",
    "workspace": "/home/moore/growerp",
    "ide": "Cursor",
    "terminal": "bash",
    "docker": {
      "server_version": "28.2.2",
      "compose_version": "2.37.1+ds1-0ubuntu2~25.04.1"
    }
  },
  "repositories": [
    {
      "path": "/home/moore/growerp",
      "remote": "https://github.com/growerp/growerp",
      "branch": "integracao",
      "head": "ea3e25fb3177166e6d34f8ebce3cee86118be99f",
      "status": {
        "tracked_modified": [
          "backend/data/GrowerpFreelabotCrmData.xml",
          "backend/data/GrowerpSupport.xml",
          "flutter/packages/admin/assets/cfg/app_settings.json"
        ],
        "untracked": [
          ".antigravitycli/0910bc5d-3486-4309-85e7-3338e74eb180.json",
          "docs/CRM_Integration_Status_Report.md", "docs/tasks_data_reports.json",
          "flutter/packages/growerp_catalog/example/macos/Flutter/ephemeral/flutter_native_integration.env"
        ]
      }
    },
    {
      "path": "/home/moore/growerp/moqui/runtime",
      "remote": "https://github.com/growerp/moqui-runtime.git",
      "branch": "growerp",
      "head": "c2732620400689951ac7f20d52cd5463424709f7",
      "status": "clean"
    }
  ],
  "commits": [
    {
      "sha": "28b694a8d0f5105b971566ee1c99535aa7c6bf0a",
      "author": "thanermcha",
      "date": "2026-06-03T22:46:09-03:00",
      "subject": "feat: add Freelabot CRM integration"
    },
    {
      "sha": "ea3e25fb3177166e6d34f8ebce3cee86118be99f",
      "author": "thanermcha",
      "date": "2026-06-03T22:50:34-03:00",
      "subject": "feat: add interactive CRM dashboard"
    }
  ],
  "diff_summary": {
    "branch_master_to_integracao": {
      "files_changed": 10,
      "insertions": 2241,
      "deletions": 5,
      "added_files": [
        "backend/data/GrowerpFreelabotCrmData.xml",
        "crm-dashboard/app.js",
        "crm-dashboard/data.js",
        "crm-dashboard/index.html",
        "crm-dashboard/style.css",
        "docs/TaskChecklist_growerp-start-stop.md",
        "docs/growerp_freelabot_integration.md",
        "growerp-crm.md"
      ],
      "modified_files": [
        "flutter/packages/admin/assets/cfg/app_settings.json",
        "flutter/packages/growerp/lib/src/growerp/import.dart"
      ]
    },
    "working_tree_uncommitted": {
      "files_changed": 3,
      "insertions": 26,
      "deletions": 24,
      "files": [
        {
          "path": "backend/data/GrowerpFreelabotCrmData.xml",
          "insertions": 18,
          "deletions": 18
        },
        {
          "path": "backend/data/GrowerpSupport.xml",
          "insertions": 3,
          "deletions": 1
        },
        {
          "path": "flutter/packages/admin/assets/cfg/app_settings.json",
          "insertions": 5,
          "deletions": 5
        }
      ]
    }
  },
  "file_line_counts": {
    "backend/data/GrowerpFreelabotCrmData.xml": 554,
    "backend/data/GrowerpSupport.xml": 48,
    "flutter/packages/admin/assets/cfg/app_settings.json": 31,
    "docs/CRM_Integration_Status_Report.md": 346, "docs/tasks_data_reports.json": 191,
    "crm-dashboard/app.js": 225,
    "crm-dashboard/data.js": 261,
    "crm-dashboard/index.html": 133,
    "crm-dashboard/style.css": 752,
    "docs/TaskChecklist_growerp-start-stop.md": 49,
    "docs/growerp_freelabot_integration.md": 214,
    "growerp-crm.md": 47,
    "flutter/packages/growerp/lib/src/growerp/import.dart": 215
  },
  "runtime_changes": [
    {
      "target": "growerp-backend:/opt/moqui/runtime/component/growerp/data/GrowerpFreelabotCrmData.xml",
      "operation": "docker cp and MoquiStart data load",
      "result": "48 records loaded"
    },
    {
      "target": "growerp-backend:/opt/moqui/runtime/component/growerp/data/GrowerpSupport.xml",
      "operation": "docker cp and MoquiStart data load",
      "result": "11 records loaded"
    },
    {
      "target": "growerp-backend:/opt/moqui/runtime/component/PopRestStore/screen/store/admin/assets/assets/cfg/app_settings.json",
      "operation": "runtime config patch and container restart",
      "result": "served app_settings now points to AppSupport and http://127.0.0.1:18081"
    }
  ],
  "validations": [
    {
      "name": "admin app settings served",
      "command": "curl http://localhost:18081/admin/assets/assets/cfg/app_settings.json",
      "result": "classificationId=AppSupport; databaseUrl=http://127.0.0.1:18081"
    },
    {
      "name": "login API",
      "command": "POST http://127.0.0.1:18081/rest/s1/growerp/100/Login",
      "result": "HTTP 200; user=SystemSupport; classification=AppSupport"
    },
    {
      "name": "CRM landing pages",
      "command": "GET http://127.0.0.1:18081/rest/s1/growerp/100/LandingPage?start=0&limit=20",
      "result": "HTTP 200; totalResults=7; blah-* landing pages present"
    }
  ],
  "known_risks": [
    "Current admin app is configured as AppSupport for local development to bypass incomplete AppAdmin tenant setup.",
    "SystemSupport has both AppSupport and AppAdmin classifications in local seed data.",
    "CRM sample data ownerPartyId is _NA_ for this local runtime; tenant-specific production data should use the intended tenant ownerPartyId.",
    "Untracked generated files are present and should not be committed without review."
  ]
}
```
