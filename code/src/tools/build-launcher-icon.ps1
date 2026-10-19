param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function New-RoundedSquare([single]$x, [single]$y, [single]$width, [single]$radius) {
    $shape = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $shape.AddArc($x,$y,$diameter,$diameter,180,90)
    $shape.AddArc(($x+$width-$diameter),$y,$diameter,$diameter,270,90)
    $shape.AddArc(($x+$width-$diameter),($y+$width-$diameter),$diameter,$diameter,0,90)
    $shape.AddArc($x,($y+$width-$diameter),$diameter,$diameter,90,90)
    $shape.CloseFigure()
    return ,$shape
}

$frames = @()
foreach ($size in @(16,20,24,32,40,48,64,128,256)) {
    $bitmap = New-Object Drawing.Bitmap(256,256)
    $g = [Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([Drawing.Color]::Transparent)
    $back = New-RoundedSquare 8 8 240 48
    $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush([Drawing.Point]::new(20,10),[Drawing.Point]::new(240,246),[Drawing.ColorTranslator]::FromHtml('#148B8B'),[Drawing.ColorTranslator]::FromHtml('#174B68'))
    $g.FillPath($gradient,$back)
    $paper = New-Object Drawing.Drawing2D.GraphicsPath
    $paper.AddPolygon([Drawing.PointF[]]@([Drawing.PointF]::new(57,36),[Drawing.PointF]::new(156,36),[Drawing.PointF]::new(200,80),[Drawing.PointF]::new(200,221),[Drawing.PointF]::new(57,221)))
    $white = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F8FBFA'))
    $fold = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#B6DDDC'))
    $ink = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#174B68'))
    $g.FillPath($white,$paper)
    $g.FillPolygon($fold,[Drawing.PointF[]]@([Drawing.PointF]::new(156,36),[Drawing.PointF]::new(156,80),[Drawing.PointF]::new(200,80)))
    # Original geometric letter strokes; no downloaded image or font glyph is embedded.
    $letterPen = New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#174B68'),8)
    $letterPen.StartCap = $letterPen.EndCap = [Drawing.Drawing2D.LineCap]::Square
    if ($size -le 24) {
        $g.DrawLine($letterPen,85,107,171,107)
        $g.DrawLine($letterPen,128,107,128,175)
    } else {
        $g.DrawLine($letterPen,75,111,111,111)
        $g.DrawLine($letterPen,93,111,93,160)
        $g.DrawLine($letterPen,119,125,119,164)
        $g.DrawLine($letterPen,119,125,141,125)
        $g.DrawLine($letterPen,119,145,138,145)
        $g.DrawLine($letterPen,119,164,141,164)
        $g.DrawLine($letterPen,153,111,181,160)
        $g.DrawLine($letterPen,181,111,153,160)
    }
    if ($size -gt 24) {
        $pen = New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#8EBBBC'),5)
        $pen.StartCap = $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($pen,82,185,174,185)
        $g.DrawLine($pen,82,200,149,200)
        $pen.Dispose()
    }
    if ($size -eq 256) { $bitmap.Save((Join-Path $OutputDirectory 'Open-LaTeX-preview.png'),[Drawing.Imaging.ImageFormat]::Png) }
    $small = New-Object Drawing.Bitmap($size,$size)
    $sg = [Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.DrawImage($bitmap,0,0,$size,$size)
    $stream = New-Object IO.MemoryStream
    $small.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
    $frames += [pscustomobject]@{Size=$size;Bytes=$stream.ToArray()}
    foreach ($item in @($stream,$sg,$small,$letterPen,$ink,$fold,$white,$paper,$gradient,$back,$g,$bitmap)) { $item.Dispose() }
}
$file = [IO.File]::Create((Join-Path $OutputDirectory 'Open-LaTeX.ico'))
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
Write-Output ('Created multi-resolution icon: ' + (Join-Path $OutputDirectory 'Open-LaTeX.ico'))
