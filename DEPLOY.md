# Deployment Guide

## Prerequisites

1. Install Supabase CLI:
   ```bash
   # Windows (using Scoop)
   scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
   scoop install supabase
   
   # Or using npm
   npm install -g supabase
   ```

2. Verify installation:
   ```bash
   supabase --version
   ```

## Step-by-Step Deployment

### 1. Login to Supabase

```bash
supabase login
```

This will open your browser to authenticate.

### 2. Link to Your Project

```bash
cd Realm-Wars
supabase link --project-ref qsexqntsuprxuyzssdda
```

You'll be prompted to enter your database password (from when you created the project).

### 3. Deploy the Edge Function

```bash
supabase functions deploy resolve-round
```

### 4. Set Environment Secrets

```bash
supabase secrets set OPENAI_API_KEY=sk-proj-YOUR-ACTUAL-KEY-HERE
```

### 5. Verify Deployment

Check your function is live:
```bash
supabase functions list
```

Or test it directly:
```bash
curl -i --location --request POST 'https://qsexqntsuprxuyzssdda.supabase.co/functions/v1/resolve-round' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"match_id":"test","round_number":1}'
```

## Troubleshooting

**"Command not found: supabase"**
- Make sure Supabase CLI is installed and in your PATH

**"Project not linked"**
- Run `supabase link --project-ref qsexqntsuprxuyzssdda` first

**"Function deployment failed"**
- Check that `supabase/functions/resolve-round/index.ts` exists
- Verify your Deno imports are valid
- Check function logs: `supabase functions logs resolve-round`

**"Secrets not set"**
- Run `supabase secrets list` to verify
- Re-run the secrets set command if needed

## Function URL

After deployment, your function will be available at:
```
https://qsexqntsuprxuyzssdda.supabase.co/functions/v1/resolve-round
```

## Updating the Function

To redeploy after making changes:
```bash
supabase functions deploy resolve-round
```

Changes take effect immediately.
