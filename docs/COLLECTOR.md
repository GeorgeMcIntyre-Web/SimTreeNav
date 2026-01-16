# Collector Agent Mode

A safe "collector agent" mode for internal environments that provides read-only database snapshots, data anonymization, and secure bundle publishing.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Configuration](#configuration)
- [Operating Modes](#operating-modes)
- [Publishing Targets](#publishing-targets)
- [Security & Least Privilege](#security--least-privilege)
- [Operational Hardening](#operational-hardening)
- [Health Monitoring](#health-monitoring)
- [Troubleshooting](#troubleshooting)

## Overview

The Collector Agent provides a secure way to extract tree structure data from Oracle databases for analysis, sharing, or archival purposes. It is designed with security as a primary concern:

- **Read-only operations**: All database transactions use `SET TRANSACTION READ ONLY`
- **Data anonymization**: Sensitive data is masked or hashed by default
- **Atomic operations**: No partial bundles are ever created or uploaded
- **Audit trails**: Structured JSON logging for all operations
- **Health monitoring**: Real-time status and metrics reporting

## Quick Start

### 1. Copy the configuration template

```powershell
Copy-Item config\collector-config.template.json config\collector.json
```

### 2. Edit the configuration

```powershell
notepad config\collector.json
```

Update at minimum:
- `database.tnsName` - Your Oracle TNS name
- `database.schema` - Target schema (e.g., DESIGN12)
- `output.bundlePath` - Where to save bundles

### 3. Test the configuration

```powershell
.\src\powershell\collector\Collector.ps1 -Config .\config\collector.json -Mode Test
```

### 4. Run a single snapshot

```powershell
.\src\powershell\collector\Collector.ps1 -Config .\config\collector.json -Mode Once
```

### 5. (Optional) Start continuous watch mode

```powershell
.\src\powershell\collector\Collector.ps1 -Config .\config\collector.json -Mode Watch
```

## Features

### Read-Only Snapshots

The collector extracts database structure using read-only transactions:

```sql
SET TRANSACTION READ ONLY;
SELECT /*+ READ_ONLY */ ... FROM schema.table;
```

All queries are validated to ensure they contain no DML/DDL statements.

### Data Anonymization

By default, all extracted data is anonymized before bundling:

| Field Type | Anonymization Method |
|------------|---------------------|
| Object IDs | SHA-256 hash (first 16 chars) |
| Usernames, emails | Masked (e.g., `jo****oe`) |
| Passwords, secrets | Completely redacted |
| IP addresses, hosts | Masked |

You can customize anonymization rules in the configuration file.

### Bundle Creation

Bundles are ZIP files containing:
- `snapshot.json` - The anonymized data
- `manifest.json` - Bundle metadata with checksums

Bundle naming convention:
```
bundles/<timestamp>_<label>.zip
# Example: bundles/20240116_143022_snapshot.zip
```

### Mapping Files (Optional)

For internal use, you can enable mapping file creation:

```json
"anonymization": {
  "createMapping": true
}
```

This creates a separate file that maps anonymized IDs back to originals:
```
mapping/<bundle>.map.json
```

**WARNING**: Mapping files contain sensitive data and should never be shared externally.

## Configuration

### Full Configuration Reference

```json
{
  "database": {
    "tnsName": "SIEMENS_PS_DB",    // Oracle TNS name
    "schema": "DESIGN12",           // Target schema
    "projectId": null,              // Optional: specific project
    "maxRows": 10000,               // Max rows per query
    "timeout": 300                  // Query timeout (seconds)
  },
  
  "schedule": {
    "intervalMinutes": 60,          // Watch mode interval
    "enabled": true
  },
  
  "output": {
    "bundlePath": "bundles",        // Bundle output directory
    "mappingPath": "mapping",       // Mapping files (internal)
    "healthPath": "health"          // Health reports
  },
  
  "logging": {
    "path": "logs",                 // Log directory
    "level": "INFO",                // DEBUG, INFO, WARN, ERROR, FATAL
    "maxSizeMB": 10,                // Max log file size
    "maxFiles": 10,                 // Max rotated files
    "maxAgeDays": 30                // Max log age
  },
  
  "anonymization": {
    "enabled": true,                // Enable anonymization
    "createMapping": false          // Create mapping files
  },
  
  "publishing": {
    "targets": [
      {
        "type": "local",
        "enabled": true,
        "path": "published"
      }
    ]
  }
}
```

## Operating Modes

### Once Mode

Runs a single snapshot cycle and exits:

```powershell
.\Collector.ps1 -Config config.json -Mode Once -Label "daily-backup"
```

### Watch Mode

Continuously runs snapshots at configured intervals:

```powershell
.\Collector.ps1 -Config config.json -Mode Watch
```

Press `Ctrl+C` to stop gracefully.

### Status Mode

Displays current health and metrics:

```powershell
.\Collector.ps1 -Config config.json -Mode Status
```

### Test Mode

Validates configuration without running:

```powershell
.\Collector.ps1 -Config config.json -Mode Test
```

## Publishing Targets

### Local File Share (Default)

Fully implemented. Copies bundles to a local or network path:

```json
{
  "type": "local",
  "enabled": true,
  "path": "\\\\server\\share\\bundles",
  "overwrite": false
}
```

Features:
- Atomic copy (temp file + rename)
- Checksum verification
- Automatic directory creation

### HTTP Endpoint (Stub)

Design and interface implemented, but actual HTTP calls are stubbed:

```json
{
  "type": "http",
  "enabled": false,
  "endpoint": "https://api.example.com/upload",
  "timeout": 300,
  "headers": {
    "Authorization": "Bearer ${HTTP_API_TOKEN}"
  }
}
```

To implement:
1. Use `Invoke-RestMethod` with multipart/form-data
2. Add authentication headers from secure storage
3. Implement retry with exponential backoff
4. Validate SSL certificates

### Cloudflare R2 (Design Only)

Documentation and design provided. Requires AWS.Tools.S3 module:

```json
{
  "type": "r2",
  "enabled": false,
  "bucket": "collector-bundles",
  "prefix": "bundles"
}
```

Required environment variables:
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET_NAME`

See `PublishTargets.ps1` for implementation guidance.

## Security & Least Privilege

### Database User Setup

Create a dedicated read-only user for the collector:

```sql
-- Create user
CREATE USER collector_readonly IDENTIFIED BY "<strong-password>";

-- Grant minimal permissions
GRANT CREATE SESSION TO collector_readonly;
GRANT SELECT ON design12.COLLECTION_ TO collector_readonly;
GRANT SELECT ON design12.REL_COMMON TO collector_readonly;
GRANT SELECT ON design12.CLASS_DEFINITIONS TO collector_readonly;
GRANT SELECT ON design12.DFPROJECT TO collector_readonly;

-- NO INSERT, UPDATE, DELETE, or DDL permissions
```

### File System Permissions

| Directory | Permissions | Notes |
|-----------|-------------|-------|
| `bundles/` | Write | Bundle output |
| `mapping/` | Write, Restricted | Contains sensitive mappings |
| `logs/` | Write | Structured logs |
| `health/` | Write | Health reports |
| `config/` | Read | Configuration files |

### Credential Management

- Never store passwords in configuration files
- Use the existing CredentialManager.ps1 for secure storage
- In production, use Windows Credential Manager
- Environment variables are acceptable for service accounts

### Network Security

For HTTP/R2 publishing:
- Always use HTTPS (never HTTP)
- Validate SSL certificates (don't disable verification)
- Use API tokens with minimal permissions
- Implement IP allowlisting where possible

## Operational Hardening

### Structured Logging

All operations are logged in JSON format for machine parsing:

```json
{
  "timestamp": "2024-01-16T14:30:22.123-05:00",
  "level": "INFO",
  "correlationId": "a1b2c3d4",
  "message": "Bundle created successfully",
  "host": "COLLECTOR-01",
  "user": "svc_collector",
  "pid": 12345,
  "data": {
    "bundleFile": "bundles/20240116_143022_snapshot.zip",
    "size": 1234567
  }
}
```

### Log Rotation

Automatic log rotation based on:
- **Size**: Rotate when file exceeds `maxSizeMB` (default 10MB)
- **Count**: Keep maximum `maxFiles` rotated files (default 10)
- **Age**: Delete logs older than `maxAgeDays` (default 30)

### Failure Safety

1. **Atomic writes**: All files are written to temp location first, then renamed
2. **Checksum verification**: All copies are verified with SHA-256
3. **No partial uploads**: If any step fails, the entire operation fails cleanly
4. **Graceful degradation**: Individual target failures don't stop other targets

### Retention Policies

Configure retention in the health thresholds:

```json
"health": {
  "thresholds": {
    "maxErrorRate": 0.1,
    "maxConsecutiveFailures": 3
  }
}
```

## Health Monitoring

### Health Report

A JSON health report is continuously updated at `health/health.json`:

```json
{
  "status": "Healthy",
  "timestamp": "2024-01-16T14:30:22Z",
  "uptime": {
    "days": 5,
    "hours": 3,
    "minutes": 22
  },
  "metrics": {
    "bundles": {
      "created": 125,
      "failed": 2,
      "successRate": 98.4,
      "totalSizeMB": 456.78
    },
    "publishing": {
      "successes": 123,
      "failures": 2
    }
  },
  "issues": []
}
```

### Status Values

| Status | Description |
|--------|-------------|
| `Healthy` | All systems operating normally |
| `Degraded` | Some issues but still functional |
| `Unhealthy` | Critical issues, intervention needed |

### Monitoring Integration

The health report can be consumed by:
- Monitoring systems (Prometheus, Datadog, etc.)
- Custom dashboards
- Alerting systems

Example Prometheus scrape (requires exporter):
```yaml
scrape_configs:
  - job_name: 'collector'
    static_configs:
      - targets: ['localhost:9100']
```

## Troubleshooting

### Common Issues

#### "Configuration file not found"

Ensure the config path is correct:
```powershell
# Use absolute path
.\Collector.ps1 -Config C:\collector\config.json -Mode Test
```

#### "Credential manager not found"

The collector requires the CredentialManager.ps1 module:
```powershell
# Verify module exists
Test-Path .\src\powershell\utilities\CredentialManager.ps1
```

#### "Query contains DML/DDL statements"

The collector only allows SELECT queries. Check custom queries in config.

#### "Checksum mismatch after copy"

Network or disk issues during copy. The operation is automatically retried.

#### "Collector is unhealthy"

Check the health report for specific issues:
```powershell
Get-Content health\health.json | ConvertFrom-Json | Format-List
```

### Debugging

Enable debug logging:
```json
"logging": {
  "level": "DEBUG"
}
```

View recent errors:
```powershell
Get-Content logs\collector-*.json | 
  ConvertFrom-Json | 
  Where-Object { $_.level -eq "ERROR" } | 
  Select-Object -Last 10
```

### Support

For issues:
1. Check logs in `logs/` directory
2. Check health report in `health/` directory
3. Run in Test mode to validate configuration
4. Enable DEBUG logging for detailed traces

## Non-Intrusive Defaults

The collector is designed with safe defaults:

| Setting | Default | Reason |
|---------|---------|--------|
| `anonymization.enabled` | `true` | Protect sensitive data |
| `anonymization.createMapping` | `false` | Don't create sensitive files |
| `publishing.targets[].enabled` | `false` (except local) | Explicit opt-in for external |
| `database.maxRows` | `10000` | Limit query impact |
| `logging.level` | `INFO` | Balance visibility/noise |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Collector.ps1                           │
│                   (Main Entry Point)                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│CollectorUtils │   │HealthReporter │   │StructuredLog │
│  - Snapshot   │   │  - Metrics    │   │  - JSON logs  │
│  - Anonymize  │   │  - Status     │   │  - Rotation   │
│  - Bundle     │   │  - Thresholds │   │  - Retention  │
└───────────────┘   └───────────────┘   └───────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│                    PublishTargets                          │
│  ┌─────────┐    ┌─────────────┐    ┌─────────────────┐    │
│  │  Local  │    │    HTTP     │    │       R2        │    │
│  │ (Full)  │    │   (Stub)    │    │  (Design Only)  │    │
│  └─────────┘    └─────────────┘    └─────────────────┘    │
└───────────────────────────────────────────────────────────┘
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-01-16 | Initial release |

---

**Note**: This tool is designed for internal use. Always follow your organization's data handling and security policies when using the collector.
