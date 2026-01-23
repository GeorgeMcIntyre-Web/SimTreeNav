# Go/No-Go Gate: SimTreeNav Production

**Date**: ___________
**Approvers**: IT Ops Lead, Product Owner (PM)

## GO Criteria (Must be Met)
| Check | Criteria | Status |
| :--- | :--- | :--- |
| **Validation Exit Code** | **Must be 0**. Log file confirms "System appears ready". | [ ] |
| **Bundle Integrity** | Files at `D:\SimTreeNav` match SHA256 of release zip. | [ ] |
| **Task XMLs** | Generated in `out\ops\tasks`. Contains `<Command>pwsh.exe</Command>` and valid arguments. | [ ] |
| **Paths** | XML arguments explicitly point to `D:\SimTreeNav\scripts\...` (Checked via Select-String). | [ ] |
| **Oracle** | Config file exists. Valid credentials available in Credential Manager (or approved alt). | [ ] |
| **Logging** | Test run produced a log file in `out\logs` with current timestamp. | [ ] |

## NO-GO Common Causes (Remediation)
1. **Validation Fails (Exit 1)**
   - *Check*: PowerShell version < 7? Missing `D:\SimTreeNav\out` permissions?
   - *Fix*: Install pwsh 7, Grant "Modify" to Svc Account.
2. **Oracle Client Missing**
   - *Check*: `validate-environment` warns about `sqlplus`.
   - *Fix*: Install Oracle Instant Client and add to PATH.
3. **Task Path Mismatch**
   - *Check*: XML path is `.\scripts` instead of `D:\...`.
   - *Fix*: Re-run generation with `-HostRoot "D:\SimTreeNav"`.
4. **Connectivity Failure (Manual Run)**
   - *Check*: ORA-12154 or TNS error.
   - *Fix*: Verify `tnsnames.ora` on server matches `production.json` ServiceName.

## Decision
[ ] **GO** - Proceed to Apply Tasks
[ ] **NO-GO** - Resolving blocking issues first.

**Sign-off**:
IT Ops: ____________________
PM: ____________________
