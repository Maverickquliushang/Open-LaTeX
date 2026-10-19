param([Parameter(Mandatory=$true)][string]$SourcePng,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$base = [Drawing.Image]::FromFile($SourcePng)
$canvas = New-Object Drawing.Bitmap(256,256)
$g = [Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::Transparent)
$g.DrawImage($base,0,0,256,256)
$outline = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F8FBFA'))
$badge = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F3AE38'))
$arrow = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#173F57'))
$g.FillEllipse($outline,153,153,99,99)
$g.FillEllipse($badge,160,160,85,85)
$g.FillPolygon($arrow,[Drawing.PointF[]]@([Drawing.PointF]::new(189,178),[Drawing.PointF]::new(189,227),[Drawing.PointF]::new(224,202.5)))
$canvas.Save((Join-Path $OutputDirectory 'Start-LaTeX-preview.png'),[Drawing.Imaging.ImageFormat]::Png)
$frames = @()
foreach ($size in @(16,20,24,32,40,48,64,128,256)) {
    $small = New-Object Drawing.Bitmap($size,$size)
    $sg = [Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.DrawImage($canvas,0,0,$size,$size)
    $stream = New-Object IO.MemoryStream
    $small.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
    $frames += [pscustomobject]@{Size=$size;Bytes=$stream.ToArray()}
    $stream.Dispose(); $sg.Dispose(); $small.Dispose()
}
$file = [IO.File]::Create((Join-Path $OutputDirectory 'Start-LaTeX.ico'))
$writer = New-Object IO.BinaryWriter($file)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $dimension = if ($frame.Size -eq 256) {0} else {$frame.Size}
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
} finally { $writer.Dispose(); $file.Dispose() }
foreach ($item in @($arrow,$badge,$outline,$g,$canvas,$base)) { $item.Dispose() }
