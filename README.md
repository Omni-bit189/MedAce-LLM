# MedAce 🩺

A Flutter-based medical AI chat app powered by local LLMs via [Ollama](https://ollama.com), with RAG (Retrieval-Augmented Generation) using ChromaDB. Hosted privately using [Tailscale Funnel](https://tailscale.com/kb/1223/tailscale-funnel) and [Caddy](https://caddyserver.com).

Users can chat with the AI about medical topics, upload their own PDFs for the model to reference, and access the app from any device without needing a VPN.

---

## Stack

- **Frontend** — Flutter (Web + Android + iOS)
- **Backend** — Python FastAPI + LangChain
- **LLM** — Ollama (local, e.g. llama3.2)
- **Embeddings** — nomic-embed-text via Ollama
- **Vector DB** — ChromaDB (persistent for medical dataset, in-memory for user uploads)
- **Reverse Proxy** — Caddy
- **Tunneling** — Tailscale Funnel (public HTTPS without port forwarding)

---

## Prerequisites

- [Ollama](https://ollama.com) installed and running
- [Caddy](https://caddyserver.com/docs/install) installed
- [Tailscale](https://tailscale.com/download) installed with Funnel enabled
- Python 3.10+
- Flutter SDK

### Pull required Ollama models
```bash
ollama pull llama3.2
ollama pull nomic-embed-text
```

---

## Setup

### 1. Clone the repo
```bash
git clone https://github.com/YOUR_USERNAME/medace.git
cd medace
```

### 2. Set up config files from examples
Every `.example` file needs to be copied and filled in with your own values:

```bash
# Backend
cp api.py.example api.py
cp medace_rag.py.example medace_rag.py

# Caddy
cp Caddyfile.example Caddyfile

# Flutter
cp medace_api.dart.example lib/services/medace_api.dart

# Startup scripts
cp start_medace.bat.example start_medace.bat
cp stop_medace.bat.example stop_medace.bat
```

Then open each file and replace all `YOUR_*` placeholders with your actual values. See the table below:

| Placeholder | What to put |
|---|---|
| `YOUR_TAILSCALE_HOSTNAME` | Your Tailscale machine hostname (e.g. `my-pc.tail1234.ts.net`) |
| `YOUR_FLUTTER_WEB_BUILD_PATH` | Full path to your Flutter `build/web` folder |
| `YOUR_DATASET_PATH` | Full path to the folder containing your medical PDFs |
| `YOUR_CADDY_PATH` | Full path to your Caddy folder |
| `YOUR_ADMIN_USERNAME` | A username for the Ollama API basic auth |
| `YOUR_CADDY_HASHED_PASSWORD` | Run `caddy hash-password` to generate this |
| `YOUR_CERT_PATH` | Path to your Tailscale TLS cert files |

### 3. Generate Tailscale TLS certificates
```bash
tailscale cert YOUR_TAILSCALE_HOSTNAME
```

### 4. Build the medical dataset (ChromaDB)
Place your medical PDF files in `YOUR_DATASET_PATH`, then run:
```bash
python medace_rag.py
```
This creates a `chroma_db/` folder next to `api.py`. Only needs to be run once, or again when you add new PDFs.

### 5. Install Flutter dependencies
```bash
flutter pub get
```

### 6. Build the Flutter web app
```bash
flutter build web
```

---

## Running

Double-click `start_medace.bat` to start everything, or run manually:

```bash
# 1. Start Tailscale Funnel
tailscale funnel --https=443 http://localhost:8080

# 2. Start FastAPI backend
cd YOUR_DATASET_PATH
uvicorn api:app --host 127.0.0.1 --port 8000

# 3. Start Caddy
cd YOUR_CADDY_PATH
caddy run --config Caddyfile
```

Access the app at `https://YOUR_TAILSCALE_HOSTNAME` from any device — no VPN required.

To stop everything, run `stop_medace.bat`.

---

## Features

- Chat with local LLMs (llama3.2, medllama2, etc.)
- RAG over a persistent medical PDF dataset
- Upload your own PDFs per session — processed in memory, never saved to disk
- Sources cited below each AI response
- Model selector dropdown
- Works on web, Android, and iOS

---

## Project Structure

```
medace/
├── api.py.example              # FastAPI backend
├── medace_rag.py.example       # One-time script to build ChromaDB
├── Caddyfile.example           # Caddy reverse proxy config
├── start_medace.bat.example    # Startup script
├── stop_medace.bat.example     # Shutdown script
├── lib/
│   ├── main.dart               # Flutter UI
│   └── services/
│       └── medace_api.dart.example  # API service layer
└── .gitignore
```

---

## Notes

- The `chroma_db/` folder is gitignored — each user builds their own from their own dataset
- User-uploaded PDFs are never written permanently — they live in RAM and are cleared on server restart
- Tailscale Funnel must be enabled on your Tailscale account (free tier supports it)
