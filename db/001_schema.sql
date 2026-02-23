-- =============================================================================
-- VEILBORN — Supabase Database Schema
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New Query)
-- =============================================================================
-- Table creation order (respects foreign keys):
--   profiles → card_definitions → player_cards → decks → deck_cards
--   → matches → match_rounds → match_placements
--   → card_packs → pack_purchases → battle_pass → battle_pass_progress
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------------

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";


-- ---------------------------------------------------------------------------
-- 1. PROFILES
-- One row per authenticated user. Extends Supabase auth.users.
-- ---------------------------------------------------------------------------

create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  username        text unique not null,
  display_name    text not null,
  avatar_url      text,

  -- Veilweaver progression
  veilweaver_level  int not null default 1,
  total_xp          int not null default 0,

  -- Currency
  shards          int not null default 100,   -- free currency (earned in game)
  crystals        int not null default 0,     -- premium currency (purchased)

  -- Match stats (denormalized for fast leaderboard queries)
  matches_played  int not null default 0,
  matches_won     int not null default 0,
  win_streak      int not null default 0,
  best_win_streak int not null default 0,
  elo_rating      int not null default 1000,

  -- Timestamps
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint username_length check (char_length(username) between 3 and 24),
  constraint shards_non_negative check (shards >= 0),
  constraint crystals_non_negative check (crystals >= 0),
  constraint elo_positive check (elo_rating > 0)
);

comment on table public.profiles is 'Player profiles. One per auth.users row.';

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'Veilweaver_' || substr(new.id::text, 1, 6)),
    coalesce(new.raw_user_meta_data->>'display_name', 'New Veilweaver')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Auto-update updated_at
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- 2. CARD DEFINITIONS
-- The master card registry. Seeded by admin, never modified by players.
-- Matches engine/models.py CardDefinition exactly.
-- ---------------------------------------------------------------------------

create type public.card_type as enum ('Specter', 'Revenant', 'Phantom', 'Behemoth');
create type public.card_rarity as enum ('Common', 'Rare', 'Epic', 'Legendary');
create type public.ability_trigger as enum ('on_attack', 'on_death', 'on_survive_round', 'passive');
create type public.ability_effect as enum ('lifesteal', 'thorns', 'last_stand', 'ghost_step', 'veil_echo', 'armor');

create table public.card_definitions (
  id              text primary key,           -- e.g. 'spec_001' (matches engine)
  name            text not null unique,
  card_type       public.card_type not null,
  rarity          public.card_rarity not null,

  -- Base stats (level 1)
  base_attack     int not null check (base_attack between 1 and 20),
  base_defense    int not null check (base_defense between 1 and 30),
  speed           int not null check (speed between 1 and 10),
  mana_cost       int not null check (mana_cost between 1 and 7),

  -- Ability (nullable — some cards have none)
  ability_trigger  public.ability_trigger,
  ability_effect   public.ability_effect,
  ability_value    numeric(4,2),               -- e.g. 0.30, 2.00
  ability_desc     text,

  -- Flavor
  lore            text not null default '',
  art_url         text not null default '',

  -- Pack weight (higher = more common in packs)
  -- Common=100, Rare=40, Epic=15, Legendary=5
  pack_weight     int not null default 100,

  -- Admin only
  is_active       boolean not null default true,
  released_at     timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

comment on table public.card_definitions is 'Master card registry. Admin-seeded, read-only for players.';
comment on column public.card_definitions.pack_weight is 'Relative probability weight in pack draws. Higher = more likely.';


-- ---------------------------------------------------------------------------
-- 3. PLAYER CARDS
-- Every card a player owns. One row per copy (players can own multiples).
-- Matches engine/models.py CardInstance.
-- ---------------------------------------------------------------------------

create table public.player_cards (
  id                  uuid primary key default uuid_generate_v4(),
  player_id           uuid not null references public.profiles(id) on delete cascade,
  card_definition_id  text not null references public.card_definitions(id),

  -- Progression (persistent between matches)
  level               int not null default 1 check (level between 1 and 5),
  xp                  int not null default 0 check (xp >= 0),

  -- State
  consecutive_losses  int not null default 0 check (consecutive_losses >= 0),
  is_dormant          boolean not null default false,
  dormant_until       timestamptz,              -- null = not dormant

  -- Acquisition
  acquired_via        text not null default 'pack',  -- 'pack', 'starter', 'reward', 'purchase'
  acquired_at         timestamptz not null default now(),

  -- Index hint
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.player_cards is 'Every card instance owned by a player.';

create index idx_player_cards_player_id on public.player_cards(player_id);
create index idx_player_cards_definition on public.player_cards(card_definition_id);
create index idx_player_cards_dormant on public.player_cards(player_id, is_dormant);

create trigger player_cards_updated_at
  before update on public.player_cards
  for each row execute function public.touch_updated_at();

-- Auto-clear dormancy when dormant_until passes
-- (called by a Supabase scheduled function or on read)
create or replace function public.clear_expired_dormancy()
returns void language plpgsql security definer as $$
begin
  update public.player_cards
  set is_dormant = false,
      dormant_until = null,
      consecutive_losses = 0
  where is_dormant = true
    and dormant_until is not null
    and dormant_until < now();
end;
$$;


-- ---------------------------------------------------------------------------
-- 4. DECKS
-- A player's named deck. One active deck is used in matchmaking.
-- ---------------------------------------------------------------------------

create table public.decks (
  id          uuid primary key default uuid_generate_v4(),
  player_id   uuid not null references public.profiles(id) on delete cascade,
  name        text not null default 'My Deck',
  is_active   boolean not null default false,  -- only one deck active at a time
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint deck_name_length check (char_length(name) between 1 and 40)
);

comment on table public.decks is 'Player deck collections. One active deck is used in matches.';

create index idx_decks_player_id on public.decks(player_id);
create index idx_decks_active on public.decks(player_id, is_active) where is_active = true;

create trigger decks_updated_at
  before update on public.decks
  for each row execute function public.touch_updated_at();

-- Enforce only one active deck per player
create or replace function public.enforce_single_active_deck()
returns trigger language plpgsql as $$
begin
  if new.is_active = true then
    update public.decks
    set is_active = false
    where player_id = new.player_id
      and id != new.id
      and is_active = true;
  end if;
  return new;
end;
$$;

create trigger single_active_deck
  before insert or update on public.decks
  for each row execute function public.enforce_single_active_deck();


-- ---------------------------------------------------------------------------
-- 5. DECK CARDS
-- Junction table: which player_cards are in which deck.
-- Max 10 cards per deck (enforced by trigger).
-- ---------------------------------------------------------------------------

create table public.deck_cards (
  id              uuid primary key default uuid_generate_v4(),
  deck_id         uuid not null references public.decks(id) on delete cascade,
  player_card_id  uuid not null references public.player_cards(id) on delete cascade,
  slot_order      int not null default 0,   -- display order in deck UI
  added_at        timestamptz not null default now(),

  unique(deck_id, player_card_id)           -- no duplicates in same deck
);

comment on table public.deck_cards is 'Cards in a deck. Max 10 per deck.';

create index idx_deck_cards_deck_id on public.deck_cards(deck_id);
create index idx_deck_cards_player_card on public.deck_cards(player_card_id);

-- Enforce 10-card deck limit
create or replace function public.enforce_deck_size()
returns trigger language plpgsql as $$
declare
  card_count int;
begin
  select count(*) into card_count
  from public.deck_cards
  where deck_id = new.deck_id;

  if card_count >= 10 then
    raise exception 'Deck cannot exceed 10 cards';
  end if;
  return new;
end;
$$;

create trigger deck_size_limit
  before insert on public.deck_cards
  for each row execute function public.enforce_deck_size();


-- ---------------------------------------------------------------------------
-- 6. MATCHES
-- One row per match. Links two players, tracks full game lifecycle.
-- ---------------------------------------------------------------------------

create type public.match_status as enum (
  'waiting',      -- created, waiting for opponent
  'active',       -- in progress
  'completed',    -- finished normally
  'abandoned',    -- player disconnected
  'draw'          -- rare tie condition
);

create table public.matches (
  id              uuid primary key default uuid_generate_v4(),

  -- Players
  player1_id      uuid not null references public.profiles(id),
  player2_id      uuid references public.profiles(id),  -- null until opponent joins
  winner_id       uuid references public.profiles(id),  -- null until complete

  -- Decks used (snapshot — decks can change, match record is immutable)
  player1_deck_id uuid references public.decks(id),
  player2_deck_id uuid references public.decks(id),

  -- Lifecycle
  status          public.match_status not null default 'waiting',
  current_round   int not null default 1,
  current_phase   text not null default 'draw',

  -- Score (denormalized for fast queries)
  player1_score   int not null default 0,
  player2_score   int not null default 0,

  -- ELO change (written at match completion)
  player1_elo_delta  int,
  player2_elo_delta  int,

  -- Matchmaking
  elo_bracket     int,    -- ELO at match creation, for balanced matchmaking
  is_ranked       boolean not null default true,

  -- Realtime channel (Supabase Realtime)
  realtime_channel  text unique,  -- e.g. 'match:{id}'

  -- Timestamps
  created_at      timestamptz not null default now(),
  started_at      timestamptz,
  completed_at    timestamptz,
  updated_at      timestamptz not null default now()
);

comment on table public.matches is 'One row per match. Realtime state synced here.';

create index idx_matches_player1 on public.matches(player1_id);
create index idx_matches_player2 on public.matches(player2_id);
create index idx_matches_status on public.matches(status);
create index idx_matches_waiting on public.matches(status, elo_bracket)
  where status = 'waiting';  -- fast matchmaking lookup

create trigger matches_updated_at
  before update on public.matches
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- 7. MATCH ROUNDS
-- One row per completed round. Stores the full BattleLog + DM narration.
-- Immutable once written — the permanent record of what happened.
-- ---------------------------------------------------------------------------

create table public.match_rounds (
  id              uuid primary key default uuid_generate_v4(),
  match_id        uuid not null references public.matches(id) on delete cascade,
  round_number    int not null check (round_number between 1 and 5),

  -- The complete BattleLog JSON (sent to DM agent)
  battle_log      jsonb not null,

  -- DM Agent output
  narration_title     text,
  narration_text      text,
  narration_tone      text,
  narration_key_moment text,

  -- Image agent output
  image_url           text,      -- generated and cached after round
  image_prompt        text,      -- stored for debugging / regeneration

  -- Round outcome (denormalized from battle_log for easy querying)
  round_winner_id     uuid references public.profiles(id),
  points_awarded      int not null default 0,
  veil_collapse       boolean not null default false,
  p1_surviving_defense int not null default 0,
  p2_surviving_defense int not null default 0,

  created_at      timestamptz not null default now(),

  unique(match_id, round_number)
);

comment on table public.match_rounds is 'Immutable round records. BattleLog + DM narration stored here.';

create index idx_match_rounds_match_id on public.match_rounds(match_id);


-- ---------------------------------------------------------------------------
-- 8. MATCH PLACEMENTS
-- Each card placement action during a round (for replay + audit).
-- Written during placement phase, face_down flipped at reveal.
-- ---------------------------------------------------------------------------

create table public.match_placements (
  id              uuid primary key default uuid_generate_v4(),
  match_id        uuid not null references public.matches(id) on delete cascade,
  round_number    int not null,
  player_id       uuid not null references public.profiles(id),
  player_card_id  uuid not null references public.player_cards(id),

  -- Board position
  col             int not null check (col between 0 and 3),
  row             text not null check (row in ('front', 'back')),
  face_down       boolean not null default true,
  mana_spent      int not null default 0,

  placed_at       timestamptz not null default now()
);

comment on table public.match_placements is 'Every card placement action. Used for replay and audit.';

create index idx_placements_match_round on public.match_placements(match_id, round_number);
create index idx_placements_player on public.match_placements(player_id);


-- ---------------------------------------------------------------------------
-- 9. CARD PACKS
-- Pack definitions (types of packs available in the shop).
-- ---------------------------------------------------------------------------

create table public.card_packs (
  id              text primary key,           -- e.g. 'starter_pack', 'veil_pack'
  name            text not null,
  description     text not null default '',
  cards_per_pack  int not null default 5,

  -- Cost (either shards or crystals, not both)
  shard_cost      int,
  crystal_cost    int,

  -- Guaranteed rarity (at least one card of this rarity per pack)
  guaranteed_rarity  public.card_rarity,

  -- Pack art
  art_url         text not null default '',

  is_active       boolean not null default true,
  available_from  timestamptz not null default now(),
  available_until timestamptz,    -- null = always available

  created_at      timestamptz not null default now(),

  constraint cost_required check (shard_cost is not null or crystal_cost is not null)
);

comment on table public.card_packs is 'Pack types available in the shop.';


-- ---------------------------------------------------------------------------
-- 10. PACK PURCHASES
-- Every pack opened. Stores exactly which cards were awarded.
-- Critical for auditing IAP and card economy.
-- ---------------------------------------------------------------------------

create table public.pack_purchases (
  id              uuid primary key default uuid_generate_v4(),
  player_id       uuid not null references public.profiles(id),
  pack_id         text not null references public.card_packs(id),

  -- Cards awarded (array of player_card ids created by this purchase)
  cards_awarded   uuid[] not null default '{}',

  -- Payment
  currency_type   text not null check (currency_type in ('shards', 'crystals', 'iap')),
  amount_paid     int,             -- null for IAP (handled by RevenueCat)
  revenuecat_tx   text,            -- RevenueCat transaction ID for IAP

  opened_at       timestamptz not null default now()
);

comment on table public.pack_purchases is 'Every pack opened. Auditable card economy record.';

create index idx_pack_purchases_player on public.pack_purchases(player_id);
create index idx_pack_purchases_pack on public.pack_purchases(pack_id);


-- ---------------------------------------------------------------------------
-- 11. BATTLE PASS
-- Seasonal battle pass definitions.
-- ---------------------------------------------------------------------------

create table public.battle_pass (
  id              text primary key,           -- e.g. 'season_1'
  name            text not null,
  description     text not null default '',
  season_number   int not null unique,

  -- Pricing
  crystal_cost    int not null default 500,

  -- Duration
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,

  -- Rewards (JSONB array of reward tiers)
  -- [{"tier": 1, "xp_required": 0, "reward_type": "shards", "amount": 50, "card_definition_id": null}, ...]
  reward_tiers    jsonb not null default '[]',

  created_at      timestamptz not null default now()
);

comment on table public.battle_pass is 'Seasonal battle pass configurations.';


-- ---------------------------------------------------------------------------
-- 12. BATTLE PASS PROGRESS
-- Per-player battle pass progress.
-- ---------------------------------------------------------------------------

create table public.battle_pass_progress (
  id              uuid primary key default uuid_generate_v4(),
  player_id       uuid not null references public.profiles(id) on delete cascade,
  battle_pass_id  text not null references public.battle_pass(id),

  -- Progress
  is_premium      boolean not null default false,  -- paid for premium track
  current_xp      int not null default 0,
  current_tier    int not null default 0,

  -- Claimed rewards (array of tier numbers already claimed)
  claimed_tiers   int[] not null default '{}',

  purchased_at    timestamptz,
  updated_at      timestamptz not null default now(),

  unique(player_id, battle_pass_id)
);

comment on table public.battle_pass_progress is 'Per-player battle pass progress and claimed rewards.';

create index idx_bp_progress_player on public.battle_pass_progress(player_id);

create trigger bp_progress_updated_at
  before update on public.battle_pass_progress
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- 13. MATCH QUEUE
-- Matchmaking queue. Players enter, get matched by ELO bracket.
-- ---------------------------------------------------------------------------

create table public.match_queue (
  id          uuid primary key default uuid_generate_v4(),
  player_id   uuid not null unique references public.profiles(id) on delete cascade,
  elo_rating  int not null,
  deck_id     uuid not null references public.decks(id),
  entered_at  timestamptz not null default now(),

  -- Widen ELO bracket every 30s player waits
  bracket_width  int not null default 100
);

comment on table public.match_queue is 'Matchmaking queue. One row per queued player.';

create index idx_match_queue_elo on public.match_queue(elo_rating);


-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

alter table public.profiles enable row level security;
alter table public.player_cards enable row level security;
alter table public.decks enable row level security;
alter table public.deck_cards enable row level security;
alter table public.matches enable row level security;
alter table public.match_rounds enable row level security;
alter table public.match_placements enable row level security;
alter table public.pack_purchases enable row level security;
alter table public.battle_pass_progress enable row level security;
alter table public.match_queue enable row level security;

-- card_definitions and card_packs: public read, admin write only
alter table public.card_definitions enable row level security;
alter table public.card_packs enable row level security;
alter table public.battle_pass enable row level security;

-- PROFILES
create policy "Profiles are publicly readable"
  on public.profiles for select using (true);

create policy "Players can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- CARD DEFINITIONS (public read only)
create policy "Card definitions are publicly readable"
  on public.card_definitions for select using (true);

-- CARD PACKS (public read only)
create policy "Card packs are publicly readable"
  on public.card_packs for select using (is_active = true);

-- BATTLE PASS (public read only)
create policy "Battle pass is publicly readable"
  on public.battle_pass for select using (true);

-- PLAYER CARDS
create policy "Players can read own cards"
  on public.player_cards for select using (auth.uid() = player_id);

create policy "Players can update own cards"
  on public.player_cards for update using (auth.uid() = player_id);

-- DECKS
create policy "Players can manage own decks"
  on public.decks for all using (auth.uid() = player_id);

-- DECK CARDS
create policy "Players can manage own deck cards"
  on public.deck_cards for all
  using (
    exists (
      select 1 from public.decks d
      where d.id = deck_id and d.player_id = auth.uid()
    )
  );

-- MATCHES
create policy "Players can read their own matches"
  on public.matches for select
  using (auth.uid() = player1_id or auth.uid() = player2_id);

create policy "Players can update active matches they're in"
  on public.matches for update
  using (
    (auth.uid() = player1_id or auth.uid() = player2_id)
    and status = 'active'
  );

-- MATCH ROUNDS (both players can read rounds of their matches)
create policy "Match participants can read rounds"
  on public.match_rounds for select
  using (
    exists (
      select 1 from public.matches m
      where m.id = match_id
        and (m.player1_id = auth.uid() or m.player2_id = auth.uid())
    )
  );

-- MATCH PLACEMENTS
-- Players can see all placements AFTER reveal (face_down = false)
-- Players can only see their OWN placements while face_down = true
create policy "Players see own placements always"
  on public.match_placements for select
  using (auth.uid() = player_id);

create policy "Players see opponent placements after reveal"
  on public.match_placements for select
  using (
    face_down = false
    and exists (
      select 1 from public.matches m
      where m.id = match_id
        and (m.player1_id = auth.uid() or m.player2_id = auth.uid())
    )
  );

create policy "Players can insert own placements"
  on public.match_placements for insert
  with check (auth.uid() = player_id);

-- PACK PURCHASES
create policy "Players can read own purchases"
  on public.pack_purchases for select using (auth.uid() = player_id);

-- BATTLE PASS PROGRESS
create policy "Players can manage own battle pass progress"
  on public.battle_pass_progress for all using (auth.uid() = player_id);

-- MATCH QUEUE
create policy "Players can manage own queue entry"
  on public.match_queue for all using (auth.uid() = player_id);

create policy "Players can read queue to find matches"
  on public.match_queue for select using (true);
