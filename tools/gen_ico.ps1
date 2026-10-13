$sizes = @(16, 24, 32, 48, 64, 128, 256)
$src = "C:\luxe\assets\logo\sizes"
$out = "C:\luxe\windows\runner\resources\app_icon.ico"

# Собираем .ico: PNG-данные внутри (поддерживается Windows Vista+)
$images = @()
foreach ($s in $sizes) {
  $p = Join-Path $src "$s.png"
  if (Test-Path $p) { $images += @{ size = $s; bytes = [System.IO.File]::ReadAllBytes($p) } }
}

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

# ICONDIR
$bw.Write([UInt16]0)            # reserved
$bw.Write([UInt16]1)            # type = icon
$bw.Write([UInt16]$images.Count)# количество картинок

$offset = 6 + (16 * $images.Count)
foreach ($img in $images) {
  $dim = if ($img.size -ge 256) { [byte]0 } else { [byte]$img.size }
  $bw.Write($dim)               # width
  $bw.Write($dim)               # height
  $bw.Write([byte]0)            # цветов в палитре (0 = truecolor)
  $bw.Write([byte]0)            # зарезервировано
  $bw.Write([UInt16]1)          # плоскостей
  $bw.Write([UInt16]32)         # бит на пиксель
  $bw.Write([UInt32]$img.bytes.Length)
  $bw.Write([UInt32]$offset)
  $offset += $img.bytes.Length
}
foreach ($img in $images) { $bw.Write($img.bytes) }

$bw.Flush()
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Write-Host ("ICO создан: {0} ({1} КБ), размеров: {2}" -f $out, [math]::Round((Get-Item $out).Length/1KB,1), $images.Count)