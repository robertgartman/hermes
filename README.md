# Hermes VPS Setup Tracker (Scaleway)

This repository tracks requirements and decisions for running Hermes on a low-cost cloud VPS for a family setup.

## Project Goal

Run Hermes continuously on a cheap Scaleway VPS with **4 separate family profiles**:

- Robert
- Sofia
- Mattis
- Love

## Confirmed Requirements

| ID | Requirement | Priority | Status | Notes |
|---|---|---|---|---|
| R1 | Run Hermes on a cheap cloud VPS (Scaleway) | High | In progress | Prefer low monthly cost, always-on instance |
| R2 | Run 4 different Hermes profiles/tenants continuously | High | Confirmed | `profiles` feature supports this |
| R3 | Keep family profiles separate (no overhearing/access) | High | Partially covered | Hermes profiles isolate Hermes state, but not full OS isolation by default |
| R4 | Internet-safe exposure/security baseline | High | In progress | Must use strict auth + network controls |
| R5 | Clarify DNS need for chat access | Medium | Confirmed | Depends on frontend/channel choice |
| R6 | Track inference spend per profile while using one OpenRouter account | High | Confirmed | Valid with per-profile API keys (same account/org) |
| R7 | Enforce ongoing cost control per profile (limits + monitoring + alerts) | High | Confirmed | Same pattern: one key per profile + per-key budgets |
| R8 | Use mixed messaging channels per family member | High | Confirmed | Discord/Slack/WhatsApp split by profile |

## What Hermes Docs Confirm

### 1) Multi-profile support exists

Hermes supports multiple profiles (`hermes profile create <name>`).  
Each profile has separate:

- config
- `.env`
- memory
- sessions
- skills
- gateway state

### 2) Important isolation limitation

Docs explicitly say profiles are **not sandboxing** by themselves.  
On local backend, commands still run with the same OS user access unless additional controls are added.

### 3) API server defaults

- API server is disabled by default.
- Default bind is `127.0.0.1` (localhost).
- `API_SERVER_KEY` auth is required.

This is a good secure default.

### 4) Provider/account behavior relevant to spend tracking

- Hermes supports per-profile `.env`, so each profile can use a different `OPENROUTER_API_KEY`.
- Hermes also supports credential pools, but rotating multiple keys inside one profile can make strict per-profile spend attribution harder.
- OpenRouter supports:
  - multiple API keys under one account/organization
  - key creation with optional spend limits and reset periods
  - usage analytics filtering by API key hash
  - usage/cost returned in each completion response (`usage.cost`)

## Recommended Architecture for Your Family

To satisfy separation + safety in practice:

1. Create 4 Hermes profiles (`robert`, `sofia`, `mattis`, `love`).
2. Run each profile with:
   - its own API key
   - its own API server port
   - its own gateway credentials/tokens (if messaging integrations are used)
3. Use containerized backend (`docker`) per profile for stronger command isolation.
4. Set `terminal.home_mode: profile` per profile to avoid shared CLI identity/state.
5. Restrict allowed users per platform (`*_ALLOWED_USERS`) so only intended user can access each profile.
6. Use one dedicated OpenRouter API key per profile (same OpenRouter account), not one shared key.

## Inference Spend Tracking Strategy (Validated)

### Can we use one OpenRouter account and still track per profile?

**Yes.**  
Use one OpenRouter account (or org workspace), but create **4 separate keys** and assign one key per Hermes profile:

- `robert` profile -> OpenRouter key A
- `sofia` profile -> OpenRouter key B
- `mattis` profile -> OpenRouter key C
- `love` profile -> OpenRouter key D

This keeps billing centralized while preserving per-profile attribution.

### Recommended implementation rules

1. Put exactly one OpenRouter key in each profile's `.env`.
2. Do not share a key across profiles if spend tracking must be accurate.
3. Avoid credential-pool rotation across multiple OpenRouter keys inside the same profile if clear accounting is required.
4. Set per-key spend caps/resets in OpenRouter (daily/weekly/monthly) for safety.
5. Use OpenRouter analytics/activity filtered by key to report spend per family profile.

### If using Scaleway Generative APIs instead of OpenRouter

Scaleway docs show one API key (`SCW_SECRET_KEY`) for calling `https://api.scaleway.ai/v1`.

Practical key strategy:

- **Minimum:** one shared Scaleway AI key for all profiles.
- **Recommended (cost control):** one key per family profile (Robert/Sofia/Mattis/Love).
- **Per-model keys:** optional, only if you want separate budgets/kill-switches per model.

For your use case, **per-profile keys are the best default**. Add per-model split only if later needed.

### Concrete profile template (copy/paste)

Use the same OpenRouter account, but generate four keys and store one in each profile:

#### `~/.hermes/profiles/robert/.env`

```bash
OPENROUTER_API_KEY=or_robert_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8650
API_SERVER_KEY=hermes_robert_local_api_key
API_SERVER_MODEL_NAME=robert
```

#### `~/.hermes/profiles/sofia/.env`

```bash
OPENROUTER_API_KEY=or_sofia_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8651
API_SERVER_KEY=hermes_sofia_local_api_key
API_SERVER_MODEL_NAME=sofia
```

#### `~/.hermes/profiles/mattis/.env`

```bash
OPENROUTER_API_KEY=or_mattis_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8652
API_SERVER_KEY=hermes_mattis_local_api_key
API_SERVER_MODEL_NAME=mattis
```

#### `~/.hermes/profiles/love/.env`

```bash
OPENROUTER_API_KEY=or_love_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8653
API_SERVER_KEY=hermes_love_local_api_key
API_SERVER_MODEL_NAME=love
```

Start services:

```bash
hermes -p robert gateway
hermes -p sofia gateway
hermes -p mattis gateway
hermes -p love gateway
```

### OpenRouter key policy (recommended)

- Key names in OpenRouter UI:
  - `hermes-robert`
  - `hermes-sofia`
  - `hermes-mattis`
  - `hermes-love`
- Apply per-key spend limits (example): monthly cap per family member.
- Keep one separate management key only for reporting/administration.

### Reporting routine (weekly/monthly)

1. In OpenRouter, list API keys and record each key hash for the 4 profile keys.
2. Query analytics/activity filtered by `api_key_hash`.
3. Export totals to your household budget sheet (per profile).

Suggested cadence:

- Weekly: anomaly check (unexpected spikes)
- Monthly: budget summary by profile

Suggested report fields:

- profile name
- key hash
- date range
- total requests
- total tokens
- total cost (USD/credits)
- top models used

### Optional strict budget guardrails

- Set hard monthly limits per profile key.
- Keep a lower limit for child profiles if desired.
- Configure alerting reminder (cron or external monitor) when 70-80% of monthly limit is reached.

### Cost-control requirement (added)

Use the same per-profile key strategy not only for spend reporting, but also for spend control:

1. One inference key per family profile (never shared).
2. Per-key hard limit (monthly) at provider side.
3. Weekly anomaly review + monthly budget report.
4. Alert when usage reaches 70-80% of key limit.
5. Emergency action: disable only the over-budget key without affecting other profiles.

### VPS quick command checklist (copy/paste)

Assumes Hermes is installed and `hermes` is in PATH on your Scaleway VPS.

```bash
# 1) Create profiles
hermes profile create robert
hermes profile create sofia
hermes profile create mattis
hermes profile create love
```

```bash
# 2) Add per-profile env config (paste your real keys)
cat > ~/.hermes/profiles/robert/.env <<'EOF'
OPENROUTER_API_KEY=or_robert_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8650
API_SERVER_KEY=hermes_robert_local_api_key
API_SERVER_MODEL_NAME=robert
EOF

cat > ~/.hermes/profiles/sofia/.env <<'EOF'
OPENROUTER_API_KEY=or_sofia_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8651
API_SERVER_KEY=hermes_sofia_local_api_key
API_SERVER_MODEL_NAME=sofia
EOF

cat > ~/.hermes/profiles/mattis/.env <<'EOF'
OPENROUTER_API_KEY=or_mattis_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8652
API_SERVER_KEY=hermes_mattis_local_api_key
API_SERVER_MODEL_NAME=mattis
EOF

cat > ~/.hermes/profiles/love/.env <<'EOF'
OPENROUTER_API_KEY=or_love_key_here
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8653
API_SERVER_KEY=hermes_love_local_api_key
API_SERVER_MODEL_NAME=love
EOF
```

```bash
# 3) Lock down permissions on profile secrets
chmod 600 ~/.hermes/profiles/robert/.env
chmod 600 ~/.hermes/profiles/sofia/.env
chmod 600 ~/.hermes/profiles/mattis/.env
chmod 600 ~/.hermes/profiles/love/.env
```

```bash
# 4) Start gateways (one process per profile)
hermes -p robert gateway
hermes -p sofia gateway
hermes -p mattis gateway
hermes -p love gateway
```

```bash
# 5) Quick health checks (run in another shell)
curl -s http://127.0.0.1:8650/health
curl -s http://127.0.0.1:8651/health
curl -s http://127.0.0.1:8652/health
curl -s http://127.0.0.1:8653/health
```

```bash
# 6) Verify model endpoints with auth keys
curl -s -H "Authorization: Bearer hermes_robert_local_api_key" http://127.0.0.1:8650/v1/models
curl -s -H "Authorization: Bearer hermes_sofia_local_api_key" http://127.0.0.1:8651/v1/models
curl -s -H "Authorization: Bearer hermes_mattis_local_api_key" http://127.0.0.1:8652/v1/models
curl -s -H "Authorization: Bearer hermes_love_local_api_key" http://127.0.0.1:8653/v1/models
```

Notes:

- Keep these API servers on localhost. Expose them via reverse proxy only if needed.
- Replace placeholder keys before starting services.

### systemd auto-start for all profiles (recommended)

Create a templated systemd service so each profile starts automatically on boot.

```bash
sudo tee /etc/systemd/system/hermes-gateway@.service > /dev/null <<'EOF'
[Unit]
Description=Hermes Gateway (%i profile)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=YOUR_LINUX_USER
WorkingDirectory=/home/YOUR_LINUX_USER
ExecStart=/usr/bin/env hermes -p %i gateway
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
```

Replace `YOUR_LINUX_USER`, then enable all four:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway@robert
sudo systemctl enable --now hermes-gateway@sofia
sudo systemctl enable --now hermes-gateway@mattis
sudo systemctl enable --now hermes-gateway@love
```

Check status/logs:

```bash
systemctl status hermes-gateway@robert --no-pager
journalctl -u hermes-gateway@robert -f
```

Repeat status checks for `sofia`, `mattis`, `love` as needed.

### Alternative (weaker) method

You can use one shared key and estimate by log analysis per profile, but this is less reliable than key-level attribution.

## Security Baseline for Internet Exposure (Good Default)

1. **Do not expose Hermes directly first.**
2. Keep Hermes API bound to localhost.
3. Place a reverse proxy (Caddy/Nginx/Traefik) in front with:
   - HTTPS/TLS certificates
   - authentication layer (at minimum strong bearer key handling; ideally SSO/auth gateway)
   - rate limiting
4. Lock VPS firewall:
   - allow only `22`, `80`, `443`
   - deny direct public access to Hermes API ports (`8642+`)
5. Keep Hermes dangerous command approvals enabled (`smart` or `manual`, not `off`).
6. Keep user allowlists enabled (default deny behavior is good).
7. Store secrets only in per-profile `.env` files with strict file permissions.
8. Patch/update OS and Hermes regularly.

## EU/GDPR-focused inference contenders (independent shortlist)

Ranking was made against your priorities: **(1) pricing, (2) EU/GDPR routing/compliance, (3) latency**.
Model count was treated as secondary.

### 1) Scaleway Generative APIs

Why it ranks high:

- Docs state hosting in **European data centers**.
- OpenAI-compatible API (`base_url=https://api.scaleway.ai/v1`) fits Hermes via custom endpoint.
- Strong EU latency profile for EU users; simple serverless setup.

Tradeoff:

- Smaller ecosystem than hyperscalers.

### 2) OVHcloud AI Endpoints

Why it ranks high:

- Docs emphasize **data privacy** and state they do not store user data.
- OpenAI-compatible LLM APIs.
- Key management + usage monitoring built in; practical for per-profile cost governance.

Tradeoff:

- Catalog depth and routing features should be validated model-by-model for your exact shortlist.

### 3) AWS Bedrock (EU-constrained mode)

Why it ranks high:

- Explicit routing controls: **In-Region** and **Geographic (EU)** routing.
- Geographic EU mode keeps prompts/outputs within EU geography.
- Good operational maturity for production workloads.

Tradeoff:

- Cost can be higher than EU-native challengers depending on selected model.

### 4) Google Gemini Enterprise Agent Platform / Vertex AI (EU multi-region)

Why it ranks high:

- Multi-region endpoint `eu` is explicitly designed so ML processing stays within **EU boundary**.
- Regional + multi-region endpoint options help tune latency/compliance tradeoffs.
- Broad partner model access.

Tradeoff:

- Must avoid global endpoint when residency is required.

### 5) Azure AI Foundry (DataZone EU or regional deployments)

Why it ranks high:

- Strong privacy/compliance docs for models sold by Azure.
- Processing can stay in customer-specified geography; **DataZone (EU)** option available.
- Native enterprise controls and governance.

Tradeoff:

- Pricing may be less aggressive than pure low-cost challengers.

### Selection guardrails (important)

For **any** contender above, ensure these settings before go-live:

1. Do not use "global" routing endpoints if EU residency is mandatory.
2. Pin deployments to EU region or EU data zone only.
3. Keep one API key per family profile for both isolation and cost control.
4. Run a 7-day latency/cost bakeoff on your real prompts before final provider choice.

## Scaleway compute target for hosting Hermes

### Which product should we use for a dirt-cheap always-on Hermes host?

Use a **Scaleway Virtual Instance (Public Cloud VM)** as primary target.

Why:

- Lowest-friction always-on Linux host for Hermes + gateway processes.
- Usually cheaper and simpler for this workload than dedicated hardware.
- Works well with systemd-managed multi-profile gateways.

### What about Dedibox VPS, Serverless Containers, Elastic Metal?

- **Dedibox VPS:** valid option, but typically not the first choice for a tiny always-on Hermes host.
- **Serverless Containers:** great for stateless apps; less ideal for long-running stateful gateway/agent setup.
- **Elastic Metal:** overpowered/overpriced for low-resource family Hermes use.

### Recommended decision

Start with the **smallest stable Scaleway Virtual Instance tier** that can run:

- 4 Hermes profile gateways
- reverse proxy (if internet-facing)
- light observability/logging

Then monitor memory/CPU for a week and scale one step up only if needed.

### Concrete starter spec (recommended)

Start with:

- **2 vCPU**
- **4 GB RAM**
- **40-60 GB SSD**
- Linux (Ubuntu LTS)

This is the practical minimum for:

- 4 profile gateways always on
- occasional concurrent chats
- reverse proxy + system logs

### Budget-first fallback (only if needed)

If budget is extremely tight, you can try:

- **2 vCPU**
- **2 GB RAM**

But expect higher risk of memory pressure when multiple family users chat at once.

### Low-cost MVP starter mode (recommended first step)

Goal: get a working family setup at minimum cost before scaling up.

#### What to run

- Use **2 vCPU / 2 GB RAM** first.
- Use **messaging gateway only** (Telegram or Discord), no Open WebUI/web frontend.
- Keep Hermes API server disabled for all profiles in MVP mode.
- Keep 4 profiles, but start with one messaging platform.

#### Do we need web clients?

No.  
If family uses messaging apps (Telegram/Discord/etc), Hermes can run through the gateway only.

Desktop/CLI can be used by admin for maintenance, but is not required for family chat usage.

#### Why this is cheaper

- No reverse proxy stack for web chat.
- No TLS/domain/web app hosting overhead for frontend.
- Lower memory footprint than adding web UI services.

#### MVP profile/env pattern (messaging-first)

For each profile:

- Keep model/provider key per profile (cost tracking and control).
- Add one platform bot token per profile.
- Add allowed user ID per profile.
- Do **not** enable `API_SERVER_*` until needed.

Example (Telegram profile):

```bash
OPENROUTER_API_KEY=or_robert_key_here
TELEGRAM_BOT_TOKEN=telegram_bot_token_for_robert
TELEGRAM_ALLOWED_USERS=telegram_user_id_robert
```

#### Suggested rollout order

1. Bring up 1 profile (Robert) on messaging gateway.
2. Validate latency/cost for 3-7 days.
3. Add Sofia, Mattis, Love profiles one-by-one.
4. Enable stricter resource tier only if thresholds are exceeded.

#### Family platform assignment (confirmed)

- **Love:** Discord + WhatsApp
- **Mattis:** Discord + WhatsApp
- **Robert:** Slack + WhatsApp
- **Sofia:** WhatsApp

#### Credential implications for this setup

Each profile must have:

1. One inference key (`OPENROUTER_API_KEY` or Scaleway key equivalent)
2. Platform credentials only for that profile's channels
3. Per-platform allowed user controls

Per profile, this means:

- **Love profile:** Discord token + WhatsApp token/session + allowed user IDs
- **Mattis profile:** Discord token + WhatsApp token/session + allowed user IDs
- **Robert profile:** Slack credentials + WhatsApp token/session + allowed user IDs
- **Sofia profile:** WhatsApp token/session + allowed user IDs

Important:

- Keep platform bot/app credentials separate per profile.
- Do not reuse the same token across profiles (Hermes token-lock safety exists, but separation is cleaner and safer).

### Upgrade trigger thresholds

Scale up one tier when any condition is consistently true (for 24-48h):

1. **RAM usage > 80%** average, or frequent OOM/restarts.
2. **CPU usage > 70%** average during normal family usage windows.
3. p95 chat response latency degrades by **> 40%** versus your first-week baseline.
4. Systemd restarts of Hermes profile services occur repeatedly (excluding deploy/reboot events).

### Next tier after starter

Upgrade target:

- **4 vCPU**
- **8 GB RAM**

Keep disk similar unless logs/artifacts grow quickly.

## Scaleway API scaffolding strategy (recommended)

Yes — there are good API-driven ways to scaffold this deployment.

### What Scaleway gives you

1. **Instances API**: create/list/delete VMs programmatically.
2. **Cloud-init support**: inject first-boot automation via instance `user-data` (`cloud-init` key).
3. **Instance templates**: immutable reusable server blueprints (type/image/network/tags/cloud-init).
4. **IAM API keys + policies**: least-privilege API access for automation users/apps.
5. **Secret Manager**: store sensitive values securely (instead of hardcoding in repo).
6. **Scaleway CLI (`scw`)**: scriptable provisioning and lifecycle operations from terminal/CI.

### Best deployment pattern for your case

Use a **2-layer approach**:

#### Layer A — Infrastructure scaffolding (one-time / occasional)

- Provision the VM via Scaleway API/CLI (or Terraform).
- Use cloud-init to bootstrap base host:
  - OS updates
  - Docker (optional)
  - Hermes install
  - systemd unit template
- Optionally capture as an Instance template for repeatable rebuilds.

#### Layer B — Runtime configuration (frequent updates)

- Keep per-profile secrets on the VPS (or pull from Secret Manager at deploy time).
- Generate/update per-profile `.env` files.
- Restart only affected `systemd` profile service.

This keeps automation strong while keeping runtime secrets off Git.

### Should this be GitHub Agents workflow?

- **Use GitHub workflow for provisioning/updates only** (optional).
- **Do not run Hermes gateway runtime inside GitHub Actions**.
- Runtime belongs on the VPS as `systemd` services.

### Minimal secure automation baseline

1. Create an IAM **application** for automation.
2. Grant least-privilege policy (instance + networking + secret read, if used).
3. Create short-lived/rotated API key for that app.
4. Store API key in GitHub Actions secrets (if CI is used).
5. Never commit profile tokens/keys to repo.

### Ready-to-use deployment artifacts in this repo

You now have two concrete files:

- `deploy/cloud-init-hermes-mvp.yaml`
- `deploy/deploy-hermes-mvp.sh`

#### What they do

- `cloud-init-hermes-mvp.yaml` bootstraps a fresh Ubuntu VM (updates + Hermes install helper).
- `deploy-hermes-mvp.sh` creates the 4 profiles, writes per-profile `.env` placeholders, installs a `systemd` template, and enables all 4 gateway services.

#### Deploy flow (Scaleway + VPS)

1. Create a low-cost Ubuntu VM on Scaleway Virtual Instance and attach `deploy/cloud-init-hermes-mvp.yaml` as cloud-init user-data.
2. SSH to the VM and copy the deploy script:

```bash
scp deploy/deploy-hermes-mvp.sh root@YOUR_SERVER_IP:/root/
ssh root@YOUR_SERVER_IP
chmod +x /root/deploy-hermes-mvp.sh
DEPLOY_USER=root /root/deploy-hermes-mvp.sh
```

3. Run per-profile setup to add real channel credentials and allowed-user settings:

```bash
hermes -p robert setup
hermes -p sofia setup
hermes -p mattis setup
hermes -p love setup
```

4. Restart and verify services:

```bash
systemctl restart hermes-gateway@robert hermes-gateway@sofia hermes-gateway@mattis hermes-gateway@love
systemctl status hermes-gateway@robert --no-pager
systemctl status hermes-gateway@sofia --no-pager
systemctl status hermes-gateway@mattis --no-pager
systemctl status hermes-gateway@love --no-pager
```

5. Verify logs for each profile:

```bash
journalctl -u hermes-gateway@robert -f
```

MVP note:

- This script sets `API_SERVER_ENABLED=false` by default (messaging-only mode for lowest cost).
- If you later want Open WebUI/API access, switch to the API-enabled profile env pattern above and front with HTTPS reverse proxy.

## DNS: Do You Need It?

**Depends on how you plan to chat:**

- **Telegram/Discord/etc (polling mode):**  
  Usually **no DNS required** for basic use.

- **Webhook mode and browser-based frontend (Open WebUI over internet):**  
  **Yes, DNS is strongly recommended** so you can use a domain + valid TLS certs.

- **Local-only/private access (VPN/Tailscale):**  
  DNS optional.

## Initial Implementation Checklist

- [ ] Provision Scaleway VPS
- [ ] Harden base OS (SSH keys only, firewall, automatic updates)
- [ ] Install Hermes
- [ ] Create profiles: robert, sofia, mattis, love
- [ ] Configure per-profile `.env` and API ports
- [ ] Create 4 OpenRouter API keys (one per profile)
- [ ] Add per-key spend limits/resets in OpenRouter
- [ ] Configure per-profile allowed users
- [ ] Choose frontend/channel (Telegram, Discord, Open WebUI, etc.)
- [ ] Configure reverse proxy + TLS (if internet-facing web access is needed)
- [ ] Configure systemd auto-start for all 4 profile gateways
- [ ] Validate profile separation with end-to-end tests

## Open Decisions

1. Which chat channel do you want first?
   - Telegram
   - Discord
   - Open WebUI (web app)
2. Do you want strictest isolation (separate container/runtime per profile) or lighter setup?
3. Should internet access be public domain + HTTPS, or private-only via VPN/Tailscale?
