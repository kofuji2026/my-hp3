$port = 3002
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
            # ライブリロード用エンドポイント：最新ファイルのタイムスタンプを返す
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
        # エラーを握りつぶしてサーバーを継続
    } finally {
        try { $res.OutputStream.Close() } catch {}
    }
}
