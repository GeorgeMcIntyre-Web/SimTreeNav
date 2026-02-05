# SimTreeNav – AI & Developer Reference

This file gives AI assistants and developers the context needed to work on SimTreeNav, especially database and local Oracle setup.

**Last updated:** February 5, 2026  
**Branch with local Oracle setup:** `feature/local-oracle-database-setup`

---

## 1. Project summary

- **SimTreeNav** – Navigation tree for Siemens Tecnomatix Process Simulate (eMPower), backed by Oracle.
- **Stack:** PowerShell (tree generation, DB access), HTML/JS (tree viewer), Oracle (Siemens schema).
- **Repo:** Windows-focused; Oracle 19c native install at `F:\Oracle\` is the current local setup.

---

## 2. Local Oracle database (primary dev setup)

We use a **native Windows Oracle 19c** instance for local development, not Docker.

### Quick reference

| Item | Value |
|------|--------|
| **Database** | localdb01 (SID: localdb01) |
| **Oracle home** | `F:\Oracle\WINDOWS.X64_193000_db_home` |
| **TNS name** | `ORACLE_LOCAL` |
| **Admin user** | EMP_ADMIN / EMP_ADMIN |
| **Port** | 1521 |
| **Full docs** | [docker/oracle/README.md](docker/oracle/README.md) |

### One-time setup (run as Administrator)

```powershell
cd C:\Users\George\source\repos\SimTreeNav\docker\oracle
.\create-database-cmd.bat    # 10–20 min
.\setup-siemens.bat
.\setup-tns.ps1
.\start-listener.bat
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL   # verify
```

### Daily use

```powershell
# Start listener if needed
.\docker\oracle\start-listener.bat
# Connect
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL
```

### Switching app between local and remote DB

Connection target is controlled by `config/database-target.json` (gitignored). Script:

```powershell
.\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL   # or REMOTE
```

`CredentialManager.ps1` reads this file and uses the correct TNS/connection.

---

## 3. Important paths

| Purpose | Path |
|--------|------|
| Local Oracle setup & scripts | `docker/oracle/` |
| Oracle full documentation | `docker/oracle/README.md` |
| DB target switcher | `src/powershell/database/docker/Switch-DatabaseTarget.ps1` |
| Credentials / connection helper | `src/powershell/utilities/CredentialManager.ps1` |
| TNS template (ORACLE_LOCAL etc.) | `config/tnsnames.ora.template` |
| Tree generation entry | `src/powershell/main/` (e.g. generate-tree-html.ps1, tree-viewer-launcher.ps1) |
| Docs index | `docs/README.md` |
| Oracle client/setup (historical) | `docs/README-ORACLE-SETUP.md` |

---

## 4. Database configuration (local)

- **Tablespaces:** PP_DATA_128K, PP_DATA_1M, PP_DATA_10M, PP_INDEX_128K, PP_INDEX_1M, PP_INDEX_10M, AQ_DATA, PERFSTAT_DATA (see [docker/oracle/README.md](docker/oracle/README.md)).
- **Siemens roles:** empower_admin_role, ems_access_role, schema_owner_role, aq_role, reset_tables_role, schema_migration_role, archive_project_role, data_analysis_role.
- **Data Pump dumps:** Copy `.dmp` to `F:\Oracle\admin\dump\`, then use `impdp` with `directory=DUMP_DIR` (see README).

---

## 5. Verification queries (SQL*Plus)

```sql
-- After connecting as EMP_ADMIN@ORACLE_LOCAL
SELECT instance_name, version, status, host_name FROM v$instance;
SELECT tablespace_name, status FROM dba_tablespaces WHERE tablespace_name LIKE 'PP_%' OR tablespace_name IN ('AQ_DATA', 'PERFSTAT_DATA') ORDER BY 1;
SELECT granted_role FROM user_role_privs ORDER BY 1;
EXIT;
```

---

## 6. For AI assistants

- **Database or Oracle work:** Prefer [docker/oracle/README.md](docker/oracle/README.md) for setup, troubleshooting, and scripts. This file is the high-level index.
- **Credentials:** Stored via `CredentialManager.ps1`; do not hardcode passwords. Target (LOCAL/REMOTE) comes from `config/database-target.json`.
- **Remote DB (legacy):** See `docs/README-ORACLE-SETUP.md` for Instant Client and TNS (e.g. SIEMENS_PS_DB). Local dev uses ORACLE_LOCAL.
- **Branch:** Local Oracle work lives on `feature/local-oracle-database-setup`; main setup docs are in `docker/oracle/`.

---

## 7. Key docs

- **Local Oracle (full):** [docker/oracle/README.md](docker/oracle/README.md)
- **Docs index:** [docs/README.md](docs/README.md)
- **Credentials:** [docs/CREDENTIAL-MANAGEMENT.md](docs/CREDENTIAL-MANAGEMENT.md), [docs/CREDENTIAL-SETUP-GUIDE.md](docs/CREDENTIAL-SETUP-GUIDE.md)
- **System design:** [docs/SYSTEM-ARCHITECTURE.md](docs/SYSTEM-ARCHITECTURE.md)
