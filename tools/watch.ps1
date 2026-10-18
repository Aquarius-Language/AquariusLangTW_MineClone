# Development job runner: executes tools\queue\*.cmd files one at a time.
# The per-job logic lives in runjob.ps1, which is re-read for every job.
# Close this window to stop.
$queue = Join-Path $PSScriptRoot 'queue'
New-Item -ItemType Directory -Force $queue | Out-Null
Write-Host "Watching $queue for jobs (close this window to stop)..."
while ($true) {
  foreach ($j in (Get-ChildItem $queue -Filter *.cmd | Sort-Object Name)) {
    try { & (Join-Path $PSScriptRoot 'runjob.ps1') $j.FullName } catch { Write-Host $_ }
  }
  Start-Sleep -Milliseconds 700
}
