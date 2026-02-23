#!/bin/bash

# Realm Wars - Edge Function Deployment Script

echo "🚀 Deploying Realm Wars Edge Functions..."
echo ""

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found!"
    echo "Install it with: npm install -g supabase"
    exit 1
fi

# Check if logged in
echo "📝 Checking Supabase login status..."
if ! supabase projects list &> /dev/null; then
    echo "❌ Not logged in to Supabase"
    echo "Run: supabase login"
    exit 1
fi

# Deploy function
echo "📦 Deploying resolve-round function..."
supabase functions deploy resolve-round

if [ $? -eq 0 ]; then
    echo "✅ Function deployed successfully!"
    echo ""
    echo "🔑 Don't forget to set your secrets:"
    echo "supabase secrets set OPENAI_API_KEY=your-key-here"
    echo ""
    echo "🌐 Function URL:"
    echo "https://qsexqntsuprxuyzssdda.supabase.co/functions/v1/resolve-round"
else
    echo "❌ Deployment failed!"
    exit 1
fi
