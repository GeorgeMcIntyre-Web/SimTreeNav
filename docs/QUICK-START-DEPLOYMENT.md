# SimTreeNav Quick-Start Deployment Guide

**Time to Deploy:** 15-30 minutes
**Target Audience:** IT Administrators
**Prerequisites:** Windows Server/Workstation, Oracle Instant Client, 5-10 pilot users identified

---

## Overview

This guide gets SimTreeNav Phase 1 (Tree Viewer) into production in under 30 minutes.

**What You're Deploying:**
- Interactive HTML tree viewer for Siemens Process Simulation database
- 310,000+ node navigation with search functionality
- User activity tracking (who's working on what)
- Zero cost, zero new infrastructure required

---

## Pre-Flight Checklist

### ✅ Before You Start

**Required:**
- [ ] Windows Server 2016+ or Windows 10+ (any machine with Oracle access)
- [ ] Oracle Instant Client 12c+ installed
- [ ] PowerShell 5.1+ (built into Windows)
- [ ] READ access to DESIGN1-12 schemas (or specific schema to use)
- [ ] Network share or IIS for hosting HTML files (optional - can use local files)

**Nice to Have:**
- [ ] 5-10 pilot users identified and willing to test
- [ ] Manager sponsor to champion adoption
- [ ] 30 minutes of uninterrupted time

**Not Required:**
- ❌ New server hardware
- ❌ Software licenses
- ❌ Budget approval
- ❌ Complex installation process

---

## Step 1: Verify Prerequisites (5 minutes)

### Test Oracle Connectivity

Open PowerShell and run:

```powershell
# Test if Oracle Instant Client is available
sqlplus /nolog

# If you see "SQL*Plus: Release 12.x.x..." you're good!
# Type 'exit' to quit
```

**Expected Output:**
```
SQL*Plus: Release 12.2.0.1.0 Production
SQL>
```

**Troubleshooting:**
- If `sqlplus` not found → Install Oracle Instant Client
- Download from: https://www.oracle.com/database/technologies/instant-client/downloads.html
- Add to PATH: `C:\oracle\instantclient_12_2`

### Verify PowerShell Version

```powershell
$PSVersionTable.PSVersion
```

**Expected Output:**
```
Major  Minor  Build  Revision
-----  -----  -----  --------
5      1      xxxxx  xxxx
```

**Requirement:** Major version must be 5 or higher.

### Test Database Access

```powershell
# Replace with your actual connection details
$env:ORACLE_USER = "your_username"
$env:ORACLE_HOST = "your_oracle_server"
$env:ORACLE_PORT = "1521"
$env:ORACLE_SERVICE = "your_service_name"

# Test connection (will prompt for password)
echo "SELECT COUNT(*) FROM DESIGN1.COLLECTION_;" | sqlplus ${env:ORACLE_USER}@${env:ORACLE_HOST}:${env:ORACLE_PORT}/${env:ORACLE_SERVICE}
```

**Expected Output:**
```
  COUNT(*)
----------
   8000000  (or similar large number)
```

**If this works, you're ready to proceed!**

---

## Step 2: Clone/Download SimTreeNav (2 minutes)

### Option A: Using Git

```powershell
cd C:\
git clone https://github.com/your-org/SimTreeNav.git
cd SimTreeNav
```

### Option B: Download ZIP

1. Download ZIP from repository
2. Extract to `C:\SimTreeNav`
3. Open PowerShell in that directory

### Verify File Structure

```powershell
ls
```

**Expected Output:**
```
Directory: C:\SimTreeNav

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----         1/20/2026   2:00 PM                config
d-----         1/20/2026   2:00 PM                docs
d-----         1/20/2026   2:00 PM                queries
d-----         1/20/2026   2:00 PM                src
```

---

## Step 3: Configure Database Connection (5 minutes)

### Create PC Profile (Server Configuration)

Run the profile creation script:

```powershell
cd C:\SimTreeNav\src\powershell\database
.\create-pc-profile.ps1
```

**Interactive Prompts:**

```
Enter PC Name (e.g., WORKSTATION1): MYSERVER
Enter Oracle Host: oracle-prod.company.com
Enter Oracle Port [1521]: 1521
Enter Oracle Service Name: ORCL

Profile saved to: C:\SimTreeNav\config\pc-profiles\MYSERVER.json
```

**What This Does:**
- Creates a configuration file with your Oracle server details
- Stores it locally (no passwords stored here)
- Reusable for future runs

### Set Up Credentials (Secure Password Storage)

Run the credential setup script:

```powershell
.\setup-credentials.ps1
```

**Interactive Prompts:**

```
Select profile: MYSERVER
Enter username: your_db_username
Enter password: ************

Credentials stored securely using Windows DPAPI encryption.
```

**Security Notes:**
- Passwords encrypted with Windows DPAPI (tied to your Windows user account)
- Credentials stored in: `C:\SimTreeNav\config\credentials\MYSERVER_your_db_username.xml`
- Only you (or your Windows account) can decrypt them
- Safe to store in version control (encrypted)

**Production Alternative:**

For production, use Windows Credential Manager instead:

```powershell
.\setup-credentials.ps1 -UseCredentialManager
```

This stores credentials in Windows secure vault (more enterprise-friendly).

---

## Step 4: Generate Your First Tree (10 minutes)

### Run the Launcher

```powershell
cd C:\SimTreeNav\src\powershell\main
.\tree-viewer-launcher-v2.ps1
```

**Interactive Menus:**

**Menu 1: Select PC Profile**
```
Available PC Profiles:
1. MYSERVER (oracle-prod.company.com:1521/ORCL)

Select profile [1]: 1
```

**Menu 2: Select Schema**
```
Available Schemas:
1. DESIGN1
2. DESIGN2
3. DESIGN3
...
12. DESIGN12

Select schema [1]: 1
```

**Processing Output:**

```
[INFO] Connecting to oracle-prod.company.com:1521/ORCL as your_db_username...
[INFO] Connected successfully.

[INFO] Extracting icons from database...
[CACHE] Found icon cache (age: 2 hours) - using cached icons (221 items)
[INFO] Icon extraction complete (0.06 seconds)

[INFO] Querying tree structure from DESIGN1.COLLECTION_...
[PROGRESS] Processing nodes... 100000... 200000... 300000... 310203 nodes found
[INFO] Building tree relationships...
[CACHE] Found tree cache (age: 30 minutes) - using cached data
[INFO] Tree structure complete (1.2 seconds)

[INFO] Querying user activity from SIMUSER_ACTIVITY...
[INFO] Found 47 checked-out items by 8 users
[INFO] User activity complete (0.5 seconds)

[INFO] Generating HTML output...
[INFO] Writing tree-viewer-DESIGN1-20260120-140523.html (95.2 MB)
[INFO] Generation complete!

Total time: 9.3 seconds

Opening in default browser...
```

**First-Time Run:**
- Takes 60-90 seconds (no cache)
- Downloads 221 icons from database
- Queries 310,000+ nodes
- Builds relationships
- Creates cache files for future runs

**Subsequent Runs:**
- Takes 9-15 seconds (with cache)
- 87% faster than first run

### Verify Output

**Browser Opens Automatically** with the tree viewer.

**What You Should See:**
- Interactive tree with expand/collapse folders
- Search box at top
- 50-100 root nodes initially visible
- Icons next to each node
- User activity indicators (checked-out items highlighted)

**Quick Tests:**

1. **Search Test:**
   - Type "ROBOT" in search box
   - See all robot resources highlighted in tree
   - Should complete in < 1 second

2. **Expand Test:**
   - Click any folder icon to expand
   - Children load instantly (lazy loading)
   - No browser freeze or slowdown

3. **User Activity Test:**
   - Look for nodes with "👤 Checked out by: [Username]" text
   - Verify names match actual users

**If all three tests pass, deployment is successful!**

---

## Step 5: Deploy to Pilot Users (5-10 minutes)

### Option A: Network Share (Simplest)

**1. Copy HTML File to Share:**

```powershell
$htmlFile = "C:\SimTreeNav\data\output\tree-viewer-DESIGN1-*.html"
$shareFolder = "\\fileserver\shared\SimTreeNav"

Copy-Item $htmlFile $shareFolder
```

**2. Send Email to Pilot Users:**

```
Subject: SimTreeNav Tree Viewer - Pilot Test

Hi Team,

We're piloting a new tool to navigate our Siemens database visually.

To try it:
1. Open this file in your browser: \\fileserver\shared\SimTreeNav\tree-viewer-DESIGN1-20260120.html
2. Use the search box to find components
3. Click folders to expand and explore the tree

This is read-only and won't change your work. Takes 5-10 minutes to learn.

Feedback welcome!
```

**Pros:** Dead simple, no server setup
**Cons:** Large file (95 MB) loads from network share (slower)

---

### Option B: IIS Hosting (Recommended for 10+ Users)

**1. Install IIS (if not already):**

```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer
```

**2. Create IIS Site:**

```powershell
# Run as Administrator
New-Item -Path "C:\inetpub\wwwroot\simtreenav" -ItemType Directory

# Copy HTML file
Copy-Item "C:\SimTreeNav\data\output\tree-viewer-DESIGN1-*.html" "C:\inetpub\wwwroot\simtreenav\index.html"

# Create IIS site
New-Website -Name "SimTreeNav" -PhysicalPath "C:\inetpub\wwwroot\simtreenav" -Port 8080
```

**3. Test:**

Open browser: `http://localhost:8080`

**4. Share with Pilot Users:**

```
Subject: SimTreeNav Tree Viewer - Pilot Test

Hi Team,

Try our new Siemens database viewer:

URL: http://your-server-name:8080

Instructions:
1. Click the link (works in Edge, Chrome, Firefox)
2. Use search box to find components
3. Expand folders to explore the tree

Read-only tool, won't affect your work. Loads in 2-5 seconds.

Feedback welcome!
```

**Pros:** Fast loading, supports many users, professional deployment
**Cons:** Requires IIS setup (5 minutes)

---

### Option C: Scheduled Auto-Refresh (Advanced)

**For production, auto-regenerate tree daily to keep data fresh:**

Create scheduled task:

```powershell
# Create script for Task Scheduler
$scriptPath = "C:\SimTreeNav\scripts\daily-tree-refresh.ps1"

@"
# Auto-refresh tree daily
cd C:\SimTreeNav\src\powershell\main

# Generate tree for DESIGN1
.\generate-tree-html.ps1 -ProfileName "MYSERVER" -SchemaName "DESIGN1" -Username "your_username"

# Copy to IIS
Copy-Item C:\SimTreeNav\data\output\tree-viewer-DESIGN1-*.html C:\inetpub\wwwroot\simtreenav\index.html -Force

Write-Host "Tree refreshed successfully at $(Get-Date)"
"@ | Out-File $scriptPath

# Create scheduled task (runs daily at 6 AM)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $scriptPath"
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "SimTreeNav Daily Refresh" -Description "Auto-refresh SimTreeNav tree viewer"
```

**Pros:** Always up-to-date data, zero manual effort
**Cons:** Requires Windows Task Scheduler setup

---

## Step 6: Gather Feedback (1-2 Weeks)

### Success Metrics to Track

**Week 1 Pilot Goals:**

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Pilot user adoption | 80%+ try it at least once | Survey: "Did you open the tool?" |
| User satisfaction | 7/10 average rating | Survey: "Rate 1-10" |
| Search usage | 50%+ use search feature | Ask: "Did you use search?" |
| Performance | < 5 second load time | User feedback: "Was it fast?" |

### Feedback Questions

**Email/Survey to Pilot Users (End of Week 1):**

```
SimTreeNav Pilot Feedback

Thanks for testing! Quick 5-minute survey:

1. Did you open the tree viewer? [Yes/No]

2. Rate the tool (1-10, 10=best):
   - Speed/Performance: ___
   - Ease of use: ___
   - Usefulness for your work: ___

3. What did you use it for? (check all)
   [ ] Finding specific components
   [ ] Exploring project structure
   [ ] Checking who owns work items
   [ ] Understanding assembly hierarchies
   [ ] Other: ________________

4. Compared to using SQL queries or Siemens app:
   [ ] Much faster
   [ ] Somewhat faster
   [ ] About the same
   [ ] Slower

5. Would you use this regularly? [Yes/No/Maybe]

6. What's missing or could be better?
   [Free text]

7. Any other feedback?
   [Free text]
```

### Red Flags (Stop and Fix)

**If you see these, pause rollout and address:**

- < 50% of pilot users actually try it → Might need better communication or training
- Average rating < 5/10 → Major usability issues, gather detailed feedback
- Performance complaints → Check network share speed, consider IIS hosting
- "I don't see the point" feedback → Better explanation of use cases needed

### Green Lights (Expand Rollout)

**Proceed to full rollout if:**

- ✅ 70%+ pilot users try it
- ✅ Average rating 7/10 or higher
- ✅ Majority say "faster than old way"
- ✅ 60%+ would use regularly
- ✅ No major bugs or performance issues

---

## Step 7: Full Production Rollout (Week 3-4)

### Expand to All Users

**Once pilot is successful:**

1. **Announce to entire engineering team:**

```
Subject: NEW TOOL: SimTreeNav Tree Viewer - Now Available

Team,

After a successful pilot with [pilot users], we're rolling out SimTreeNav to everyone.

WHAT IT IS:
A visual, searchable tree viewer for our Siemens database. Navigate 310,000+ components in seconds instead of writing SQL queries.

ACCESS:
http://your-server-name:8080

TRAINING:
- 2-hour workshop: [Date/Time] in [Room]
- Quick-start guide: \\share\SimTreeNav\QuickStart.pdf
- Video walkthrough: \\share\SimTreeNav\Demo.mp4

WHY USE IT:
✓ Find components in 5 seconds vs. 5-10 minutes
✓ See who's working on what (live user activity)
✓ Search across entire project instantly
✓ No SQL knowledge needed

SUPPORT:
- Email: simtreenav-support@company.com
- Office Hours: Fridays 2-3 PM in [Room]

Try it today!
```

2. **Schedule Training Sessions:**

- Week 1: 2-hour hands-on workshop
- Week 2: 1-hour Q&A session
- Week 3: 30-minute "tips and tricks" session

3. **Create Self-Service Resources:**

- Quick-start PDF (1-page cheat sheet)
- Video walkthrough (5 minutes)
- FAQ document
- Support email/chat channel

### Monitor Adoption

**Track Weekly:**

| Week | Active Users | % Adoption | Average Rating | Issues Reported |
|------|-------------|------------|----------------|-----------------|
| 1    | 15          | 30%        | 8.2/10         | 2 minor         |
| 2    | 28          | 56%        | 8.5/10         | 1 minor         |
| 3    | 38          | 76%        | 8.7/10         | 0               |
| 4    | 45          | 90%        | 8.9/10         | 0               |

**Goal:** 90% adoption within 3 months

---

## Troubleshooting Common Issues

### Issue 1: "Tree loads slowly (30+ seconds)"

**Likely Causes:**
- Loading from network share (95 MB file)
- Browser caching disabled
- Antivirus scanning HTML file

**Solutions:**
1. Host on IIS instead of network share
2. Enable browser caching
3. Add `tree-viewer-*.html` to antivirus exclusions

---

### Issue 2: "Search doesn't find my component"

**Likely Causes:**
- Component not rendered yet (lazy loading)
- Typo in search term
- Component actually missing from database

**Solutions:**
1. Expand parent folders first, then search
2. Try partial name (e.g., "ROBOT" instead of "ROBOT_XYZ_123")
3. Verify component exists in database with SQL query

---

### Issue 3: "Icons not displaying (blank squares)"

**Likely Causes:**
- Icon cache corrupted
- Database BLOB extraction failed
- Browser blocking data URIs

**Solutions:**
1. Delete icon cache and regenerate:
   ```powershell
   Remove-Item C:\SimTreeNav\data\cache\icon-cache-*.json
   .\tree-viewer-launcher-v2.ps1
   ```
2. Check browser console for errors (F12 → Console tab)
3. Try different browser (Edge, Chrome, Firefox)

---

### Issue 4: "User activity not showing"

**Likely Causes:**
- SIMUSER_ACTIVITY table empty
- No checked-out items currently
- Cache stale (> 1 hour old)

**Solutions:**
1. Verify users have items checked out in Siemens app
2. Delete user activity cache:
   ```powershell
   Remove-Item C:\SimTreeNav\data\cache\user-activity-cache-*.js
   ```
3. Regenerate tree

---

### Issue 5: "Password prompts on every run"

**Likely Causes:**
- Credential storage failed
- Windows DPAPI encryption issue
- Running as different Windows user

**Solutions:**
1. Re-run credential setup:
   ```powershell
   cd C:\SimTreeNav\src\powershell\database
   .\setup-credentials.ps1 -Force
   ```
2. Use Windows Credential Manager instead:
   ```powershell
   .\setup-credentials.ps1 -UseCredentialManager
   ```
3. Verify running as same Windows user who created credentials

---

## Maintenance and Updates

### Daily Tasks (Automated)

**If using scheduled task:**
- Tree auto-refreshes at 6 AM
- Logs stored in: `C:\SimTreeNav\logs\daily-refresh.log`
- Review logs weekly for errors

### Weekly Tasks (5 minutes)

1. **Check disk space:**
   ```powershell
   Get-ChildItem C:\SimTreeNav\data\output -Recurse | Measure-Object -Property Length -Sum
   ```
   - Each tree is ~95 MB
   - Keep last 7 days (665 MB)
   - Delete older files

2. **Review user feedback:**
   - Check support email
   - Address any issues reported

3. **Monitor adoption metrics:**
   - Count active users (server logs or survey)
   - Track toward 90% goal

### Monthly Tasks (30 minutes)

1. **Performance review:**
   - Check average load time
   - Monitor cache hit rates
   - Optimize if needed

2. **User satisfaction survey:**
   - Quick 3-question email
   - Track trends

3. **Plan for Phase 2:**
   - If Phase 1 adoption > 70%, start Phase 2 planning
   - Review Phase 2 requirements with management

---

## Next Steps After Successful Rollout

### Phase 2 Planning (4-6 Weeks Out)

**Once Phase 1 achieves 70%+ adoption:**

1. **Present Phase 2 proposal to management:**
   - Use [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md)
   - Highlight ROI: $1.3M+ annual value
   - Request budget: 100-150 developer hours

2. **Gather Phase 2 requirements:**
   - Survey users: "What features do you want?"
   - Prioritize: Timeline view, health scores, work breakdown
   - Validate with managers: "Will this help you?"

3. **Allocate resources:**
   - Assign developer (internal or contractor)
   - Identify subject matter experts for testing
   - Schedule 2-hour workshop for dashboard mockup review

4. **Kickoff Phase 2 development:**
   - 4-6 week timeline
   - Weekly check-ins with stakeholders
   - Beta testing with pilot users first

---

## Success Criteria Summary

### Phase 1 Deployment Complete When:

- ✅ Tree viewer loads in < 5 seconds
- ✅ All 310,000+ nodes accessible
- ✅ Search functional and fast
- ✅ User activity tracking working
- ✅ 90% of engineers using tool within 3 months
- ✅ Average user rating 8/10 or higher
- ✅ Zero critical bugs reported
- ✅ Support process established

### Ready for Phase 2 When:

- ✅ Phase 1 adoption > 70% within 2 months
- ✅ User feedback requests management features
- ✅ Management approves Phase 2 budget
- ✅ Developer resource allocated
- ✅ No outstanding Phase 1 performance issues

---

## Contact and Support

**Project Lead:** [Your Name/Title]
**IT Contact:** [IT Admin]
**Support Email:** simtreenav-support@company.com
**Documentation:** `C:\SimTreeNav\docs\`
**Issue Tracking:** [GitHub/JIRA URL]

---

## Appendix: Command Reference

### Quick Commands

**Generate tree (DESIGN1):**
```powershell
cd C:\SimTreeNav\src\powershell\main
.\tree-viewer-launcher-v2.ps1
```

**Clear all caches (force full regeneration):**
```powershell
Remove-Item C:\SimTreeNav\data\cache\*.* -Force
```

**Check cache status:**
```powershell
Get-ChildItem C:\SimTreeNav\data\cache | Select-Object Name, Length, LastWriteTime
```

**Test database connection:**
```powershell
cd C:\SimTreeNav\src\powershell\database
.\test-connection.ps1 -ProfileName "MYSERVER" -Username "your_username"
```

**View generation logs:**
```powershell
Get-Content C:\SimTreeNav\logs\tree-generation.log -Tail 50
```

---

**END OF QUICK-START DEPLOYMENT GUIDE**

**Estimated Total Time:** 15-30 minutes for basic deployment
**Estimated Time to Full Rollout:** 3-4 weeks with training and adoption tracking

Good luck with your deployment! 🚀
