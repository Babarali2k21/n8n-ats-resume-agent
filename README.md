# 🤖 ATS Resume Agent — n8n Automation

An end-to-end AI automation that wakes up every morning at 7 AM, scrapes fresh LinkedIn job listings, uses **Google Gemini** to tailor your resume to each job description, compiles a polished **PDF via LaTeX**, uploads it to Google Drive, deduplicates against **Supabase**, and emails you a summary with direct links — all without touching a keyboard.

> Built as a portfolio project demonstrating production-grade n8n workflow design, AI agent orchestration, and cloud-native automation.

---

## Architecture

```
Schedule Trigger (7 AM)
       │
       ▼
Workflow Config (env vars)
       │
       ▼
Google Drive ──► Google Docs API ──► Extract Resume Text
                                            │
                                            ▼
                                   Build LinkedIn Search URL
                                            │
                                            ▼
                                   Apify Actor (LinkedIn Scraper)
                                            │
                                   Poll until SUCCEEDED
                                            │
                                            ▼
                                   Parse & Filter Jobs (last 7 days)
                                            │
                                            ▼
                                   Limit to 5 Jobs
                                            │
                                            ▼
                                   Filter Duplicates (Supabase check)
                                            │
                          ┌─────────────────┘  (per job)
                          ▼
                   ATS Optimizer Agent (Gemini LLM)
                   "Tailor resume to this JD"
                          │
                          ▼
                   Merge Job + Agent Output
                          │
                    ┌─────┴──────┐
                    ▼            ▼
             Store in       Build LaTeX
             Supabase         Resume
                                │
                                ▼
                         Compile to PDF
                         (latex.ytotech.com)
                                │
                                ▼
                         Upload to Google Drive
                                │
                                ▼
                           Share PDF (public link)
                                │
                          ──────┘  (after all jobs)
                                │
                                ▼
                         Email Summary (HTML table)
                         with job links + PDF links
```

---

## Features

- **Zero-touch daily execution** — fully scheduled, no manual steps
- **AI-tailored resumes** — Gemini rewrites bullet points and summary to match each JD's keywords and tone
- **ATS-optimized output** — structured LaTeX → PDF via `moderncv`, clean formatting that passes ATS parsers
- **Deduplication** — Supabase tracks processed jobs so you never get the same resume twice
- **HTML email digest** — one email per morning with a table of companies, roles, and direct PDF links
- **Configurable** — single config node controls search query, email, Apify token, Supabase credentials

---

## Tech Stack

| Layer | Tool |
|---|---|
| Workflow Orchestration | [n8n](https://n8n.io) (self-hosted) |
| AI Agent | Google Gemini via LangChain node |
| Job Scraping | [Apify](https://apify.com) LinkedIn Jobs Actor |
| Resume Parsing | Google Docs API |
| PDF Generation | LaTeX + [latex.ytotech.com](https://latex.ytotech.com) |
| Storage | [Supabase](https://supabase.com) (PostgreSQL) |
| File Storage | Google Drive |
| Notifications | Gmail |
| Self-Hosting | Hostinger VPS + Docker |

---

## Setup

### Prerequisites

- n8n instance (self-hosted via Docker — see [Deployment](#deployment))
- Google Cloud project with Drive + Docs + Gmail OAuth credentials
- [Apify](https://apify.com) account (free tier works)
- [Supabase](https://supabase.com) project (free tier works)
- Google Gemini API key

### 1. Supabase Schema

Run this in your Supabase SQL editor:

```sql
create table jobs (
  id           bigserial primary key,
  job_url      text unique not null,
  job_title    text,
  company      text,
  processed_at timestamptz default now()
);
```

### 2. Configure the Workflow

Open the `Workflow Configuration` node and replace all placeholder values:

| Variable | Description |
|---|---|
| `resumeFileId` | Google Doc ID of your master resume |
| `jobSearchQuery` | e.g. `"AI Engineer Vienna"` |
| `userEmail` | Where to send the daily digest |
| `apifyActorId` | Default: `curious_coder~linkedin-jobs-scraper` |
| `apifyToken` | From your Apify account settings |
| `supabaseUrl` | `https://YOUR_PROJECT_ID.supabase.co` |
| `supabaseKey` | Supabase anon key |

### 3. Credentials

In n8n, create credentials for:
- `Google Drive OAuth2`
- `Gmail OAuth2`
- `Google Gemini (PaLM) API`
- `Supabase` (URL + anon key)

Then wire each credential to the corresponding node via the n8n UI.

### 4. Import the Workflow

1. In n8n, go to **Workflows → Import**
2. Upload `workflow.json`
3. Connect your credentials to each node
4. Set the workflow to **Active**

---

## Deployment

### Self-hosted on Hostinger VPS (recommended)

```bash
# 1. SSH into your VPS
ssh root@your-vps-ip

# 2. Install Docker
curl -fsSL https://get.docker.com | sh

# 3. Create n8n directory
mkdir -p ~/n8n && cd ~/n8n

# 4. Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: "3.8"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=Europe/Vienna
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF

# 5. Create .env
cat > .env << 'EOF'
DOMAIN_NAME=your-domain.com
N8N_ENCRYPTION_KEY=your-random-32-char-key
EOF

# 6. Start n8n
docker compose up -d

# 7. (Optional) Set up Nginx reverse proxy + SSL
apt install nginx certbot python3-certbot-nginx -y
certbot --nginx -d your-domain.com
```

### Cheapest viable hosting options

| Provider | Plan | Monthly Cost | Notes |
|---|---|---|---|
| Hostinger | KVM 1 | ~€3.99 | 1 vCPU, 4GB RAM — sufficient |
| Hetzner | CX11 | ~€3.79 | Best EU performance/price |
| DigitalOcean | Basic Droplet | ~$6 | Easy setup |

Supabase free tier handles this workload easily (500MB DB, 2GB bandwidth).

---

## How It Works — Step by Step

1. **7 AM trigger** fires the workflow
2. **Config node** sets all credentials and parameters in one place
3. **Resume fetch** — downloads your Google Doc resume as plain text via the Docs API
4. **LinkedIn scrape** — Apify runs the LinkedIn Jobs actor asynchronously; n8n polls every 10 seconds until `SUCCEEDED`
5. **Parse & filter** — strips HTML from job descriptions, removes listings older than 7 days, deduplicates
6. **For each new job:**
   - Supabase checks if we've already processed this URL
   - Gemini rewrites the resume tailored to that specific JD
   - LaTeX template is built from the AI output
   - `latex.ytotech.com` compiles it to PDF
   - PDF is uploaded to Google Drive and shared publicly
   - Job record is stored in Supabase
7. **Email digest** — single HTML email with a table: company, role, posted date, job link, PDF link

---

## Customisation

- **Change LLM**: swap `Google Gemini Chat Model` node for OpenAI, Anthropic, or any LangChain-compatible model
- **Change job source**: replace Apify actor with any job board API
- **Change resume format**: modify the LaTeX template in the `Build LaTeX Resume` code node
- **Change schedule**: update the `Schedule Trigger` node (cron-style)

---

## Project Structure

```
.
├── workflow.json          # n8n workflow export (import directly)
├── README.md
└── docs/
    └── architecture.png   # (optional) flow diagram
```

---

## License

MIT — use freely, attribution appreciated.

---

*Built by [Babar Ali](https://github.com/Babarali2k21) *
