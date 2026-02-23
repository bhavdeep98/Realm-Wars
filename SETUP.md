# Veilborn — Supabase Setup Guide

## Step 1: Create Your Supabase Project

1. Go to https://supabase.com and create a new project
2. Choose a region close to your target players (US East for North America)
3. Save your project URL and anon key — you'll need these in Flutter

---

## Step 2: Run the Schema

In Supabase Dashboard → SQL Editor → New Query:

1. Paste and run `001_schema.sql` — creates all tables, RLS policies, and triggers
2. Paste and run `002_seed.sql` — seeds card definitions, packs, and Season 1 battle pass

Verify with:
```sql
select count(*) from card_definitions;  -- should be 12
select count(*) from card_packs;        -- should be 3
select count(*) from battle_pass;       -- should be 1
```

---

## Step 3: Enable Realtime

In Supabase Dashboard → Database → Replication:

Enable Realtime for these tables:
- `matches` (for match state changes)
- `match_rounds` (for new round narrations)
- `match_placements` (for opponent placement reveals)

---

## Step 4: Deploy Edge Functions

Install Supabase CLI:
```bash
brew install supabase/tap/supabase
supabase login
```

Link to your project:
```bash
supabase link --project-ref YOUR_PROJECT_REF
```

Deploy the resolve-round function:
```bash
supabase functions deploy resolve-round
```

Set secrets:
```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-your-key-here
```

---

## Step 5: Configure Storage

In Supabase Dashboard → Storage:

Create these buckets:

| Bucket Name      | Public | Purpose                          |
|------------------|--------|----------------------------------|
| `card-art`       | Yes    | Generated card portraits (cached forever) |
| `battle-scenes`  | Yes    | Round battle images (one per round) |
| `avatars`        | Yes    | Player profile pictures          |

Set a 10MB file size limit on all buckets.

---

## Step 6: Flutter Environment Variables

Create `lib/config/supabase_config.dart`:

```dart
class SupabaseConfig {
  static const String url = 'https://YOUR_PROJECT_REF.supabase.co';
  static const String anonKey = 'YOUR_ANON_KEY';

  // Edge Function URLs
  static const String resolveRoundUrl =
    '$url/functions/v1/resolve-round';
}
```

**Never commit real keys.** Use `--dart-define` for production builds:
```bash
flutter build ios --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

---

## Step 7: Matchmaking Cron Job

Set up a Supabase scheduled function to widen ELO brackets over time
(so players don't wait forever):

In Supabase Dashboard → Database → Functions, create:

```sql
-- Widen bracket by 50 ELO every 30 seconds a player waits
create or replace function public.widen_matchmaking_brackets()
returns void language plpgsql as $$
begin
  update public.match_queue
  set bracket_width = least(bracket_width + 50, 500)
  where entered_at < now() - interval '30 seconds';
end;
$$;
```

Then schedule it with pg_cron (enabled in Supabase Extensions):
```sql
select cron.schedule(
  'widen-brackets',
  '*/30 * * * * *',   -- every 30 seconds
  'select public.widen_matchmaking_brackets()'
);
```

---

## Key Environment Variables

| Variable                    | Where Set            | Value |
|-----------------------------|----------------------|-------|
| `SUPABASE_URL`              | Flutter app          | Your project URL |
| `SUPABASE_ANON_KEY`         | Flutter app          | Anon key (safe for client) |
| `ANTHROPIC_API_KEY`         | Supabase secrets     | Your Claude API key |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge functions only  | Service role key (never expose) |

---

## Realtime Channel Naming Convention

Each match uses a dedicated Realtime channel:
```
match:{match_uuid}
```

Flutter subscribes on match start, unsubscribes on match end.
The Edge Function broadcasts to this channel after each round resolves.

---

## Recommended Indexes (already in schema)

| Table              | Index                                    | Purpose                      |
|--------------------|------------------------------------------|------------------------------|
| `matches`          | `(status, elo_bracket)` partial          | Fast matchmaking lookup      |
| `player_cards`     | `(player_id, is_dormant)`               | Filter dormant cards         |
| `match_placements` | `(match_id, round_number)`              | Round state queries          |
| `match_rounds`     | `(match_id)`                            | Match history                |

---

## Cost Estimates (Supabase Free Tier)

The free tier supports:
- 500MB database
- 5GB storage
- 2GB bandwidth
- 500MB Edge Function memory

For early beta this is more than enough. Upgrade to Pro ($25/mo) when you hit:
- ~100 concurrent players, or
- 1GB+ database size

At $25/mo Pro you get 8GB database and 100GB bandwidth — sufficient for ~10,000 MAU.
