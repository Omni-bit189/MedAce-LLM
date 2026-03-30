# MedAce 🩺🤖

A privacy-first, locally-hosted medical AI chat app powered by local LLMs via [Ollama](https://ollama.com). It features RAG (Retrieval-Augmented Generation) using ChromaDB for document analysis, and secure, private web searches using a local SearXNG instance.

Hosted privately using [Tailscale Funnel](https://tailscale.com/kb/1223/tailscale-funnel) and [Caddy](https://caddyserver.com), users can access the app from any device without needing a VPN, while ensuring maximum data privacy by bypassing corporate APIs.

---

## ✨ Features

- **Local AI Processing:** Chat with models like `llama3.2` and `medllama2` running entirely on your own hardware.
- **Private Web Search:** Bypasses Google/DuckDuckGo API limits by using a local SearXNG Docker container to scrape web and image results (including PubMed).
- **Medical RAG:** RAG over a persistent medical PDF dataset.
- **Dynamic File Uploads:** Upload your own PDFs per session — processed in memory, never saved to disk.
- **Stateful Chat:** Maintains conversational context and history for follow-up questions.
- **Automated Startup:** Fully automated Windows batch scripts boot up Docker, SearXNG, Tailscale funnels, Caddy, and the Python backend in a single click.
- **Cross-Platform:** Works seamlessly on web, Android, and iOS.

---

## 🛠️ Stack

- **Frontend** — Flutter (Web + Android + iOS)
- **Backend** — Python FastAPI + LangChain
- **LLM** — Ollama (local)
- **Embeddings** — nomic-embed-text via Ollama
- **Vector DB** — ChromaDB (persistent for dataset, in-memory for user uploads)
- **Search API** — SearXNG (hosted via Docker)
- **Reverse Proxy** — Caddy
- **Tunneling** — Tailscale Funnel (public HTTPS without port forwarding)

---

## 📋 Prerequisites

- [Ollama](https://ollama.com) installed and running
- [Docker Desktop](https://www.docker.com/) installed and running (Required for SearXNG)
- [Caddy](https://caddyserver.com/docs/install) installed
- [Tailscale](https://tailscale.com/download) installed with Funnel enabled
- Python 3.10+
- Flutter SDK

### Pull required Ollama models

```bash
ollama pull llama3.2
ollama pull medllama2:7b-q4_K_M
ollama pull nomic-embed-text
```

---

## 🚀 Setup

### 1. Clone the repo

```bash
git clone https://github.com/Omni-bit189/MedAce-LLM.git
cd MedAce-LLM
```

### 2. Configure SearXNG (Local Web Search)

MedAce uses a local SearXNG instance to perform web searches securely.

1. Create a folder named `searxng_data` in your project root.
2. Inside that folder, create a `settings.yml` file with the following content to enable the JSON API:

```yaml
search:
  formats:
    - html
    - json
```

### 3. Set up config files from examples

Every `.example` file needs to be copied and filled in with your own paths/values:

```bash
# Backend
cp api.py.example api.py
cp medace_rag.py.example medace_rag.py

# Caddy
cp Caddyfile.example Caddyfile

# Flutter
cp lib/services/medace_api.dart.example lib/services/medace_api.dart

# Startup scripts
cp start_medace.bat.example start_medace.bat
cp stop_medace.bat.example stop_medace.bat
```

Open each file and replace all `YOUR_*` placeholders with your actual values:

| Placeholder | What to put |
|---|---|
| `YOUR_TAILSCALE_HOSTNAME` | Your Tailscale machine hostname (e.g. `my-pc.tail1234.ts.net`) |
| `YOUR_FLUTTER_WEB_BUILD_PATH` | Full path to your Flutter `build/web` folder |
| `YOUR_DATASET_PATH` | Full path to the folder containing your medical PDFs |
| `YOUR_CADDY_PATH` | Full path to your Caddy folder |
| `YOUR_ADMIN_USERNAME` | A username for the Ollama API basic auth |
| `YOUR_CADDY_HASHED_PASSWORD` | Run `caddy hash-password` to generate this |
| `YOUR_CERT_PATH` | Path to your Tailscale TLS cert files |

### 4. Generate Tailscale TLS certificates

```bash
tailscale cert YOUR_TAILSCALE_HOSTNAME
```

### 5. Build the medical dataset (ChromaDB)

Place your medical PDF files in `YOUR_DATASET_PATH`, set up a Python virtual environment, install dependencies, and run the RAG script:

```bash
python -m venv venv
venv\Scripts\activate  # On Windows
pip install fastapi uvicorn langchain langchain-chroma langchain-ollama langchain-community pydantic python-multipart requests

python medace_rag.py
```

This creates a `chroma_db/` folder next to `api.py`. It only needs to be run once, or again when you add new PDFs.

### 6. Install Flutter dependencies & Build

```bash
flutter pub get
flutter build web
```

---

## 💻 Running MedAce

Double-click `start_medace.bat` to automatically start everything. The script will wake up Docker, launch the SearXNG container, initialize the Tailscale Funnel, start Uvicorn, and boot Caddy.

To run manually without the script:

```bash
# 1. Start Docker container for SearXNG
docker run -d --name medace-search -p 8888:8080 -v "%cd%\searxng_data\settings.yml:/etc/searxng/settings.yml" searxng/searxng

# 2. Start Tailscale Funnel
tailscale funnel --https=443 http://localhost:8080

# 3. Start FastAPI backend
cd YOUR_DATASET_PATH
uvicorn api:app --host 127.0.0.1 --port 8000

# 4. Start Caddy
cd YOUR_CADDY_PATH
caddy run --config Caddyfile
```

Access the app at `https://YOUR_TAILSCALE_HOSTNAME` from any device — no VPN required.

To cleanly stop all background services, simply run `stop_medace.bat`.

---

## 📂 Project Structure

```
MedAce/
├── api.py.example              # FastAPI backend (Search, Chat, Upload)
├── medace_rag.py.example       # One-time script to build ChromaDB
├── Caddyfile.example           # Caddy reverse proxy config
├── start_medace.bat.example    # Automated Startup script
├── stop_medace.bat.example     # Automated Shutdown script
├── searxng_data/               # Local search engine config (gitignored)
├── lib/
│   ├── main.dart               # Flutter UI (Web/Mobile)
│   └── services/
│       └── medace_api.dart.example  # API service layer
└── .gitignore
```

---

## ⚠️ Notes & Privacy

- The `chroma_db/` and `searxng_data/` folders are gitignored. Each user builds their own local databases and search instances.
- User-uploaded PDFs are never written permanently — they live securely in RAM and are cleared on server restart or manual session clear.
- Tailscale Funnel must be enabled on your Tailscale account (the free tier supports it).

> **Disclaimer:** MedAce is an AI assistant tool meant for educational, research, and organizational purposes. It is not a substitute for professional medical advice, diagnosis, or treatment.
