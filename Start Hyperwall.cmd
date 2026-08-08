@echo off & setlocal
rem Double-click to launch the EIC Hyperwall fullscreen. Serves this folder over
rem http (needed so the page can read .env) and opens the browser in fullscreen.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$root='%~dp0';$c=(Get-Content -LiteralPath '%~f0' -Raw) -replace '(?s)^.*?#PS>\r?\n','';Invoke-Expression $c"
goto :eof
#PS>
$ErrorActionPreference = 'Stop'
$root = $root.TrimEnd('\')
$port = 8787
$url  = "http://localhost:$port/eic-hyperwall.html"

# Open the wall fullscreen in Edge if present, otherwise the default browser (F11).
function Open-Wall($u) {
  $edge = $null
  foreach ($c in @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:LocalAppData\Microsoft\Edge\Application\msedge.exe"
  )) { if (Test-Path $c) { $edge = $c; break } }
  if (-not $edge) {
    try { $edge = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction Stop).'(default)' } catch {}
    if (-not $edge -or -not (Test-Path $edge)) { $cmd = Get-Command msedge.exe -ErrorAction SilentlyContinue; if ($cmd) { $edge = $cmd.Source } }
  }
  if ($edge -and (Test-Path $edge)) {
    # A dedicated profile forces a fresh Edge process so the kiosk flags always
    # apply, even when Edge is already open. Kiosk = true borderless fullscreen.
    $profileDir = Join-Path $env:LocalAppData 'EICHyperwall\EdgeProfile'
    Start-Process $edge -ArgumentList @(
      "--user-data-dir=$profileDir",
      '--no-first-run',
      '--kiosk', $u,
      '--edge-kiosk-type=fullscreen',
      '--no-default-browser-check'
    )
  } else {
    Write-Host "Edge not found - opening your default browser. Press F11 for fullscreen." -ForegroundColor Yellow
    Start-Process $u
  }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try {
  $listener.Start()
} catch {
  Write-Host "Server already running (or port $port busy). Opening the wall..." -ForegroundColor Yellow
  Open-Wall $url
  return
}

Write-Host "EIC Hyperwall serving at $url" -ForegroundColor Green
Write-Host "Keep this window open while the wall runs. Close it to stop." -ForegroundColor DarkGray

Open-Wall $url

$mime = @{
  '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8';
  '.js'='text/javascript'; '.css'='text/css'; '.json'='application/json';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif';
  '.svg'='image/svg+xml'; '.ico'='image/x-icon'; '.mp4'='video/mp4';
  '.env'='text/plain; charset=utf-8'
}
$rootFull = [System.IO.Path]::GetFullPath($root)

while ($listener.IsListening) {
  try { $ctx = $listener.GetContext() } catch { break }
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'eic-hyperwall.html' }
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
    if (-not $full.StartsWith($rootFull)) {
      $res.StatusCode = 403                       # block path traversal outside the folder
    } elseif (Test-Path $full -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $ct = $mime[$ext]; if (-not $ct) { $ct = 'application/octet-stream' }
      $res.ContentType = $ct
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.OutputStream.Close() } catch {}
  }
}
