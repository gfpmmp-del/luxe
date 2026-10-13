Add-Type -AssemblyName System.Drawing

$src = "C:\luxe\assets\logo\luxe_logo.png"
$orig = [System.Drawing.Image]::FromFile($src)

# Квадратная основа: центрируем квадрат максимального размера
$side = [Math]::Min($orig.Width, $orig.Height)
$rect = New-Object System.Drawing.Rectangle(
    [int](($orig.Width - $side) / 2), [int](($orig.Height - $side) / 2), $side, $side)
$crop = New-Object System.Drawing.Bitmap($side, $side)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($orig, (New-Object System.Drawing.Rectangle(0, 0, $side, $side)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()

# --- Android ---
$android = @{
  "mipmap-mdpi"    = 48
  "mipmap-hdpi"    = 72
  "mipmap-xhdpi"   = 96
  "mipmap-xxhdpi"  = 144
  "mipmap-xxxhdpi" = 192
}
foreach ($k in $android.Keys) {
  $dir = "C:\luxe\android\app\src\main\res\$k"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $size = $android[$k]
  $b = New-Object System.Drawing.Bitmap($size, $size)
  $gg = [System.Drawing.Graphics]::FromImage($b)
  $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.DrawImage($crop, 0, 0, $size, $size)
  $gg.Dispose()
  $b.Save("$dir\ic_launcher.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
  Write-Host "Android $k : $size"
}

# --- Web ---
$web = @{
  "Icon-192.png"           = 192
  "Icon-512.png"           = 512
  "Icon-maskable-192.png"  = 192
  "Icon-maskable-512.png"  = 512
  "favicon.png"            = 64
}
foreach ($f in $web.Keys) {
  $size = $web[$f]
  $b = New-Object System.Drawing.Bitmap($size, $size)
  $gg = [System.Drawing.Graphics]::FromImage($b)
  $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.DrawImage($crop, 0, 0, $size, $size)
  $gg.Dispose()
  $b.Save("C:\luxe\web\icons\$f", [System.Drawing.Imaging.ImageFormat]::Png)
  if ($f -eq "favicon.png") { $b.Save("C:\luxe\web\$f", [System.Drawing.Imaging.ImageFormat]::Png) }
  $b.Dispose()
  Write-Host "Web $f : $size"
}

# --- Каталог со всеми размерами (для .ico и iOS/macOS) ---
New-Item -ItemType Directory -Force -Path C:\luxe\assets\logo\sizes | Out-Null
foreach ($size in @(16, 24, 32, 48, 64, 128, 256, 512, 1024)) {
  $b = New-Object System.Drawing.Bitmap($size, $size)
  $gg = [System.Drawing.Graphics]::FromImage($b)
  $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.DrawImage($crop, 0, 0, $size, $size)
  $gg.Dispose()
  $b.Save("C:\luxe\assets\logo\sizes\$size.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
}
Write-Host "Sizes generated"

$crop.Dispose()
$orig.Dispose()