# Security Policy

## Project Security Posture

SimTreeNav is designed with security as a core principle. This document outlines our security practices, vulnerability handling, and responsible disclosure process.

### Security Design Principles

1. **Defense in Depth** - Multiple layers of protection
2. **Least Privilege** - Minimal permissions required
3. **Secure by Default** - Safe defaults for all configurations
4. **No Secrets in Code** - All credentials encrypted and external

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.4.x   | :white_check_mark: |
| 0.3.x   | :white_check_mark: |
| < 0.3   | :x:                |

## Security Features

### Credential Management

SimTreeNav implements secure credential handling:

- **DEV Mode**: Windows DPAPI encryption (user-specific)
- **PROD Mode**: Windows Credential Manager (system-integrated)
- **No plaintext storage**: All passwords encrypted at rest
- **No command-line exposure**: Credentials never passed as arguments
- **Git protection**: `.gitignore` excludes all credential files

```
config/.credentials/    → DPAPI-encrypted XML files
pc-profiles.json        → Contains no credentials
credential-config.json  → Mode configuration only
```

### Database Security

- **Read-only access recommended**: No write operations required
- **Schema-level isolation**: Separate schemas for data segregation
- **Oracle TNS encryption**: Configurable connection encryption
- **Connection pooling**: Secure connection reuse

### Non-Intrusive Operations

SimTreeNav operates in a completely **read-only, non-intrusive** manner:

- ✅ **No writes to database** - Only SELECT queries
- ✅ **No schema modifications** - No DDL operations
- ✅ **No data mutations** - No INSERT/UPDATE/DELETE
- ✅ **No stored procedures** - No server-side code execution
- ✅ **No administrative operations** - No DBA-level commands
- ✅ **Local output only** - All generated files are local

This makes SimTreeNav safe for use against production databases.

## Threat Model

### Threats Mitigated

| Threat | Mitigation |
|--------|------------|
| Plaintext credential exposure | DPAPI/CredMan encryption |
| Credential theft from git | `.gitignore` protection |
| Command-line credential exposure | Secure credential retrieval |
| Database write operations | Read-only queries only |
| SQL injection | Parameterized queries |
| Unauthorized access | Per-user credential isolation |

### Residual Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Windows account compromise | Low | High | Standard Windows security practices |
| Physical machine access | Low | High | BitLocker, physical security |
| Memory dump attacks | Very Low | Medium | Runtime-only exposure |
| Oracle connection interception | Low | Medium | Configure TNS encryption |

## Reporting a Vulnerability

We take security vulnerabilities seriously. Please follow responsible disclosure practices.

### How to Report

1. **DO NOT** create a public GitHub issue for security vulnerabilities
2. **Email**: security@simtreenav.dev (or create a private security advisory)
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Any suggested fixes (optional)

### What to Expect

| Timeline | Action |
|----------|--------|
| 24 hours | Initial acknowledgment |
| 72 hours | Preliminary assessment |
| 7 days | Detailed response with remediation plan |
| 30 days | Fix released (critical vulnerabilities) |
| 90 days | Fix released (non-critical vulnerabilities) |

### Disclosure Policy

- We follow a **90-day disclosure timeline**
- Security fixes are released as patch versions
- Credit is given to reporters (unless anonymity requested)
- CVE IDs are requested for significant vulnerabilities

## Security Best Practices

### For Users

1. **Use read-only database accounts**
   ```sql
   -- Create minimal-privilege user
   CREATE USER simtreenav_reader IDENTIFIED BY <password>;
   GRANT CONNECT TO simtreenav_reader;
   GRANT SELECT ON DESIGN12.COLLECTION_ TO simtreenav_reader;
   GRANT SELECT ON DESIGN12.REL_COMMON TO simtreenav_reader;
   GRANT SELECT ON DESIGN12.CLASS_DEFINITIONS TO simtreenav_reader;
   GRANT SELECT ON DESIGN12.DF_ICONS_DATA TO simtreenav_reader;
   ```

2. **Configure TNS encryption**
   ```
   # In sqlnet.ora
   SQLNET.ENCRYPTION_CLIENT = REQUIRED
   SQLNET.ENCRYPTION_TYPES_CLIENT = (AES256)
   ```

3. **Protect configuration files**
   ```powershell
   # Verify permissions
   icacls config\.credentials
   # Should show only current user access
   ```

4. **Use PROD mode in shared environments**
   ```json
   // credential-config.json
   {
     "mode": "PROD"
   }
   ```

### For Developers

1. **Never commit credentials**
   - Pre-commit hooks verify no secrets
   - CI runs credential detection

2. **Use SecureString for passwords**
   ```powershell
   $securePassword = Read-Host -AsSecureString
   ```

3. **Validate all inputs**
   ```powershell
   param(
       [ValidatePattern('^[A-Z0-9_]+$')]
       [string]$SchemaName
   )
   ```

4. **Log securely**
   ```powershell
   # Good - log action, not data
   Write-Verbose "Connected to server: $ServerName"
   
   # Bad - never log credentials
   Write-Verbose "Password: $Password"
   ```

## Security Checklist

### Pre-Release

- [ ] No hardcoded credentials in code
- [ ] All tests pass including security tests
- [ ] PSScriptAnalyzer security rules pass
- [ ] Dependencies scanned for vulnerabilities
- [ ] Documentation updated

### Deployment

- [ ] Read-only database user configured
- [ ] Credential mode appropriate for environment
- [ ] Config files permissions verified
- [ ] TNS encryption enabled (recommended)

## Compliance

SimTreeNav is designed to support compliance requirements:

- **Data Protection**: No data leaves the local machine
- **Audit Trail**: All operations are read-only and logged
- **Access Control**: Windows-integrated authentication
- **Encryption**: At-rest and in-transit encryption options

## Security Updates

Security updates are announced through:

1. GitHub Security Advisories
2. CHANGELOG.md entries
3. Release notes

Subscribe to releases to receive security update notifications.

## Contact

- **Security issues**: security@simtreenav.dev
- **General questions**: [GitHub Discussions](https://github.com/GeorgeMcIntyre-Web/SimTreeNav/discussions)

---

Last reviewed: 2026-01-16
