$port = 3003
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Output "Serving $root on http://localhost:$port/"

$mimeMap = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff2'= 'font/woff2'
    '.woff' = 'font/woff'
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        $urlPath = $req.Url.LocalPath

        if ($urlPath -eq '/_live') {
            # Live-reload endpoint: returns latest file timestamp as JSON hash
            $newest = Get-ChildItem -Path $root -Include "*.html","*.css","*.js" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            $hashStr = if ($newest) { $newest.LastWriteTimeUtc.Ticks.ToString() } else { "0" }
            $body = [System.Text.Encoding]::UTF8.GetBytes("{`"hash`":`"$hashStr`"}")
            $res.StatusCode      = 200
            $res.ContentType     = 'application/json; charset=utf-8'
            $res.Headers.Add('Access-Control-Allow-Origin', '*')
            $res.ContentLength64 = $body.LongLength
            $res.OutputStream.Write($body, 0, $body.Length)
        } elseif ($urlPath -eq '/api/chat' -and $req.HttpMethod -eq 'POST') {
            # AI Chat endpoint – proxies to Anthropic API
            $apiKey = $env:ANTHROPIC_API_KEY
            if (-not $apiKey) {
                $eb = [System.Text.Encoding]::UTF8.GetBytes('{"error":"ANTHROPIC_API_KEY environment variable not set"}')
                $res.StatusCode = 500; $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Access-Control-Allow-Origin', '*')
                $res.ContentLength64 = $eb.LongLength
                $res.OutputStream.Write($eb, 0, $eb.Length)
            } else {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $inStr = $sr.ReadToEnd(); $sr.Close()
                $payload = $inStr | ConvertFrom-Json

                $msgs = [System.Collections.ArrayList]@()
                if ($payload.history) {
                    foreach ($h in $payload.history) {
                        [void]$msgs.Add([PSCustomObject]@{ role = $h.role; content = $h.content })
                    }
                }
                [void]$msgs.Add([PSCustomObject]@{ role = 'user'; content = $payload.message })

                try {
                    # Load system prompt from UTF-8 file to avoid encoding issues in .ps1
                    $promptFile = Join-Path $root 'chat-prompt.txt'
                    $sys = [System.IO.File]::ReadAllText($promptFile, [System.Text.Encoding]::UTF8).Trim()

                    $apiReq = [PSCustomObject]@{
                        model      = 'claude-haiku-4-5-20251001'
                        max_tokens = 800
                        system     = $sys
                        messages   = $msgs.ToArray()
                    } | ConvertTo-Json -Depth 10
                    $apiBytes = [System.Text.Encoding]::UTF8.GetBytes($apiReq)

                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add('x-api-key', $apiKey)
                    $wc.Headers.Add('anthropic-version', '2023-06-01')
                    $wc.Headers.Add('Content-Type', 'application/json; charset=utf-8')
                    $respBytes = $wc.UploadData('https://api.anthropic.com/v1/messages', 'POST', $apiBytes)
                    $respStr   = [System.Text.Encoding]::UTF8.GetString($respBytes)
                    $apiRes    = $respStr | ConvertFrom-Json
                    $reply     = $apiRes.content[0].text
                    $rb = [System.Text.Encoding]::UTF8.GetBytes(([PSCustomObject]@{ reply = $reply } | ConvertTo-Json))
                    $res.StatusCode = 200; $res.ContentType = 'application/json; charset=utf-8'
                    $res.Headers.Add('Access-Control-Allow-Origin', '*')
                    $res.ContentLength64 = $rb.LongLength
                    $res.OutputStream.Write($rb, 0, $rb.Length)
                } catch {
                    # Catch ALL exceptions and return JSON so the browser never sees a raw connection close
                    $errDetail = $_.Exception.Message
                    if ($_.Exception -is [System.Net.WebException] -and $_.Exception.Response) {
                        try {
                            $errReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                            $errDetail = $errReader.ReadToEnd(); $errReader.Close()
                        } catch {}
                    }
                    $eb = [System.Text.Encoding]::UTF8.GetBytes(([PSCustomObject]@{ error = $errDetail } | ConvertTo-Json))
                    $res.StatusCode = 502; $res.ContentType = 'application/json; charset=utf-8'
                    $res.Headers.Add('Access-Control-Allow-Origin', '*')
                    $res.ContentLength64 = $eb.LongLength
                    $res.OutputStream.Write($eb, 0, $eb.Length)
                }
            }
        } else {
            if ($urlPath -eq '/') { $urlPath = '/index.html' }
            $filePath = Join-Path $root ($urlPath.TrimStart('/') -replace '/', '\')

            if (Test-Path $filePath -PathType Leaf) {
                $ext   = [System.IO.Path]::GetExtension($filePath).ToLower()
                $mime  = if ($mimeMap.ContainsKey($ext)) { $mimeMap[$ext] } else { 'application/octet-stream' }
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $res.StatusCode      = 200
                $res.ContentType     = $mime
                $res.ContentLength64 = $bytes.LongLength
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
                $res.StatusCode      = 404
                $res.ContentType     = 'text/plain; charset=utf-8'
                $res.ContentLength64 = $body.LongLength
                $res.OutputStream.Write($body, 0, $body.Length)
            }
        }
    } catch {
        # Swallow per-request errors to keep the server running
    } finally {
        try { $res.OutputStream.Close() } catch {}
    }
}
