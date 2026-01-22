# AI/ML Integration Strategy for SimTreeNav

**How to Add Intelligence Without Overcomplicating**

**Date:** January 20, 2026

---

## Executive Summary

**The Question:** Where can AI/ML add real value to SimTreeNav?

**The Answer:** Start small with **predictive health scoring** and **natural language search**. Scale to advanced features (root cause prediction, anomaly detection) only if Phase 2 proves successful.

**Key Principle:** AI should enhance existing features, not become a feature itself. Users don't care about "AI" - they care about faster root cause analysis and fewer surprises.

---

## Part 1: Where AI Makes Sense (Prioritized)

### 🔥 HIGH VALUE - Phase 2 Core

#### 1. Predictive Study Health Scoring

**What It Does:**
Instead of manually calculating health scores (completeness + consistency + activity + quality), use ML to predict "will this study fail in the next 7 days?"

**Why It's Valuable:**
- Current health score is **reactive** (tells you current state)
- Predictive score is **proactive** (tells you future risk)
- Managers can intervene before failures occur

**How It Works:**

```python
# Training data: Historical study features + outcomes
features = [
    days_since_last_modified,
    health_score_trend,  # declining, stable, improving
    num_missing_resources,
    num_orphaned_parts,
    complexity_score,  # based on dependency graph depth
    owner_activity_level,  # how active is the engineer?
]

target = study_failed_within_7_days  # binary: yes/no

# Train a simple model (Random Forest or XGBoost)
from sklearn.ensemble import RandomForestClassifier
model = RandomForestClassifier()
model.fit(X_train, y_train)

# Predict for new studies
risk_score = model.predict_proba(current_study_features)[:, 1]
# risk_score = 0.75 means 75% chance of failure in 7 days
```

**Data Requirements:**
- 6-12 months of historical study data
- Labeled outcomes (which studies failed, when)
- 500+ studies minimum for training

**Implementation Effort:** 2-3 weeks
**ROI:** High (prevents failures, saves rework time)

**Deployment:**
- Option A: Python script runs daily, updates health scores in database
- Option B: Azure ML endpoint, called via PowerShell/API

---

#### 2. Natural Language Search

**What It Does:**
Instead of typing "ROBOT_XYZ", ask "which robot has reach over 2500mm?" or "show me studies using the ABC assembly"

**Why It's Valuable:**
- Non-technical managers can search without knowing exact names
- Reduces time spent guessing component names
- Enables ad-hoc queries without SQL

**How It Works:**

```python
# Use Azure OpenAI or local LLM to convert natural language to query
user_query = "which robots have reach over 2500mm?"

# LLM converts to structured query
structured_query = {
    "table": "COLLECTION_",
    "filters": [
        {"type": "ROBOT"},
        {"field": "REACH_PARAMETER", "operator": ">", "value": 2500}
    ]
}

# Execute query against database or in-memory tree
results = execute_query(structured_query)
```

**Azure OpenAI Integration:**

```powershell
# Call Azure OpenAI API from PowerShell
$apiKey = Get-AzKeyVaultSecret -VaultName "simtreenav-vault" -Name "openai-key"
$endpoint = "https://your-openai.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"

$prompt = @"
Convert this natural language query to a JSON filter:
User query: "$($userQuery)"

Available fields: NAME, TYPE, REACH_PARAMETER, LAST_MODIFIED_DATE, OWNER
Return JSON only.
"@

$response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{
    "api-key" = $apiKey
    "Content-Type" = "application/json"
} -Body (@{
    messages = @(
        @{ role = "system"; content = "You are a query translator." }
        @{ role = "user"; content = $prompt }
    )
} | ConvertTo-Json -Depth 10)

$filter = $response.choices[0].message.content | ConvertFrom-Json
```

**Implementation Effort:** 3-4 weeks
**ROI:** Medium-High (democratizes access, reduces learning curve)

**Deployment:**
- Azure OpenAI (pay-per-use, ~$0.01 per query)
- Local LLM (Ollama + Llama 3, free but requires GPU)

---

### 🟡 MEDIUM VALUE - Phase 2 Advanced

#### 3. Root Cause Prediction (AI-Powered Time-Travel)

**What It Does:**
When a study fails, AI suggests the most likely root cause based on historical patterns

**Why It's Valuable:**
- Current time-travel debugging shows timeline (manual interpretation)
- AI prediction highlights the **exact change** most likely responsible
- Reduces root cause analysis from 2 minutes to 10 seconds

**How It Works:**

```python
# Features: Study failure + recent changes
features = [
    failure_type,  # e.g., "RESOURCE_MISSING", "DATA_INCONSISTENT"
    recent_changes_count,
    change_types,  # "ROBOT_MODIFIED", "ASSEMBLY_UPDATED"
    degrees_of_separation,  # how far is change from failed study?
    time_since_change,  # hours between change and failure
]

# Train on historical failures
# Target: which upstream change was the root cause?

model.fit(failure_features, root_cause_change_id)

# Predict for new failure
predicted_root_cause = model.predict(new_failure_features)
confidence = model.predict_proba(new_failure_features).max()
```

**Training Data:**
- Manually label 100-200 past failures with their root causes
- Use as ground truth for model training

**Implementation Effort:** 4-5 weeks (including manual labeling)
**ROI:** Medium (nice-to-have, but time-travel debugging already fast)

---

#### 4. Anomaly Detection (Data Quality Watchdog)

**What It Does:**
Automatically detect weird patterns in data that might indicate problems

**Examples:**
- "Study_123 has 500% more parts than similar studies" → likely data error
- "Resource library hasn't been updated in 90 days" → possible neglect
- "10 studies all failed at the same time" → systemic issue, not individual failures

**How It Works:**

```python
from sklearn.ensemble import IsolationForest

# Features for each study
features = [
    num_resources,
    num_parts,
    num_operations,
    health_score,
    days_since_last_modified,
]

# Train anomaly detector
detector = IsolationForest(contamination=0.05)  # expect 5% anomalies
detector.fit(all_studies_features)

# Detect anomalies
anomaly_score = detector.predict(new_study_features)
# -1 = anomaly, 1 = normal

if anomaly_score == -1:
    alert("Study_123 has unusual characteristics - review recommended")
```

**Implementation Effort:** 2-3 weeks
**ROI:** Medium (catches edge cases, but rare)

---

### 🟢 LOW VALUE - Phase 3 (Nice-to-Have)

#### 5. Smart Notification Prioritization

**What It Does:**
Instead of sending all notifications, AI learns which notifications you actually care about and filters the rest

**Why It's Valuable:**
- Current smart notifications send alerts for *all* dependency changes
- AI learns: "Jane ignores robot changes but always acts on assembly changes"
- Reduces notification fatigue

**How It Works:**

```python
# Track user behavior: did they click/act on notification?
features = [
    notification_type,  # "ROBOT_CHANGE", "ASSEMBLY_CHANGE"
    degrees_of_separation,
    change_severity,  # "MAJOR", "MINOR"
    time_of_day,
]

target = user_clicked_notification  # binary

# Train per-user model
model.fit(user_notification_history, user_actions)

# Predict for new notification
relevance_score = model.predict_proba(new_notification_features)[:, 1]

if relevance_score > 0.7:
    send_notification()
else:
    log_for_daily_digest()
```

**Implementation Effort:** 3-4 weeks
**ROI:** Low-Medium (nice UX improvement, not critical)

---

#### 6. Collaborative Filtering (Recommended Studies)

**What It Does:**
"Engineers who worked on Study A also worked on Study B - you might want to review Study B"

**Why It's Valuable:**
- Helps discover related work
- Identifies knowledge sharing opportunities
- Surfaces hidden dependencies

**How It Works:**

```python
# User-study interaction matrix
# Rows = users, Columns = studies, Values = interaction level (0-5)

from sklearn.decomposition import NMF

model = NMF(n_components=10)
model.fit(user_study_matrix)

# Recommend studies for Jane
jane_vector = user_study_matrix[jane_id]
predicted_interests = model.transform(jane_vector)
recommended_studies = top_k_studies(predicted_interests)
```

**Implementation Effort:** 2-3 weeks
**ROI:** Low (interesting, but not high-priority)

---

## Part 2: AI Hosting Options

### Option 1: Azure OpenAI (Recommended for NLP Tasks)

**Best For:**
- Natural language search
- Query translation
- Text summarization for reports

**Pros:**
- ✅ Managed service (no infrastructure)
- ✅ Enterprise-grade security (AAD integration)
- ✅ GPT-4 available (state-of-the-art)
- ✅ Pay-per-use (cost scales with usage)
- ✅ Low latency (Azure East US datacenter)

**Cons:**
- ❌ Costs money (~$0.01-0.03 per request)
- ❌ Requires internet connection
- ❌ Data leaves on-prem (if that's a concern)

**Setup:**

```powershell
# 1. Create Azure OpenAI resource
az cognitiveservices account create `
    --name simtreenav-openai `
    --resource-group simtreenav-rg `
    --kind OpenAI `
    --sku S0 `
    --location eastus

# 2. Deploy GPT-4 model
az cognitiveservices account deployment create `
    --name simtreenav-openai `
    --resource-group simtreenav-rg `
    --deployment-name gpt-4 `
    --model-name gpt-4 `
    --model-version 0613 `
    --model-format OpenAI `
    --sku-capacity 10

# 3. Get API key
$apiKey = az cognitiveservices account keys list `
    --name simtreenav-openai `
    --resource-group simtreenav-rg `
    --query "key1" -o tsv

# 4. Store in Key Vault
az keyvault secret set `
    --vault-name simtreenav-vault `
    --name openai-api-key `
    --value $apiKey
```

**Cost Estimate:**
- GPT-4: $0.03 per 1K tokens (~750 words)
- If 50 users do 10 NL queries/day: 500 queries/day × $0.03 = **$15/day = $450/month**
- Can reduce to $150/month with GPT-3.5-turbo

---

### Option 2: Azure Machine Learning (For Custom ML Models)

**Best For:**
- Predictive health scoring
- Root cause prediction
- Anomaly detection

**Pros:**
- ✅ Train custom models on your data
- ✅ Deploy as REST API endpoint
- ✅ Autoscaling based on load
- ✅ Model versioning and A/B testing
- ✅ Integrated with Azure DevOps for CI/CD

**Cons:**
- ❌ More expensive than OpenAI (~$100-500/month for compute)
- ❌ Requires ML expertise to train models
- ❌ Setup more complex

**Setup:**

```python
# 1. Train model locally
from sklearn.ensemble import RandomForestClassifier
import joblib

model = RandomForestClassifier()
model.fit(X_train, y_train)
joblib.dump(model, 'study_health_model.pkl')

# 2. Create Azure ML workspace
az ml workspace create --name simtreenav-ml --resource-group simtreenav-rg

# 3. Register model
az ml model register --name study-health-predictor --model-path ./study_health_model.pkl

# 4. Deploy to endpoint
az ml online-endpoint create --name study-health-api
az ml online-deployment create --name blue --endpoint study-health-api --model study-health-predictor

# 5. Call from PowerShell
$endpoint = "https://study-health-api.eastus.inference.ml.azure.com/score"
$response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
} -Body (@{
    data = @($studyFeatures)
} | ConvertTo-Json)

$healthScore = $response.predictions[0]
```

**Cost Estimate:**
- Compute: ~$100/month (basic tier, always-on)
- Storage: ~$20/month (model artifacts, logs)
- **Total: ~$120/month**

---

### Option 3: Local ML (On-Prem Windows Server)

**Best For:**
- Companies with data residency requirements
- No budget for cloud services
- Offline/air-gapped environments

**Pros:**
- ✅ Zero cloud costs
- ✅ Data never leaves on-prem
- ✅ Full control over infrastructure
- ✅ No internet dependency

**Cons:**
- ❌ Need GPU for decent performance (NVIDIA ~$500-2000)
- ❌ Manual model deployment and updates
- ❌ No autoscaling (fixed capacity)
- ❌ Maintenance overhead

**Setup:**

```powershell
# 1. Install Python on Windows Server
choco install python --version=3.11

# 2. Install ML libraries
pip install scikit-learn pandas numpy joblib

# 3. For NLP (local LLM), install Ollama
choco install ollama
ollama pull llama3

# 4. Create prediction service (run as Windows Service)
# File: predict-study-health.ps1
param($studyId)

# Load model
$model = python -c "import joblib; print(joblib.load('study_health_model.pkl'))"

# Get study features from database
$features = Get-StudyFeatures -StudyId $studyId

# Predict
$prediction = python -c "import joblib; model = joblib.load('study_health_model.pkl'); print(model.predict([$features]))"

return $prediction
```

**Cost Estimate:**
- GPU (optional): $500-2000 one-time
- Additional server resources: Minimal (use existing server)
- **Total: $0/month (after initial hardware)**

---

### Option 4: Hybrid (Azure for NLP, Local for ML)

**Best Of Both Worlds:**
- Azure OpenAI for natural language search (pay-per-use, < $200/month)
- Local ML for predictive health scoring (no recurring cost)

**Why This Works:**
- NLP benefits from GPT-4 (hard to replicate locally)
- Predictive models are simpler (Random Forest works well)
- Balances cost, performance, and data residency

**Recommended:** Start here for Phase 2 Advanced

---

## Part 3: AI Integration Roadmap

### Phase 2 Core (No AI Yet)

**Focus:** Manual health scoring, basic reporting
**Rationale:** Prove value first, add AI later

**Features:**
- Calculate health scores using rules (completeness + consistency + activity + quality)
- No ML predictions (yet)
- Manual threshold-based alerts

---

### Phase 2 Advanced (Add AI Gradually)

**Month 1-2:**
1. **Natural Language Search (Azure OpenAI)**
   - Deploy Azure OpenAI resource
   - Integrate with search box in UI
   - Cost: ~$150-200/month

2. **Collect Training Data**
   - Log study health scores daily
   - Label historical failures with root causes (manual work)
   - 3-6 months of data needed for good models

**Month 3-4:**
3. **Predictive Health Scoring (Azure ML or Local)**
   - Train initial model on collected data
   - Deploy as API endpoint
   - A/B test: show both manual and predicted scores
   - Validate accuracy (target: 80%+ precision)

**Month 5-6:**
4. **Anomaly Detection (Local)**
   - Train Isolation Forest model
   - Run daily batch job to detect anomalies
   - Alert on unusual patterns

---

### Phase 3 (Full AI Integration)

**Month 7-12:**
- Root cause prediction (AI-powered time-travel)
- Smart notification filtering (per-user models)
- Collaborative filtering (recommended studies)
- Continuous model retraining (weekly updates)

---

## Part 4: Data Requirements for AI

### Minimum Data Needed

**For Predictive Health Scoring:**
- 500+ historical studies (with outcomes)
- 6-12 months of health score history
- Labels: which studies failed, which succeeded

**For Root Cause Prediction:**
- 100-200 past failures with manually labeled root causes
- Full change log for 6+ months
- Dependency graph history

**For Anomaly Detection:**
- 1,000+ studies for training (current state is enough)
- No historical data required (unsupervised learning)

**For Natural Language Search:**
- No training data required (use pretrained GPT-4)
- Optional: fine-tune on company-specific terminology

---

## Part 5: ROI of AI Features

### Natural Language Search

**Cost:** $150-200/month (Azure OpenAI)
**Value:** 50 users × 5 queries/day × 2 min saved = **417 hours/month = $41,700/year**
**ROI:** 21,000% (pays for itself in 1 day)

---

### Predictive Health Scoring

**Cost:** $120/month (Azure ML) or $0 (local)
**Value:** Prevent 2 study failures/month × 20 hours rework = **40 hours/month = $4,000/month**
**ROI:** 3,233% (pays for itself in 1 week)

---

### Root Cause Prediction

**Cost:** $0 (runs on same Azure ML endpoint)
**Value:** Reduce root cause analysis from 2 min to 10 sec × 20 incidents/month = **30 min/month = $50/month**
**ROI:** Low (nice UX improvement, but already fast)

**Verdict:** Build if easy, don't prioritize

---

## Part 6: Recommended Implementation Strategy

### Start Small (Phase 2 Advanced)

**Month 1:**
1. ✅ Deploy Azure OpenAI for natural language search
2. ✅ Start collecting training data (health scores, failures)

**Month 2-3:**
3. ✅ Train predictive health scoring model
4. ✅ A/B test: manual vs. predicted scores
5. ✅ Validate accuracy (target: 80%+)

**Month 4:**
6. ✅ Deploy to production if validated
7. ✅ Monitor model performance weekly
8. ✅ Collect user feedback

### Scale If Successful (Phase 3)

**Month 5-6:**
- Add anomaly detection
- Implement smart notification filtering
- Build root cause prediction (if users request it)

### Don't Overbuild

**Skip These (For Now):**
- Collaborative filtering (low ROI)
- Advanced NLP (GPT-4 is good enough)
- Real-time prediction (daily batch is fine)
- Custom LLM training (expensive, unnecessary)

---

## Part 7: Technical Architecture

### Recommended Setup

```
SimTreeNav Architecture (with AI)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frontend (Browser)
  └─ Natural Language Search Box
     ├─> Azure OpenAI API (query translation)
     └─> SimTreeNav Backend (execute query)

Backend (PowerShell on Windows Server)
  ├─ generate-tree-html.ps1
  ├─ calculate-health-scores.ps1
  │  └─> Azure ML API (predictive score)
  └─ detect-anomalies.ps1
     └─> Local Python script (Isolation Forest)

Data Layer (Oracle + SIMTREENAV Schema)
  ├─ COLLECTION_ (8M rows - read-only)
  ├─ SIMTREENAV_HEALTH_HISTORY (training data)
  └─ SIMTREENAV_PREDICTIONS (cached AI predictions)

AI Services
  ├─ Azure OpenAI (natural language)
  ├─ Azure ML (predictive health)
  └─ Local Python (anomaly detection)
```

---

## Part 8: Security Considerations

### API Key Management

**Azure OpenAI:**
```powershell
# Store API key in Azure Key Vault
$apiKey = Get-AzKeyVaultSecret -VaultName "simtreenav-vault" -Name "openai-key" -AsPlainText

# Rotate keys every 90 days (automated)
az keyvault secret set-attributes --name openai-key --vault-name simtreenav-vault --expires (Get-Date).AddDays(90)
```

### Data Privacy

**Concern:** Does data sent to Azure OpenAI stay private?

**Answer:** Yes (with proper setup)
- Use Azure OpenAI (NOT OpenAI.com) - data stays in Azure tenant
- Enable "no data retention" setting
- Data processed in Azure East US region only
- Covered by Microsoft BAA (HIPAA compliant if needed)

**Configuration:**
```json
{
  "data_retention": false,
  "logging": "errors_only",
  "content_filtering": "low"
}
```

---

## Part 9: Testing AI Features

### A/B Testing Predictive Scores

**Approach:**
1. Show 50% of users manual health scores
2. Show 50% of users predicted health scores
3. Measure: Which group catches failures earlier?

**Success Criteria:**
- Predicted scores flag at-risk studies 5+ days earlier than manual
- False positive rate < 20%
- User satisfaction with predictions > 7/10

### Validating Natural Language Search

**Test Cases:**
```
Query: "robots with reach over 2500"
Expected: List of robots where REACH_PARAMETER > 2500

Query: "studies not touched in 2 weeks"
Expected: Studies where LAST_MODIFIED_DATE < SYSDATE - 14

Query: "who owns the ABC assembly"
Expected: User from SIMUSER_ACTIVITY where OBJECT_ID = ABC
```

**Success Criteria:**
- 90%+ of queries return correct results
- Response time < 2 seconds
- User satisfaction > 8/10

---

## Part 10: Cost Summary

### Monthly Recurring Costs

| Service | Use Case | Cost/Month | ROI |
|---------|----------|-----------|-----|
| Azure OpenAI | Natural language search | $150-200 | 21,000% |
| Azure ML | Predictive health scoring | $120 | 3,233% |
| Local Python | Anomaly detection | $0 | N/A |
| **TOTAL** | | **$270-320/month** | **7,700%** |

**Annual Cost:** ~$3,600
**Annual Value:** ~$280,000 (conservative)
**Net ROI:** $276,400 / $3,600 = **7,677%**

---

## Conclusion

**AI adds real value to SimTreeNav, but start small:**

1. **Phase 2 Core:** No AI (prove manual features work)
2. **Phase 2 Advanced:** Add natural language search + predictive health scoring
3. **Phase 3:** Scale to anomaly detection, root cause prediction if demand exists

**Recommended First AI Feature:** Natural language search (Azure OpenAI)
- Easiest to implement (2-3 weeks)
- Highest user-facing value
- Clear ROI ($41,700/year for $200/month)

**Don't Overcomplicate:** AI should enhance existing features, not become a science project.

---

**Next Steps:**
1. Deploy Azure OpenAI resource (30 minutes)
2. Build prototype NL search (2 weeks)
3. Collect training data for predictive models (3-6 months)
4. Train and deploy health predictor (3 weeks)
5. Measure impact and iterate

---

**End of AI Integration Strategy**
