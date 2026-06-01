# Online Login And Leaderboards

This project includes a small Netlify Functions backend for account login and online leaderboards.

## Backend

The backend lives in:

```text
netlify/functions/api.mts
```

It provides:

```text
POST /api/register
POST /api/login
POST /api/submit-score
GET  /api/leaderboards
GET  /api/leaderboard?mode=sixshot
```

User passwords are stored as salted PBKDF2 hashes. Scores are stored in Netlify Blobs.

## Local Test

Install the Netlify CLI, then run:

```powershell
npm install
netlify dev
```

The local API base URL is usually:

```text
http://localhost:8888
```

## Game Client

Open the game main menu, choose `登录/注册`, and set the server address.

For local testing use:

```text
http://localhost:8888
```

After deploying to Netlify, use your site URL, for example:

```text
https://your-site-name.netlify.app
```

When a logged-in player finishes a run, the game submits that score online. The `联机排行` page shows the top 10 scores for each mode.
