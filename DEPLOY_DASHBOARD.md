# Deploy Edge Function via Supabase Dashboard (No CLI Required)

## Step 1: Access Your Project

Go to: https://supabase.com/dashboard/project/qsexqntsuprxuyzssdda

## Step 2: Navigate to Edge Functions

1. Click **"Edge Functions"** in the left sidebar
2. Click **"Create a new function"** button

## Step 3: Create the Function

1. **Function name:** `resolve-round`
2. Click **"Create function"**

## Step 4: Paste the Code

1. Delete any default code in the editor
2. Open the file: `Realm-Wars/supabase/functions/resolve-round/index.ts`
3. Copy ALL the code from that file
4. Paste it into the Supabase editor
5. Click **"Deploy"** or **"Save"**

## Step 5: Set Environment Variables

1. In the Edge Functions page, click on your `resolve-round` function
2. Go to the **"Settings"** or **"Secrets"** tab
3. Add these secrets:

   **Secret Name:** `OPENAI_API_KEY`  
   **Value:** Your OpenAI API key (starts with `sk-proj-...`)

   Note: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are automatically provided by Supabase

4. Click **"Save"**

## Step 6: Test the Function

1. Go to the **"Logs"** tab to monitor function calls
2. Your function URL is:
   ```
   https://qsexqntsuprxuyzssdda.supabase.co/functions/v1/resolve-round
   ```

## Alternative: Use the Supabase Dashboard SQL Editor

If the Edge Functions UI doesn't work well, you can also:

1. Go to **SQL Editor** in your Supabase dashboard
2. Run your schema files (`001_schema.sql` and `002_seed.sql`)
3. For the edge function, you may need to wait for Supabase to add better dashboard support, or use the CLI

## Troubleshooting

**Can't find Edge Functions in sidebar?**
- Make sure you're on a paid plan or have edge functions enabled
- Try refreshing the page

**Function not deploying?**
- Check for syntax errors in the code
- Make sure all imports are valid Deno imports
- Check the function logs for error messages

**Secrets not working?**
- Make sure secret names are EXACTLY as shown (case-sensitive)
- Redeploy the function after adding secrets

## Next Steps

After deployment:
1. Run the database schema (`db/001_schema.sql`)
2. Seed the cards (`db/002_seed.sql`)
3. Test the Flutter app
