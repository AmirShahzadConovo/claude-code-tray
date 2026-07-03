# Icon rendering for the Claude tray widget: an edge-to-edge gradient squircle
# (rounded square) tinted per state; idle is a hollow outline. Chosen over a
# starburst mark because the burst confused with the Claude desktop app icon
# and thin rays read too small at 16px. Dot-sourced by ClaudeTray.ps1.
Add-Type -AssemblyName System.Drawing

function New-RoundedRectPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Get-Lighter([System.Drawing.Color]$c, [double]$f) {
    [System.Drawing.Color]::FromArgb($c.A,
        [int]($c.R + (255 - $c.R) * $f),
        [int]($c.G + (255 - $c.G) * $f),
        [int]($c.B + (255 - $c.B) * $f))
}
function Get-Darker([System.Drawing.Color]$c, [double]$f) {
    [System.Drawing.Color]::FromArgb($c.A,
        [int]($c.R * (1 - $f)),
        [int]($c.G * (1 - $f)),
        [int]($c.B * (1 - $f)))
}

# style: 'filled' = gradient squircle, 'outline' = hollow squircle (idle)
function New-StatusBitmap([System.Drawing.Color]$color, [int]$badge, [string]$style) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($style -eq 'outline') {
        $path = New-RoundedRectPath 3 3 26 26 8
        $pen = New-Object System.Drawing.Pen $color, 4.5
        $g.DrawPath($pen, $path)
        $pen.Dispose(); $path.Dispose()
    } else {
        $path = New-RoundedRectPath 1 1 30 30 10
        $rect = New-Object System.Drawing.RectangleF 0, 0, 32, 32
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, (Get-Lighter $color 0.38), (Get-Darker $color 0.22), [single]78)
        $g.FillPath($grad, $path)
        $grad.Dispose()

        # soft specular sheen across the top third
        $g.SetClip($path)
        $hlRect = New-Object System.Drawing.RectangleF 0, 0, 32, 13
        $hl = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $hlRect,
            [System.Drawing.Color]::FromArgb(90, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillRectangle($hl, $hlRect)
        $hl.Dispose()
        $g.ResetClip()
        $path.Dispose()

        if ($badge -ge 2) {
            $text = if ($badge -gt 9) { '9' } else { [string]$badge }
            # badge text flips to black on bright fills (e.g. the light pulse frame)
            $lum = $color.R * 0.299 + $color.G * 0.587 + $color.B * 0.114
            $textBrush = [System.Drawing.Brushes]::White
            if ($lum -gt 150) { $textBrush = [System.Drawing.Brushes]::Black }
            $font = New-Object System.Drawing.Font('Segoe UI', 19, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $trect = New-Object System.Drawing.RectangleF 0, 1, 32, 30
            $g.DrawString($text, $font, $textBrush, $trect, $sf)
            $font.Dispose(); $sf.Dispose()
        }
    }
    $g.Dispose()
    return $bmp
}

function New-StatusIcon([System.Drawing.Color]$color, [int]$badge, [string]$style) {
    $bmp = New-StatusBitmap $color $badge $style
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $bmp.Dispose()
    return $icon
}
