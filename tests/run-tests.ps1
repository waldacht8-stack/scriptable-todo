# Run tests with the Node runtime bundled in VS Code (no Node.js install needed).
# (Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.)
$cmd = Get-Command code -ErrorAction SilentlyContinue
if ($cmd) {
  $code = $cmd.Source -replace '\\bin\\code\.cmd$', '\Code.exe'
} else {
  $code = Join-Path $env:USERPROFILE 'AppData\Local\Programs\Microsoft VS Code\Code.exe'
}
if (-not (Test-Path -LiteralPath $code)) { Write-Error "VS Code (Code.exe) not found: $code"; exit 1 }
$env:ELECTRON_RUN_AS_NODE = '1'
$env:TZ = 'Asia/Tokyo'
$out = Join-Path ([System.IO.Path]::GetTempPath()) 'todo-test-out.txt'
$err = Join-Path ([System.IO.Path]::GetTempPath()) 'todo-test-err.txt'
$p = Start-Process -FilePath $code -ArgumentList ('"' + (Join-Path $PSScriptRoot 'run-tests.js') + '"') `
  -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Get-Content $out -Encoding UTF8
Get-Content $err -Encoding UTF8
exit $p.ExitCode
