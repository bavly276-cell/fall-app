# Fall Detection App — Backend Proxy

This is a Node.js/Express backend that securely proxies requests to the Groq AI API. Your Flutter app calls this backend instead of calling Groq directly, so the Groq API key is never exposed in the app.

## Setup

### 1. Install dependencies

```bash
cd backend
npm install
```

### 2. Create `.env` file

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Then open `.env` and paste your **new** Groq API key:

```env
GROQ_API_KEY=your_new_groq_key_here
PORT=3000
NODE_ENV=development
```

### 3. Start the server

**Development (with auto-reload):**
```bash
npm run dev
```

**Production:**
```bash
npm start
```

The server will start on `http://localhost:3000`.

### 4. Test the endpoint

```bash
curl -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is fall prevention?"}'
```

Expected response:
```json
{
  "success": true,
  "reply": "Fall prevention includes...",
  "model": "llama-3.1-8b-instant"
}
```

## API Endpoints

### `GET /health`
Health check. Returns `{"status": "ok"}`.

### `POST /api/chat`
Send a chat message. 

**Request body:**
```json
{
  "message": "Your question here",
  "systemPrompt": "Optional custom system prompt",
  "model": "llama-3.1-8b-instant"
}
```

**Response:**
```json
{
  "success": true,
  "reply": "AI response here",
  "model": "llama-3.1-8b-instant"
}
```

## Deploying to the cloud

You can deploy this backend to:

- **Render** (free tier): https://render.com
- **Railway**: https://railway.app
- **Replit**: https://replit.com
- **Heroku** (paid): https://heroku.com

### Render deployment steps:

1. Push this folder to a Git repo (GitHub, GitLab, etc.).
2. Log in to Render.
3. Click **New** → **Web Service**.
4. Connect your repo.
5. Set **Build Command**: `npm install`
6. Set **Start Command**: `npm start`
7. Add environment variable `GROQ_API_KEY` with your key.
8. Deploy.

After deployment, you'll get a URL like `https://fall-detection-proxy-xxxxx.onrender.com`. Use this in your Flutter app.

## Security Notes

- The `.env` file is **never** committed to Git (see `.gitignore`).
- The Groq API key is only stored on your backend, not in the Flutter app.
- Even if someone reverse-engineers the Flutter app, they only see your backend URL, not the API key.
- Consider adding API rate limiting and authentication for production.
