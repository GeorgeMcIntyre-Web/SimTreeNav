# SimTreeNav API and Integration Specification

This document defines a REST and webhook integration surface for third-party tools to consume SimTreeNav simulation data. It is designed for analytics, automation, and operational visibility.

## Goals

- Provide a stable, versioned API for study health, activity, timelines, and work statistics.
- Support real-time and event-driven integrations via webhooks.
- Enforce strong authentication, role-based authorization, and predictable rate limits.
- Make consumption simple with consistent schemas, pagination, and error responses.

## Base URL and Versioning

- Base URL: `https://{host}/api/v1`
- Versioning: URI-based (`/v1`). Breaking changes increment the version.
- Content Type: `application/json; charset=utf-8`

## Authentication and Authorization

### API key management

API keys are issued to users or service principals. Each key has:
- `keyId` and `secret` (only shown at creation)
- `role` (viewer, manager, admin)
- optional `scopes` (fine-grained access)
- optional `expiresAt`

Recommended header:
- `Authorization: ApiKey {keyId}.{secret}`

Management endpoints (admin only):
- `POST /v1/api-keys` create a key
- `GET /v1/api-keys` list keys (no secrets)
- `PATCH /v1/api-keys/{keyId}` rotate or disable
- `DELETE /v1/api-keys/{keyId}` revoke

### Role-based access

- **viewer**: read-only access to studies, activity, timelines, and work stats.
- **manager**: viewer access plus webhook management and status streaming.
- **admin**: full access, including API key management and tenant-level settings.

### Rate limiting

Default limits (configurable per tenant):
- 600 requests/min per API key
- 60 requests/min for timeline endpoints

Rate limit headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset` (epoch seconds)

On 429, honor `Retry-After`.

## Conventions

### Pagination

Query params:
- `page` (1-based, default 1)
- `pageSize` (default 50, max 500)

Response envelope:
```json
{
  "data": [],
  "page": 1,
  "pageSize": 50,
  "total": 1234
}
```

### Filtering and sorting

Common query patterns:
- `start` and `end` for time ranges (ISO 8601 UTC)
- `sort` with comma-separated fields, prefix with `-` for desc
  - example: `sort=-healthScore,updatedAt`

### Time and timezone

All timestamps are ISO 8601 UTC (`2026-01-20T21:41:00Z`).

### Errors

Standard error response:
```json
{
  "error": {
    "code": "invalid_request",
    "message": "start must be before end",
    "details": [
      { "field": "start", "issue": "must be before end" }
    ],
    "traceId": "cbe2a6b4d0f64b3aa5a3d7d3b8a3b0ab"
  }
}
```

Common HTTP statuses:
- 400 invalid request
- 401 missing or invalid key
- 403 insufficient role or scope
- 404 not found
- 409 conflict (duplicate or invalid state)
- 429 rate limit exceeded
- 500/503 server or dependency failures

## REST API Endpoints

### Get study lists with health scores

`GET /v1/studies`

Query params:
- `healthScoreMin` (0-100)
- `healthScoreMax` (0-100)
- `status` (active, stalled, completed)
- `ownerId`
- `updatedSince` (ISO 8601)
- `include` (comma list: `dependencies`, `tags`)
- `sort` (example: `-healthScore,updatedAt`)
- `page`, `pageSize`

Response (example):
```json
{
  "data": [
    {
      "studyId": "STUDY-2189",
      "name": "Rosslyn Line Balancing",
      "project": "J7337",
      "owner": { "userId": "u-104", "displayName": "A. Perez" },
      "healthScore": 82,
      "healthStatus": "green",
      "status": "active",
      "updatedAt": "2026-01-20T21:10:12Z"
    }
  ],
  "page": 1,
  "pageSize": 50,
  "total": 128
}
```

### Query work activity by date range

`GET /v1/activities`

Query params:
- `start` (required)
- `end` (required)
- `studyId`
- `userId`
- `workType` (enum: run, edit, validate, import, export)
- `location` (client app or host)
- `page`, `pageSize`

Response (example):
```json
{
  "data": [
    {
      "activityId": "ACT-9002",
      "studyId": "STUDY-2189",
      "actor": { "userId": "u-104", "displayName": "A. Perez" },
      "action": "run",
      "workType": "simulate",
      "timestamp": "2026-01-20T20:58:11Z",
      "durationSeconds": 184,
      "location": { "clientApp": "SimTreeNav Desktop", "host": "WS-991" }
    }
  ],
  "page": 1,
  "pageSize": 50,
  "total": 4120
}
```

### Retrieve timeline data for a specific study

`GET /v1/studies/{studyId}/timeline`

Query params:
- `start` (optional)
- `end` (optional)
- `includeCausality` (boolean, default false)
- `depth` (int, max 5)
- `eventType` (filter by type)
- `page`, `pageSize`

Response (example):
```json
{
  "data": {
    "studyId": "STUDY-2189",
    "range": { "start": "2026-01-19T00:00:00Z", "end": "2026-01-20T23:59:59Z" },
    "events": [
      {
        "eventId": "TL-448",
        "eventType": "dependency_change",
        "timestamp": "2026-01-20T18:42:01Z",
        "summary": "Resource assembly updated: Powertrain v4",
        "severity": "warning",
        "causality": {
          "parentIds": [],
          "childIds": ["TL-452"],
          "rootCauseCandidate": true
        }
      },
      {
        "eventId": "TL-452",
        "eventType": "health_score_drop",
        "timestamp": "2026-01-20T19:05:22Z",
        "summary": "Health score dropped from 86 to 62",
        "severity": "critical",
        "causality": {
          "parentIds": ["TL-448"],
          "childIds": [],
          "rootCauseCandidate": false
        }
      }
    ]
  },
  "page": 1,
  "pageSize": 200,
  "total": 2
}
```

### Fetch work type breakdown statistics

`GET /v1/studies/{studyId}/work-types`

Query params:
- `start` (optional)
- `end` (optional)
- `groupBy` (workType, user, day)

Response (example):
```json
{
  "data": {
    "studyId": "STUDY-2189",
    "range": { "start": "2026-01-01T00:00:00Z", "end": "2026-01-20T23:59:59Z" },
    "totals": { "count": 324, "durationSeconds": 98520 },
    "breakdown": [
      { "workType": "simulate", "count": 132, "durationSeconds": 68200, "percent": 67.4 },
      { "workType": "validate", "count": 78, "durationSeconds": 11450, "percent": 11.6 },
      { "workType": "edit", "count": 114, "durationSeconds": 18870, "percent": 19.2 }
    ]
  }
}
```

### Real-time user activity status

Snapshot:

`GET /v1/users/status`

Query params:
- `activeWithinSeconds` (default 300)
- `teamId` (optional)

Response (example):
```json
{
  "data": [
    {
      "userId": "u-104",
      "displayName": "A. Perez",
      "status": "active",
      "lastSeenAt": "2026-01-20T21:40:12Z",
      "currentStudyId": "STUDY-2189",
      "currentActivity": "simulate"
    }
  ]
}
```

Streaming (SSE):

`GET /v1/users/status/stream` with `Accept: text/event-stream`

SSE event payload:
```json
{
  "event": "user.status.changed",
  "userId": "u-104",
  "status": "idle",
  "lastSeenAt": "2026-01-20T21:40:12Z"
}
```

## Data Models (JSON)

### Study object

Schema:
```json
{
  "type": "object",
  "required": ["studyId", "name", "healthScore", "healthStatus", "status", "updatedAt"],
  "properties": {
    "studyId": { "type": "string" },
    "name": { "type": "string" },
    "project": { "type": "string" },
    "owner": {
      "type": "object",
      "properties": {
        "userId": { "type": "string" },
        "displayName": { "type": "string" }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "site": { "type": "string" },
        "program": { "type": "string" },
        "tags": { "type": "array", "items": { "type": "string" } }
      }
    },
    "healthScore": { "type": "integer", "minimum": 0, "maximum": 100 },
    "healthStatus": { "type": "string", "enum": ["green", "yellow", "red"] },
    "status": { "type": "string", "enum": ["active", "stalled", "completed"] },
    "dependencies": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["dependencyId", "type", "name", "status"],
        "properties": {
          "dependencyId": { "type": "string" },
          "type": { "type": "string", "enum": ["resource", "assembly", "dataset", "operation"] },
          "name": { "type": "string" },
          "version": { "type": "string" },
          "status": { "type": "string", "enum": ["ok", "changed", "missing"] },
          "lastModifiedAt": { "type": "string", "format": "date-time" },
          "impact": { "type": "string", "enum": ["low", "medium", "high"] }
        }
      }
    },
    "createdAt": { "type": "string", "format": "date-time" },
    "updatedAt": { "type": "string", "format": "date-time" }
  }
}
```

Example:
```json
{
  "studyId": "STUDY-2189",
  "name": "Rosslyn Line Balancing",
  "project": "J7337",
  "owner": { "userId": "u-104", "displayName": "A. Perez" },
  "metadata": { "site": "Rosslyn", "program": "SUV-2026", "tags": ["line-balance"] },
  "healthScore": 82,
  "healthStatus": "green",
  "status": "active",
  "dependencies": [
    {
      "dependencyId": "DEP-010",
      "type": "assembly",
      "name": "Powertrain",
      "version": "v4",
      "status": "changed",
      "lastModifiedAt": "2026-01-20T18:41:57Z",
      "impact": "high"
    }
  ],
  "createdAt": "2026-01-02T08:12:44Z",
  "updatedAt": "2026-01-20T21:10:12Z"
}
```

### Activity event

Schema:
```json
{
  "type": "object",
  "required": ["activityId", "studyId", "actor", "action", "timestamp"],
  "properties": {
    "activityId": { "type": "string" },
    "studyId": { "type": "string" },
    "actor": {
      "type": "object",
      "properties": {
        "userId": { "type": "string" },
        "displayName": { "type": "string" }
      }
    },
    "action": { "type": "string", "enum": ["run", "edit", "validate", "import", "export", "fail"] },
    "workType": { "type": "string" },
    "timestamp": { "type": "string", "format": "date-time" },
    "durationSeconds": { "type": "integer" },
    "location": {
      "type": "object",
      "properties": {
        "clientApp": { "type": "string" },
        "host": { "type": "string" },
        "ip": { "type": "string" }
      }
    },
    "details": { "type": "object" }
  }
}
```

Example:
```json
{
  "activityId": "ACT-9002",
  "studyId": "STUDY-2189",
  "actor": { "userId": "u-104", "displayName": "A. Perez" },
  "action": "run",
  "workType": "simulate",
  "timestamp": "2026-01-20T20:58:11Z",
  "durationSeconds": 184,
  "location": { "clientApp": "SimTreeNav Desktop", "host": "WS-991", "ip": "10.24.18.9" },
  "details": { "iterations": 4, "solver": "flowline-v2" }
}
```

### Work type summary

Schema:
```json
{
  "type": "object",
  "required": ["studyId", "range", "totals", "breakdown"],
  "properties": {
    "studyId": { "type": "string" },
    "range": {
      "type": "object",
      "properties": {
        "start": { "type": "string", "format": "date-time" },
        "end": { "type": "string", "format": "date-time" }
      }
    },
    "totals": {
      "type": "object",
      "properties": {
        "count": { "type": "integer" },
        "durationSeconds": { "type": "integer" }
      }
    },
    "breakdown": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "workType": { "type": "string" },
          "count": { "type": "integer" },
          "durationSeconds": { "type": "integer" },
          "percent": { "type": "number" }
        }
      }
    }
  }
}
```

Example:
```json
{
  "studyId": "STUDY-2189",
  "range": { "start": "2026-01-01T00:00:00Z", "end": "2026-01-20T23:59:59Z" },
  "totals": { "count": 324, "durationSeconds": 98520 },
  "breakdown": [
    { "workType": "simulate", "count": 132, "durationSeconds": 68200, "percent": 67.4 },
    { "workType": "validate", "count": 78, "durationSeconds": 11450, "percent": 11.6 },
    { "workType": "edit", "count": 114, "durationSeconds": 18870, "percent": 19.2 }
  ]
}
```

### Timeline event with causality

Schema:
```json
{
  "type": "object",
  "required": ["eventId", "eventType", "timestamp", "summary"],
  "properties": {
    "eventId": { "type": "string" },
    "eventType": { "type": "string" },
    "timestamp": { "type": "string", "format": "date-time" },
    "summary": { "type": "string" },
    "severity": { "type": "string", "enum": ["info", "warning", "critical"] },
    "causality": {
      "type": "object",
      "properties": {
        "parentIds": { "type": "array", "items": { "type": "string" } },
        "childIds": { "type": "array", "items": { "type": "string" } },
        "rootCauseCandidate": { "type": "boolean" }
      }
    },
    "metadata": { "type": "object" }
  }
}
```

Example:
```json
{
  "eventId": "TL-448",
  "eventType": "dependency_change",
  "timestamp": "2026-01-20T18:42:01Z",
  "summary": "Resource assembly updated: Powertrain v4",
  "severity": "warning",
  "causality": {
    "parentIds": [],
    "childIds": ["TL-452"],
    "rootCauseCandidate": true
  },
  "metadata": { "dependencyId": "DEP-010", "previousVersion": "v3" }
}
```

## Webhooks and Notifications

### Webhook management

Create a webhook:

`POST /v1/webhooks`

Request:
```json
{
  "name": "Ops Alerts",
  "targetUrl": "https://hooks.example.com/simtreenav",
  "events": [
    "study.health.changed",
    "study.dependency.updated",
    "study.stalled",
    "study.completed"
  ],
  "secret": "client-generated-shared-secret",
  "active": true
}
```

List or inspect:
- `GET /v1/webhooks`
- `GET /v1/webhooks/{webhookId}`

Update:
- `PATCH /v1/webhooks/{webhookId}`

Delete:
- `DELETE /v1/webhooks/{webhookId}`

### Event types and payloads

Common envelope:
```json
{
  "eventId": "EVT-9941",
  "eventType": "study.health.changed",
  "occurredAt": "2026-01-20T19:05:22Z",
  "studyId": "STUDY-2189",
  "data": {}
}
```

Study health score changes:
```json
{
  "eventId": "EVT-9941",
  "eventType": "study.health.changed",
  "occurredAt": "2026-01-20T19:05:22Z",
  "studyId": "STUDY-2189",
  "data": {
    "previousScore": 86,
    "currentScore": 62,
    "status": "red"
  }
}
```

Dependency updates (resource/assembly modifications):
```json
{
  "eventId": "EVT-9942",
  "eventType": "study.dependency.updated",
  "occurredAt": "2026-01-20T18:42:01Z",
  "studyId": "STUDY-2189",
  "data": {
    "dependencyId": "DEP-010",
    "type": "assembly",
    "name": "Powertrain",
    "previousVersion": "v3",
    "currentVersion": "v4",
    "status": "changed"
  }
}
```

Stalled study alerts:
```json
{
  "eventId": "EVT-9943",
  "eventType": "study.stalled",
  "occurredAt": "2026-01-20T12:30:00Z",
  "studyId": "STUDY-2189",
  "data": {
    "inactiveSince": "2026-01-17T09:00:00Z",
    "healthScore": 58
  }
}
```

Completion notifications:
```json
{
  "eventId": "EVT-9944",
  "eventType": "study.completed",
  "occurredAt": "2026-01-20T21:10:12Z",
  "studyId": "STUDY-2189",
  "data": {
    "finalHealthScore": 91,
    "completedBy": { "userId": "u-104", "displayName": "A. Perez" }
  }
}
```

### Webhook security and retries

- Sign requests using `X-SimTreeNav-Signature` (HMAC SHA-256 of raw body with shared secret).
- Include `X-SimTreeNav-Event` and `X-SimTreeNav-Delivery` headers.
- Retry on non-2xx with exponential backoff (max 10 attempts).
- Send a `webhook.ping` event on creation to validate connectivity.

## Example Integration Scenarios

### Power BI dashboard

- Use `GET /v1/studies` with `updatedSince` for incremental refresh.
- Pull work type stats with `GET /v1/studies/{studyId}/work-types`.
- Visualize healthScore trends and stalled studies.

### Slack bot daily summaries

- Query `GET /v1/studies?status=stalled` and `GET /v1/activities?start=...&end=...`.
- Post summary to a channel at a scheduled time.

### JIRA integration for critical health scores

- Subscribe to `study.health.changed` webhook.
- On `status` red or `currentScore` below threshold, auto-create a JIRA ticket.
- Include `studyId`, last changed dependency, and root cause candidate from timeline.

### Excel plugin for reports

- Pull study lists and activity summaries via `GET /v1/studies` and `GET /v1/activities`.
- Cache results locally and refresh only when `updatedSince` changes.

## Sample Code

### Authenticate and query the API

PowerShell:
```powershell
$baseUrl = "https://simtreenav.example.com/api/v1"
$apiKey = "keyId.secret"
$headers = @{ Authorization = "ApiKey $apiKey" }

try {
    $uri = "$baseUrl/studies?healthScoreMin=70&sort=-healthScore"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    $resp.data | Select-Object studyId, name, healthScore
} catch {
    Write-Error ("API request failed: {0}" -f $_.Exception.Message)
}
```

Python:
```python
import requests

base_url = "https://simtreenav.example.com/api/v1"
api_key = "keyId.secret"
headers = {"Authorization": f"ApiKey {api_key}"}

try:
    resp = requests.get(
        f"{base_url}/studies",
        params={"healthScoreMin": 70, "sort": "-healthScore"},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    for study in resp.json()["data"]:
        print(study["studyId"], study["name"], study["healthScore"])
except requests.RequestException as exc:
    print(f"API request failed: {exc}")
```

### Subscribe to webhooks

PowerShell:
```powershell
$baseUrl = "https://simtreenav.example.com/api/v1"
$apiKey = "keyId.secret"
$headers = @{ Authorization = "ApiKey $apiKey"; "Content-Type" = "application/json" }

$payload = @{
    name = "Daily Alerts"
    targetUrl = "https://hooks.example.com/simtreenav"
    events = @("study.health.changed", "study.stalled")
    secret = "shared-secret"
    active = $true
}

try {
    $resp = Invoke-RestMethod -Method Post -Uri "$baseUrl/webhooks" `
        -Headers $headers -Body ($payload | ConvertTo-Json -Depth 5) -ErrorAction Stop
    $resp
} catch {
    Write-Error ("Webhook registration failed: {0}" -f $_.Exception.Message)
}
```

Python:
```python
import requests

base_url = "https://simtreenav.example.com/api/v1"
api_key = "keyId.secret"

payload = {
    "name": "Daily Alerts",
    "targetUrl": "https://hooks.example.com/simtreenav",
    "events": ["study.health.changed", "study.stalled"],
    "secret": "shared-secret",
    "active": True,
}

resp = requests.post(
    f"{base_url}/webhooks",
    json=payload,
    headers={"Authorization": f"ApiKey {api_key}"},
    timeout=30,
)
if resp.status_code not in (200, 201):
    raise RuntimeError(f"Webhook registration failed: {resp.status_code} {resp.text}")
print(resp.json())
```

### Parse timeline data for root cause analysis

PowerShell:
```powershell
$baseUrl = "https://simtreenav.example.com/api/v1"
$apiKey = "keyId.secret"
$headers = @{ Authorization = "ApiKey $apiKey" }
$studyId = "STUDY-2189"

$uri = "$baseUrl/studies/$studyId/timeline?includeCausality=true"
$resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

$rootCause = $resp.data.events |
    Where-Object { $_.causality.rootCauseCandidate -eq $true } |
    Select-Object -First 1

if ($null -eq $rootCause) {
    $rootCause = $resp.data.events |
        Where-Object { $_.causality.parentIds.Count -eq 0 } |
        Select-Object -First 1
}

$rootCause | Select-Object eventId, eventType, summary, timestamp
```

Python:
```python
import requests

base_url = "https://simtreenav.example.com/api/v1"
api_key = "keyId.secret"
study_id = "STUDY-2189"

resp = requests.get(
    f"{base_url}/studies/{study_id}/timeline",
    params={"includeCausality": "true"},
    headers={"Authorization": f"ApiKey {api_key}"},
    timeout=30,
)
resp.raise_for_status()
events = resp.json()["data"]["events"]

root = next((e for e in events if e.get("causality", {}).get("rootCauseCandidate")), None)
if root is None:
    root = next((e for e in events if not e.get("causality", {}).get("parentIds")), None)

if root:
    print(root["eventId"], root["eventType"], root["summary"], root["timestamp"])
```

## Best Practices for API Consumers

- Cache list responses and use `updatedSince` to minimize bandwidth.
- Use pagination for large result sets; do not request `pageSize` > 500.
- Prefer time-bounded queries for activity and timeline endpoints.
- Back off on 429 and 503 responses using exponential retry and jitter.
- Validate webhook signatures and handle retries idempotently.
- Store API keys securely and rotate them regularly.
