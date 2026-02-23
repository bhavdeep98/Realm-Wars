# Realm Wars - Edge Function Deployment Script (PowerShell)

Write-Host "🚀 Deploying Realm Wars Edge Functions..." -ForegroundColor Cyan
Write-Host ""

# Check if supabase CLI is installed
$supabaseCmd = Get-Command supabase -ErrorAction SilentlyContinue
if (-not $supabaseCmd) {
    Write-Host "❌ Supabase CLI not found!" -ForegroundColor Red
    Write-Host "Install it with: npm install -g supabase" -ForegroundColor Yellow
    exit 1
}

# Check if logged in
Write-Host "📝 Checking Supabase login status..." -ForegroundColor Yellow
$loginCheck = supabase projects list 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Not logged in to Supabase" -ForegroundColor Red
    Write-Host "Run: supabase login" -ForegroundColor Yellow
    exit 1
}

# Deploy function
Write-Host "📦 Deploying resolve-round function..." -ForegroundColor Yellow
supabase functions deploy resolve-round

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Function deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "🔑 Don't forget to set your secrets:" -ForegroundColor Cyan
    Write-Host "supabase secrets set OPENAI_API_KEY=your-key-here" -ForegroundColor White
    Write-Host ""
    Write-Host "🌐 Function URL:" -ForegroundColor Cyan
    Write-Host "https://qsexqntsuprxuyzssdda.supabase.co/functions/v1/resolve-round" -ForegroundColor White
} else {
    Write-Host "❌ Deployment failed!" -ForegroundColor Red
    exit 1
}
