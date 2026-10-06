# Run tests with the Node runtime bundled in VS Code (no Node.js install needed).
# (Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.)
$code = (Get-Command code -ErrorAction Stop).Source -replace '\\bin\\code\.cmd$', '\Code.exe'
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
