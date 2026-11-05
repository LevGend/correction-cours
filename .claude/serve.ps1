$root = Join-Path $PSScriptRoot '..' | Resolve-Path
$l = New-Object System.Net.HttpListener; $l.Prefixes.Add('http://localhost:8765/'); $l.Start()
while ($l.IsListening) { $c = $l.GetContext(); $p = $c.Request.Url.AbsolutePath.TrimStart('/'); if (!$p) { $p = 'template/cours_template.html' }
  $f = Join-Path $root $p; if (Test-Path $f) { $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = 'text/html; charset=utf-8'; $c.Response.OutputStream.Write($b,0,$b.Length) } else { $c.Response.StatusCode = 404 }
  $c.Response.Close() }
