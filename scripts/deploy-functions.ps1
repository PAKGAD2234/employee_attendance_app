# Deploy edited Supabase Edge Functions (Windows PowerShell)
# Usage: Open PowerShell in repository root and run:
#   .\scripts\deploy-functions.ps1
# or specify functions:
#   .\scripts\deploy-functions.ps1 -Functions notify-checkin,notify-checkout

param(
  [string[]]$Functions = @('notify-checkin','notify-checkout')
)

function Abort($msg){ Write-Host $msg -ForegroundColor Red; exit 1 }

# Check supabase CLI
if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  Abort "supabase CLI not found. Install: npm i -g supabase or see https://supabase.com/docs/guides/cli"
}

# Ensure logged in
$supLogin = & supabase login 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "You may need to run 'supabase login' interactively to authenticate." -ForegroundColor Yellow
}

# Optional: project ref from env
$projectRef = $env:SUPABASE_PROJECT_REF
if (-not $projectRef) {
  Write-Host "No SUPABASE_PROJECT_REF env var detected. If you manage multiple projects, pass --project-ref manually." -ForegroundColor Yellow
}

foreach ($f in $Functions) {
  Write-Host "Deploying function: $f" -ForegroundColor Cyan
  $cmd = "supabase functions deploy $f"
  if ($projectRef) { $cmd += " --project-ref $projectRef" }
  Write-Host "Running: $cmd"
  iex $cmd
  if ($LASTEXITCODE -ne 0) { Abort "Deploy failed for $f" }
}

Write-Host "Deployment finished for: $($Functions -join ', ')" -ForegroundColor Green
