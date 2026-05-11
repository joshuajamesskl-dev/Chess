# ♟ ChessCraft

A full-featured chess platform built with Next.js, Supabase, and Claude AI.

## Features

- **vs AI** — Play against Stockfish at 6 difficulty levels
- **Multiplayer** — Real-time games via Supabase Realtime
- **Puzzles** — Tactical training with rated puzzles
- **Analysis Board** — Import PGN, navigate moves, engine evaluation
- **AI Coach** — Real-time hints + post-game review powered by Claude

## Setup (3 steps)

### 1. Install dependencies
```bash
npm install
```

### 2. Configure environment
Fill in `.env.local` with your keys:
```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
ANTHROPIC_API_KEY=...
```

### 3. Set up Supabase database
1. Go to [supabase.com](https://supabase.com) → create a project
2. Open **SQL Editor → New Query**
3. Paste the contents of `supabase/migration.sql`
4. Click **Run**

### 4. Run locally
```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Deploy to Vercel

```bash
npx vercel
```

Add the three env vars in Vercel's dashboard under **Settings → Environment Variables**.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Next.js 15 (App Router) + TypeScript |
| Styling | Tailwind CSS |
| Database | Supabase (PostgreSQL) |
| Auth | Supabase Auth |
| Realtime | Supabase Realtime |
| Chess Logic | chess.js |
| Board UI | react-chessboard |
| AI Engine | Stockfish (Web Worker) |
| AI Coach | Claude (Anthropic API) |
| Deployment | Vercel |

## Project Structure

```
src/
├── app/
│   ├── api/           # API routes (coach, games)
│   ├── auth/          # Login + register pages
│   ├── game/          # Play lobby + live game board
│   ├── puzzles/       # Puzzle list + solver
│   ├── analysis/      # Analysis board
│   └── coach/         # Post-game review
├── components/
│   ├── board/         # ChessBoard, MoveHistory, EvalBar
│   ├── coach/         # CoachPanel
│   └── ui/            # Button, Modal, Badge, Clock
├── hooks/
│   ├── useChessGame   # Core game state
│   ├── useStockfish   # Engine Web Worker bridge
│   ├── useRealtime    # Supabase Realtime
│   ├── useCoach       # Claude API streaming
│   └── useGameTimer   # Chess clock
├── lib/
│   ├── supabase/      # Client + server clients
│   ├── chess-utils    # Helpers
│   └── elo            # Rating calculations
└── types/             # TypeScript types + DB schema
```
