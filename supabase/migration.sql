-- ============================================================
-- CHESS PLATFORM — FULL SCHEMA MIGRATION v1
-- Run this entire file in: Supabase → SQL Editor → New Query
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ============================================================
-- PROFILES
-- ============================================================
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  username text unique not null,
  avatar_url text,
  elo_blitz int not null default 1200,
  elo_rapid int not null default 1200,
  elo_bullet int not null default 1200,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profiles are viewable by everyone"
  on public.profiles for select using (true);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- GAMES
-- ============================================================
create table public.games (
  id uuid primary key default gen_random_uuid(),
  white_player_id uuid references public.profiles(id),
  black_player_id uuid references public.profiles(id),
  fen text not null default 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  pgn text not null default '',
  time_control text not null default '10+0',
  status text not null default 'waiting'
    check (status in ('waiting','ongoing','checkmate','draw','resigned','abandoned')),
  winner_id uuid references public.profiles(id),
  is_vs_ai bool not null default false,
  ai_difficulty int check (ai_difficulty between 1 and 20),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

alter table public.games enable row level security;

create policy "Players can view their own games"
  on public.games for select
  using (
    auth.uid() = white_player_id or
    auth.uid() = black_player_id
  );

create policy "Players can update their own games"
  on public.games for update
  using (
    auth.uid() = white_player_id or
    auth.uid() = black_player_id
  );

create policy "Authenticated users can create games"
  on public.games for insert
  with check (auth.role() = 'authenticated');

-- ============================================================
-- MOVES
-- ============================================================
create table public.moves (
  id uuid primary key default gen_random_uuid(),
  game_id uuid references public.games(id) on delete cascade not null,
  player_id uuid references public.profiles(id) not null,
  move_san text not null,
  fen_after text not null,
  eval_score float,
  classification text check (
    classification in ('brilliant','great','good','inaccuracy','mistake','blunder')
  ),
  move_number int not null,
  played_at timestamptz not null default now()
);

alter table public.moves enable row level security;

create policy "Players can view moves for their games"
  on public.moves for select
  using (
    exists (
      select 1 from public.games g
      where g.id = game_id
      and (g.white_player_id = auth.uid() or g.black_player_id = auth.uid())
    )
  );

create policy "Players can insert their own moves"
  on public.moves for insert
  with check (auth.uid() = player_id);

-- ============================================================
-- PUZZLES
-- ============================================================
create table public.puzzles (
  id uuid primary key default gen_random_uuid(),
  fen text not null,
  solution_moves text[] not null,
  themes text[] not null default '{}',
  difficulty int not null default 1200,
  source text
);

alter table public.puzzles enable row level security;

create policy "Puzzles are viewable by everyone"
  on public.puzzles for select using (true);

-- ============================================================
-- PUZZLE ATTEMPTS
-- ============================================================
create table public.puzzle_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  puzzle_id uuid references public.puzzles(id) on delete cascade not null,
  solved bool not null default false,
  time_taken_ms int,
  attempted_at timestamptz not null default now()
);

alter table public.puzzle_attempts enable row level security;

create policy "Users can view own puzzle attempts"
  on public.puzzle_attempts for select
  using (auth.uid() = user_id);

create policy "Users can insert own puzzle attempts"
  on public.puzzle_attempts for insert
  with check (auth.uid() = user_id);

-- ============================================================
-- COACH SESSIONS
-- ============================================================
create table public.coach_sessions (
  id uuid primary key default gen_random_uuid(),
  game_id uuid references public.games(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  fen_at_request text not null,
  user_question text,
  claude_response text not null,
  hint_type text not null check (hint_type in ('real_time','post_game')),
  created_at timestamptz not null default now()
);

alter table public.coach_sessions enable row level security;

create policy "Users can view own coach sessions"
  on public.coach_sessions for select
  using (auth.uid() = user_id);

create policy "Users can insert own coach sessions"
  on public.coach_sessions for insert
  with check (auth.uid() = user_id);

-- ============================================================
-- ANALYSIS BOARDS
-- ============================================================
create table public.analysis_boards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  title text not null default 'Untitled Analysis',
  pgn text not null default '',
  starting_fen text,
  is_public bool not null default false,
  created_at timestamptz not null default now()
);

alter table public.analysis_boards enable row level security;

create policy "Public boards are viewable by everyone"
  on public.analysis_boards for select
  using (is_public = true or auth.uid() = user_id);

create policy "Users can manage own boards"
  on public.analysis_boards for all
  using (auth.uid() = user_id);

-- ============================================================
-- ELO UPDATE FUNCTION
-- ============================================================
create or replace function public.update_elo(
  winner uuid,
  loser uuid,
  time_ctrl text,
  is_draw bool default false
)
returns void as $$
declare
  w_elo int;
  l_elo int;
  expected_w float;
  expected_l float;
  k int := 32;
  new_w int;
  new_l int;
  col text;
begin
  col := case
    when split_part(time_ctrl, '+', 1)::int < 3 then 'elo_bullet'
    when split_part(time_ctrl, '+', 1)::int <= 5 then 'elo_blitz'
    else 'elo_rapid'
  end;

  execute format('select %I from public.profiles where id = $1', col)
    into w_elo using winner;
  execute format('select %I from public.profiles where id = $1', col)
    into l_elo using loser;

  expected_w := 1.0 / (1 + power(10, (l_elo - w_elo)::float / 400));
  expected_l := 1.0 - expected_w;

  if is_draw then
    new_w := w_elo + round(k * (0.5 - expected_w));
    new_l := l_elo + round(k * (0.5 - expected_l));
  else
    new_w := w_elo + round(k * (1.0 - expected_w));
    new_l := l_elo + round(k * (0.0 - expected_l));
  end if;

  execute format('update public.profiles set %I = $1 where id = $2', col)
    using new_w, winner;
  execute format('update public.profiles set %I = $1 where id = $2', col)
    using new_l, loser;
end;
$$ language plpgsql security definer;

-- ============================================================
-- SEED PUZZLES (10 starter puzzles)
-- ============================================================
insert into public.puzzles (fen, solution_moves, themes, difficulty) values
  ('r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
   ARRAY['f3g5','d8e7','g5f7'],
   ARRAY['fork','tactics'],
   800),
  ('r1bqkbnr/ppp2ppp/2np4/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4',
   ARRAY['f3g5','f7f6','d1h5'],
   ARRAY['attack','tactics'],
   900),
  ('8/8/8/3k4/8/3K4/8/4R3 w - - 0 1',
   ARRAY['e1e5','d5c4','e5e4'],
   ARRAY['endgame','rook'],
   700),
  ('r2qkb1r/ppp2ppp/2n1bn2/3pp3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 2 6',
   ARRAY['c4f7','e8f7','f3g5','f7g8','d1h5'],
   ARRAY['sacrifice','attack'],
   1400),
  ('6k1/5ppp/8/8/8/8/5PPP/5RK1 w - - 0 1',
   ARRAY['f1f7','g8h8','f7f8'],
   ARRAY['endgame','rook','checkmate'],
   900),
  ('r1b1k1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4',
   ARRAY['c5f2','f1f2','d8h4','f2f1','h4f2'],
   ARRAY['sacrifice','tactics','pin'],
   1600),
  ('4r1k1/pp3ppp/2p5/8/3n4/2N2Q2/PPP2PPP/4R1K1 b - - 0 1',
   ARRAY['d4f3','g2f3','e8e1'],
   ARRAY['fork','tactics','checkmate'],
   1100),
  ('8/8/1p6/8/8/1P6/8/1K1k4 w - - 0 1',
   ARRAY['b1c2','d1e2','c2d3','e2f3','d3e4'],
   ARRAY['endgame','king','opposition'],
   1000),
  ('r3k2r/ppp2ppp/2n5/3qp3/1b1P4/2NB1N2/PPP2PPP/R2QK2R w KQkq - 0 8',
   ARRAY['d3b5','d5b5','d1d8'],
   ARRAY['pin','tactics'],
   1300),
  ('8/8/8/8/8/3k4/r7/3K4 b - - 0 1',
   ARRAY['a2a1','d1d2','a1d1'],
   ARRAY['endgame','rook','checkmate'],
   800);

-- ============================================================
-- ENABLE REALTIME
-- Wrapped in DO block so re-running the migration doesn't error
-- if tables are already members of the publication.
-- ============================================================
do $$
begin
  begin
    alter publication supabase_realtime add table public.games;
  exception when others then
    null; -- already a member
  end;
  begin
    alter publication supabase_realtime add table public.moves;
  exception when others then
    null; -- already a member
  end;
end $$;
