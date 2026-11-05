<#
.SYNOPSIS  Windows form to brand and build RemoteTool for one organization (name, logo, concurrent users, developer).
.DESCRIPTION
  Fill in the form -> it writes branding\<org>\branding.json (+ logo.png, relay.env), then calls scripts\publish-app.ps1 -BrandingDir so the
  values are embedded in that organization's RemoteTool.exe. Run again for the next customer. Add -NoBuild to only create the branding folder.
.PARAMETER FromFile  Skip the form and use an existing branding folder (CI): -FromFile branding\acme
#>
param([string]$FromFile = "", [switch]$NoBuild, [string]$SignThumbprint = "", [switch]$SkipTests)
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\.."

function Build($dir) {
    if ($NoBuild) { Write-Host "Branding written to $dir"; return }
    $a = @{ BrandingDir = $dir; Output = "$root\artifacts\$(Split-Path $dir -Leaf)" }
    if ($SignThumbprint) { $a.SignThumbprint = $SignThumbprint }
    if ($SkipTests) { $a.SkipTests = $true }
    & "$PSScriptRoot\publish-app.ps1" @a
}
if ($FromFile) { Build (Resolve-Path $FromFile).Path; return }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$f = New-Object Windows.Forms.Form -Property @{ Text = "RemoteTool - Enterprise build"; Size = '480,360'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false }
function Row($label, $y, $ctl) {
    $l = New-Object Windows.Forms.Label -Property @{ Text = $label; Location = "16,$($y+3)"; Size = '150,20' }
    $ctl.Location = "170,$y"; $f.Controls.AddRange(@($l, $ctl))
}
$org = New-Object Windows.Forms.TextBox -Property @{ Size = '280,24'; MaxLength = 80 }
$users = New-Object Windows.Forms.NumericUpDown -Property @{ Size = '100,24'; Minimum = 0; Maximum = 100000; Value = 10 }
$dev = New-Object Windows.Forms.TextBox -Property @{ Size = '280,24'; Text = 'Toolveriq'; MaxLength = 80 }
$logoBox = New-Object Windows.Forms.TextBox -Property @{ Size = '200,24'; ReadOnly = $true }
$browse = New-Object Windows.Forms.Button -Property @{ Text = 'Browse...'; Size = '75,26'; Location = '375,127' }
$preview = New-Object Windows.Forms.PictureBox -Property @{ Size = '96,48'; Location = '170,165'; SizeMode = 'Zoom'; BorderStyle = 'FixedSingle' }
$hint = New-Object Windows.Forms.Label -Property @{ Text = "0 concurrent users = unlimited. The limit is enforced by the relay (relay.env)."; Location = '16,225'; Size = '440,32' }
$ok = New-Object Windows.Forms.Button -Property @{ Text = 'Build'; Size = '90,30'; Location = '270,280'; DialogResult = 'OK' }
$cancel = New-Object Windows.Forms.Button -Property @{ Text = 'Cancel'; Size = '90,30'; Location = '366,280'; DialogResult = 'Cancel' }
Row "Organization name" 20 $org; Row "Concurrent users" 60 $users; Row "Developed by" 95 $dev; Row "Company logo (PNG)" 128 $logoBox
$f.Controls.AddRange(@($browse, $preview, $hint, $ok, $cancel)); $f.AcceptButton = $ok; $f.CancelButton = $cancel
$browse.Add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog -Property @{ Filter = 'Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp' }
    if ($d.ShowDialog() -eq 'OK') { $logoBox.Text = $d.FileName; $preview.Image = [Drawing.Image]::FromFile($d.FileName) }
})
$f.Add_FormClosing({
    if ($f.DialogResult -eq 'OK' -and [string]::IsNullOrWhiteSpace($org.Text)) {
        [Windows.Forms.MessageBox]::Show("Enter the organization name."); $_.Cancel = $true
    }
})
if ($f.ShowDialog() -ne 'OK') { return }

$name = ($org.Text -replace '[\p{Cc}]', '').Trim()
$slug = ($name -replace '[^\p{L}\p{N}]+', '-').Trim('-').ToLower()
if (-not $slug) { $slug = "org" }
$dir = Join-Path $root "branding\$slug"
New-Item -ItemType Directory -Force $dir | Out-Null
$devName = ($dev.Text -replace '[\p{Cc}]', '').Trim(); if (-not $devName) { $devName = 'Toolveriq' }
$json = [ordered]@{ organization = $name; maxConcurrentUsers = [int]$users.Value; developedBy = $devName } | ConvertTo-Json -Compress
[IO.File]::WriteAllText("$dir\branding.json", $json, (New-Object Text.UTF8Encoding $false))
if (Test-Path "$dir\logo.png") { Remove-Item "$dir\logo.png" }
if ($logoBox.Text) {
    # Normalize any image to a PNG no larger than 256px high so the exe stays small.
    $src = [Drawing.Image]::FromFile($logoBox.Text)
    $h = [Math]::Min(256, $src.Height); $w = [int]($src.Width * $h / $src.Height)
    $bmp = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($src, 0, 0, $w, $h); $g.Dispose()
    $bmp.Save("$dir\logo.png", [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $src.Dispose()
}
# Seat limit for this organization's relay (RelayOptions.MaxConcurrentSessions); 0 = leave the relay default.
if ($users.Value -gt 0) { Set-Content "$dir\relay.env" "RELAY__MaxConcurrentSessions=$([int]$users.Value)" } elseif (Test-Path "$dir\relay.env") { Remove-Item "$dir\relay.env" }
Build $dir
