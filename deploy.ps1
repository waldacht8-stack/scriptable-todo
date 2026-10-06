# Copy src/ into the Scriptable folder on iCloud Drive (iPhone picks it up via iCloud sync).
# Data (todo-data/) is never touched.
# (Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.)
$candidates = @(
  "$env:USERPROFILE\iCloudDrive\iCloud~dk~simonbs~Scriptable",
  "$env:USERPROFILE\iCloudDrive\Scriptable"
)
$dest = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $dest) {
  Write-Error "Scriptable folder not found on iCloud Drive. Turn on iCloud Drive in iCloud for Windows and open Scriptable on the iPhone once."
  exit 1
}
$src = Join-Path $PSScriptRoot 'src'
New-Item -ItemType Directory -Force -Path (Join-Path $dest 'todo-lib') | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'TODO.js') -Destination $dest -Force
# Same entry script under another name: runs the UITable fallback screen
Copy-Item -LiteralPath (Join-Path $src 'TODO.js') -Destination (Join-Path $dest 'TODO Lite.js') -Force
Copy-Item -LiteralPath (Join-Path $src 'TODO Diag.js') -Destination $dest -Force
Copy-Item -Path (Join-Path $src 'todo-lib\*.js') -Destination (Join-Path $dest 'todo-lib') -Force
Write-Output "Deployed to: $dest"
Get-ChildItem -LiteralPath $dest -Recurse -File | Where-Object { $_.FullName -notlike '*todo-data*' } | ForEach-Object { '  ' + $_.FullName.Substring($dest.Length + 1) }
