param([string]$Path)
$base = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Path), [IO.Path]::GetFileNameWithoutExtension($Path))
$run = "$base.job.cmd"
Move-Item $Path $run -Force
Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), [IO.Path]::GetFileName($Path))
# Wait for the job's own cmd.exe only: build servers or launched apps may outlive it.
$p = Start-Process -FilePath cmd.exe -ArgumentList "/c $run > $base.log 2>&1" -NoNewWindow -PassThru
$p.WaitForExit()
Set-Content "$base.done" $p.ExitCode
Remove-Item $run -Force
Write-Host ("    exit {0}" -f $p.ExitCode)
