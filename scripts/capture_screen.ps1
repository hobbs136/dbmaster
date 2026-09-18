# Capture primary screen and save to PNG
param(
    [string]$OutPath = "C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter\site\assets\screenshots\_probe.png"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "Screen bounds: $($bounds.Width) x $($bounds.Height)"

$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

Write-Host "Saved: $OutPath"
Get-Item $OutPath | Select-Object Name, Length, LastWriteTime