# SimTreeNav Training Presentation Outline

**Duration:** 2 hours (hands-on workshop)
**Audience:** Engineers and managers (5-30 participants)
**Format:** Live demo + hands-on practice + Q&A

---

## Pre-Workshop Preparation (Send 2 Days Before)

**Email to Participants:**

```
Subject: SimTreeNav Training Workshop - January 22, 2026

Hi Team,

You're registered for the SimTreeNav training workshop on [Date] at [Time] in [Room].

WHAT TO BRING:
✓ Your laptop (fully charged)
✓ Database credentials (you'll need to connect to Oracle)
✓ Any questions about navigating Siemens database

WHAT WE'LL COVER:
• Interactive tree navigation (find components fast)
• Search functionality (locate anything in seconds)
• User activity tracking (see who's working on what)
• Hands-on practice with real project data

OPTIONAL PRE-WORK (10 minutes):
• Read Quick-Start Guide: \\share\SimTreeNav\QuickStart.pdf
• Watch 5-minute demo video: \\share\SimTreeNav\Demo.mp4

See you there!
```

---

## Workshop Agenda

### PART 1: Introduction (15 minutes)

**Slide 1: Title Slide**
```
SimTreeNav: Simulation Management System
Interactive Tree Navigation for Siemens Process Simulation

[Your Name], [Date]
```

**Slide 2: The Problem We're Solving**
```
BEFORE SimTreeNav:
❌ 5-10 minutes to find a component (manual SQL queries)
❌ No visibility into who's working on what
❌ Constant interruptions asking for status
❌ Hours spent debugging cascading changes

AFTER SimTreeNav:
✅ 5 seconds to find any component (visual search)
✅ Real-time user activity tracking
✅ Self-service status for managers
✅ Fast root cause analysis
```

**Slide 3: What Is SimTreeNav?**
```
A web-based tree viewer for Siemens Oracle databases

• 310,000+ components organized visually
• Instant search across entire project
• User activity tracking (checked-out items)
• Works with all DESIGN1-12 schemas
• Read-only (won't change your work)
```

**Talking Points:**
- "Think of it like Windows File Explorer, but for your Siemens database"
- "If you can use Google search, you can use SimTreeNav"
- "It's a viewer, not an editor - completely safe to explore"

**Slide 4: Quick Demo (Live)**
```
[Open SimTreeNav in browser]

Show 3 things:
1. Tree navigation (expand/collapse folders)
2. Search functionality (type "ROBOT", see highlights)
3. User activity (checked-out items with owner names)

Total time: 3 minutes
```

**Demo Script:**
1. "Here's the tree viewer. See all these folders? Each one represents a component in your project."
2. "I'll search for 'ROBOT'... [type in search box]... and instantly all robot resources are highlighted."
3. "See this icon here? It shows that Jane Smith has this component checked out and modified it 2 hours ago."

---

### PART 2: Hands-On Practice - Basic Navigation (30 minutes)

**Slide 5: Exercise 1 - Opening SimTreeNav**
```
TASK: Open the tree viewer on your laptop

Option 1 (Network Share):
\\fileserver\shared\SimTreeNav\tree-viewer-DESIGN1.html

Option 2 (Web):
http://simtreenav-server:8080

Should load in 2-5 seconds
```

**Instructor Actions:**
- Walk around room, help anyone with issues
- Common problems: wrong URL, browser security warnings
- Have troubleshooting guide ready

**Success Criteria:**
- 90%+ of participants have tree loaded within 5 minutes
- If anyone stuck, pair them with successful neighbor

---

**Slide 6: Exercise 2 - Tree Navigation**
```
TASK: Navigate the tree structure

1. Find the COWL_SILL_SIDE assembly
   Hint: Look under Assemblies → Body Shop → ...

2. Expand it to see child components

3. Find a robot resource inside

Expected time: 5 minutes
```

**Instructor Demonstration:**
- Show on projector: "Click the arrow to expand"
- "Keep clicking until you find COWL_SILL_SIDE"
- "Double-click or single-click to expand/collapse"

**Debrief Questions:**
- "How many clicks did it take?"
- "How long would this take with SQL queries?" (Answer: 5-10 minutes)
- "Is this faster or slower than Siemens app?" (Answer: about the same, but more visual)

---

**Slide 7: Exercise 3 - Search Functionality**
```
TASK: Use search to find components instantly

1. Type "ROBOT" in the search box
   → How many results highlighted?

2. Clear search, try "PANEL"
   → Find all panel components

3. Search for "WELD"
   → Find weld stations and studies

Expected time: 5 minutes
```

**Instructor Tips:**
- "Search is case-insensitive - 'robot' and 'ROBOT' both work"
- "Partial matches work - 'ROB' finds 'ROBOT_XYZ_123'"
- "Clear search by clicking X or pressing Escape"

**Debrief:**
- "Who found more than 50 robot results?" (should be many hands)
- "How long did that take?" (Answer: < 5 seconds)
- "Compare to SQL query time?" (Answer: 10x faster)

---

**Slide 8: Exercise 4 - User Activity Tracking**
```
TASK: Find who's working on what

1. Look for components with a person icon 👤

2. Find something checked out by [specific user name]
   Hint: Use search + scroll

3. Check the "Last Modified" timestamp

Expected time: 5 minutes
```

**Instructor Script:**
- "The person icon means someone has this item checked out right now"
- "This is live data from the SIMUSER_ACTIVITY table"
- "Refreshed hourly, so you always see current status"

**Use Cases to Highlight:**
- **For engineers:** "Check if someone else is editing before you start work"
- **For managers:** "See team activity without interrupting anyone"
- **For debugging:** "Find out who last modified a component"

---

### PART 3: Advanced Features (20 minutes)

**Slide 9: Power User Tips**
```
TIP 1: Multi-Parent Nodes
Some components appear in multiple places (same node, different parents)
→ This is intentional - shows all relationships

TIP 2: Lazy Loading
Tree only renders what you expand (performance optimization)
→ If search misses something, expand parent folders first

TIP 3: Browser Bookmarks
Bookmark the URL for quick access
→ Add to favorites bar: "SimTreeNav - DESIGN1"

TIP 4: Keyboard Shortcuts
• F3 or Ctrl+F: Jump to search box
• Escape: Clear search
• Ctrl+Click: Open node in new context (future feature)
```

---

**Slide 10: Exercise 5 - Real-World Scenarios**
```
SCENARIO 1 (Engineers):
You need to find all assemblies using robot "KUKA_KR_500".
→ How would you use SimTreeNav?

SCENARIO 2 (Managers):
Check if anyone is working on the XYZ study right now.
→ How would you find out?

SCENARIO 3 (Debugging):
A study failed. You need to see which resources it uses.
→ How would you navigate to that information?

Work in pairs. 10 minutes.
```

**Instructor Walks Through Answers:**

**Scenario 1:**
1. Search for "KUKA_KR_500"
2. See all instances highlighted
3. Look at parent nodes to find assemblies

**Scenario 2:**
1. Search for "XYZ"
2. Find the study node
3. Check for 👤 icon and owner name

**Scenario 3:**
1. Navigate to Studies folder
2. Find the failed study
3. Expand to see resource allocations
4. Note which resources are assigned

---

### PART 4: What's Coming Next - Phase 2 (15 minutes)

**Slide 11: Phase 2 Management Dashboard**
```
[Show PHASE2-DASHBOARD-MOCKUP.html in browser]

COMING IN 4-6 WEEKS:
✓ Study timeline view (track progress over time)
✓ Health scores for all studies (0-100 quality rating)
✓ Work type breakdown (5 categories of work)
✓ Automated weekly reports (30 seconds vs. 2 hours)

BUSINESS VALUE:
• Managers see what's happening in real-time
• Proactive quality management (fix issues before review)
• Data-driven resource allocation
```

**Talking Points:**
- "This is the big value-add for managers"
- "Show me what's happening in studies over time - that's the goal"
- "Health scores automatically flag at-risk studies"

---

**Slide 12: Phase 2 Advanced Features (Future)**
```
COMING IN 8-12 WEEKS (if approved):

⏰ Time-Travel Debugging
→ Trace root cause of study failures in 2 minutes (vs. 4 hours)

🗺️ Collaborative Heat Maps
→ See where team is working, prevent duplicate effort

🔔 Smart Notifications
→ Alerts when dependent work changes (prevents cascading failures)

📊 Technical Debt Tracking
→ Automated data quality checks (orphaned parts, stale studies)
```

**Call to Action:**
- "Your feedback drives prioritization"
- "If you want these features, let us know"
- "Survey link: [URL] - takes 2 minutes"

---

### PART 5: Q&A and Feedback (30 minutes)

**Slide 13: Common Questions**
```
Q: Will this replace the Siemens application?
A: No - it's a viewer, not an editor. You still use Siemens app for actual work.

Q: Is my data safe?
A: Yes - read-only access. Can't modify database from SimTreeNav.

Q: How often is data refreshed?
A: Tree data: Daily (6 AM auto-refresh)
   User activity: Hourly cache
   Icons: Weekly

Q: Can I use this on multiple projects?
A: Yes - works with DESIGN1-12 schemas. Pick from menu.

Q: What if I find a bug?
A: Email: simtreenav-support@company.com
   Or: Submit ticket at [URL]
```

---

**Slide 14: Open Q&A**
```
Your Questions?

[Reserve 15 minutes for open discussion]
```

**Instructor Prep:**
- Have technical expert on standby for tough questions
- Take notes on feature requests
- Identify early adopters for pilot expansion

---

**Slide 15: Feedback Survey**
```
Help us improve SimTreeNav!

Survey (5 minutes):
[QR Code or URL]

Questions:
1. Rate today's training (1-10)
2. How likely are you to use SimTreeNav? (1-10)
3. What features do you want next?
4. Any concerns or issues?

THANK YOU!
```

---

### PART 6: Wrap-Up and Next Steps (10 minutes)

**Slide 16: How to Get Help**
```
SUPPORT OPTIONS:

📧 Email: simtreenav-support@company.com
📅 Office Hours: Fridays 2-3 PM in [Room]
📚 Documentation: \\share\SimTreeNav\docs\
🎥 Video Tutorials: \\share\SimTreeNav\videos\
💬 Chat: [Teams/Slack channel]

QUICK REFERENCE:
Download 1-page cheat sheet: \\share\SimTreeNav\CheatSheet.pdf
```

---

**Slide 17: Your Next Steps**
```
TODAY:
✓ Bookmark the SimTreeNav URL
✓ Try it on your real project data
✓ Complete feedback survey

THIS WEEK:
✓ Use SimTreeNav instead of SQL queries
✓ Share with teammates
✓ Report any issues or feature requests

THIS MONTH:
✓ Track your time savings
✓ Join Phase 2 beta testing (optional)
✓ Attend follow-up Q&A session (Feb 5)
```

---

**Slide 18: Thank You!**
```
Questions? Contact:
[Your Name]
[Email]
[Phone]

Documentation & Resources:
\\share\SimTreeNav\

Next Training Session:
[Date] - Phase 2 Dashboard Workshop
```

---

## Post-Workshop Follow-Up

### Send Within 24 Hours:

**Email:**

```
Subject: SimTreeNav Training - Resources & Next Steps

Hi Team,

Thanks for attending yesterday's SimTreeNav workshop!

RESOURCES:
• Presentation slides: \\share\SimTreeNav\Training-Slides.pdf
• 1-page cheat sheet: \\share\SimTreeNav\CheatSheet.pdf
• Video recording: \\share\SimTreeNav\Training-Recording.mp4

FEEDBACK SURVEY (if not completed):
[URL] - takes 5 minutes, helps us improve

QUICK LINKS:
• Tree Viewer: http://simtreenav-server:8080
• Documentation: \\share\SimTreeNav\docs\
• Support Email: simtreenav-support@company.com

NEXT SESSION:
Phase 2 Dashboard Workshop - [Date] at [Time]
(Once management reporting features are ready)

Questions? Reply to this email or drop by office hours (Fridays 2-3 PM).

Happy exploring!
```

---

## Training Materials Checklist

**Before Workshop:**
- [ ] Presentation slides (PowerPoint/PDF)
- [ ] Demo environment ready (SimTreeNav accessible)
- [ ] Test user accounts for participants
- [ ] Printed handouts (1-page cheat sheet)
- [ ] Feedback survey created (Google Forms/SurveyMonkey)
- [ ] Backup plan if tech fails (offline demo, screenshots)

**During Workshop:**
- [ ] Sign-in sheet (track attendance)
- [ ] Projector/screen tested
- [ ] Wi-Fi access for participants
- [ ] Helpers/TAs for hands-on exercises (if large group)
- [ ] Troubleshooting guide for common issues

**After Workshop:**
- [ ] Send follow-up email with resources
- [ ] Review feedback survey results
- [ ] Document questions/issues for FAQ
- [ ] Update training materials based on feedback
- [ ] Schedule follow-up sessions if needed

---

## Trainer Notes

### Pacing Tips:
- **If running behind:** Skip Exercise 4, combine Q&A with Part 4
- **If running ahead:** Add bonus exercise (e.g., "Find the most recently modified study")
- **If audience is technical:** Speed up basics, spend more time on Phase 2 advanced features
- **If audience is management:** Skip hands-on, focus on business value and Phase 2 dashboard

### Engagement Tips:
- Ask questions frequently ("Who's used SQL queries before?" → hands up)
- Call on specific people for answers (not always volunteers)
- Share real success stories ("Jane saved 30 minutes last week using this")
- Use humor (lighten technical concepts)

### Common Pitfalls:
- **Participants can't connect:** Have backup plan (pre-loaded HTML files on USB drives)
- **Search not working:** Remind users to expand parent folders first (lazy loading)
- **Browser compatibility:** Test in Edge, Chrome, Firefox beforehand
- **Data privacy concerns:** Emphasize read-only access, no data leaves network

---

## Customization Options

### For Management-Only Audience (1-hour version):

**Condensed Agenda:**
1. Introduction (10 min)
2. Live demo only - no hands-on (15 min)
3. Phase 2 dashboard mockup (20 min)
4. ROI and business value (10 min)
5. Q&A (5 min)

**Focus:** Business value, ROI, strategic vision

---

### For Technical Deep-Dive (4-hour version):

**Extended Agenda:**
- Architecture overview (how it works under the hood)
- Database schema walkthrough
- Caching system explanation
- Performance optimization techniques
- API integration possibilities (Phase 3)
- Hands-on: Setting up your own instance

**Audience:** Developers, DBAs, technical leads

---

## Success Metrics

**Training is successful if:**
- ✅ 80%+ participants complete hands-on exercises
- ✅ Average satisfaction rating 8/10 or higher
- ✅ 70%+ say "likely to use regularly"
- ✅ < 5% report technical issues during workshop
- ✅ 50%+ use SimTreeNav within 1 week post-training

---

**END OF TRAINING PRESENTATION OUTLINE**

**Total Prep Time:** 4-6 hours (slides, demo env, materials)
**Delivery Time:** 2 hours workshop
**Follow-Up Time:** 1 hour (send resources, review feedback)
