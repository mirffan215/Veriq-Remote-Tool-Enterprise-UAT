<#
.SYNOPSIS  Windows form to brand and build RemoteTool for one organization (name, logo, concurrent users, developer, relay server).
.DESCRIPTION
  Fill in the form -> it writes branding\<org>\branding.json (+ logo.png, relay.env), then calls scripts\publish-app.ps1 -BrandingDir so the
  values are embedded in that organization's RemoteTool.exe. Run again for the next customer. Add -NoBuild to only create the branding folder.
.PARAMETER FromFile  Skip the form and use an existing branding folder (CI): -FromFile branding\acme
#>
param([string]$FromFile = "", [switch]$NoBuild, [string]$SignThumbprint = "", [switch]$SkipTests)
# With -FromFile there is no form: set RT_DEFAULT_RELAY / RT_DEFAULT_RELAY_FP / RT_DEFAULT_RELAY_KEY in the environment (CI secrets).
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
$f = New-Object Windows.Forms.Form -Property @{ Text = "RemoteTool - Enterprise build"; Size = '500,520'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false }
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
$hint = New-Object Windows.Forms.Label -Property @{ Text = "0 concurrent users = unlimited. The limit is enforced by the relay (relay.env)."; Location = '16,222'; Size = '460,32' }
$grp = New-Object Windows.Forms.Label -Property @{ Text = "Relay server (baked into the exe; users never see it)"; Location = '16,262'; Size = '460,20'; Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold) }
$relay = New-Object Windows.Forms.TextBox -Property @{ Size = '300,24' }
$fp = New-Object Windows.Forms.TextBox -Property @{ Size = '300,24' }
$key = New-Object Windows.Forms.TextBox -Property @{ Size = '300,24'; UseSystemPasswordChar = $true }
$lock = New-Object Windows.Forms.CheckBox -Property @{ Text = "Hide and lock relay settings in the client"; Checked = $true; Location = '170,400'; Size = '300,22' }
$relayHint = New-Object Windows.Forms.Label -Property @{ Text = "Relay: host:port, several separated by commas for failover. Fingerprint only if the relay uses a self-signed certificate. The access key can be extracted from the exe by anyone who has it: use a key you can rotate."; Location = '16,428'; Size = '460,48' }
$ok = New-Object Windows.Forms.Button -Property @{ Text = 'Build'; Size = '90,30'; Location = '290,480'; DialogResult = 'OK' }
$cancel = New-Object Windows.Forms.Button -Property @{ Text = 'Cancel'; Size = '90,30'; Location = '386,480'; DialogResult = 'Cancel' }
Row "Organization name" 20 $org; Row "Concurrent users" 60 $users; Row "Developed by" 95 $dev; Row "Company logo (PNG)" 128 $logoBox
Row "Relay address" 292 $relay; Row "Relay fingerprint" 328 $fp; Row "Relay access key" 364 $key
$f.Controls.AddRange(@($browse, $preview, $hint, $grp, $lock, $relayHint, $ok, $cancel)); $f.AcceptButton = $ok; $f.CancelButton = $cancel
$browse.Add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog -Property @{ Filter = 'Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp' }
    if ($d.ShowDialog() -eq 'OK') { $logoBox.Text = $d.FileName; $preview.Image = [Drawing.Image]::FromFile($d.FileName) }
})
$f.Add_FormClosing({
    if ($f.DialogResult -eq 'OK' -and [string]::IsNullOrWhiteSpace($org.Text)) {
        [Windows.Forms.MessageBox]::Show("Enter the organization name."); $_.Cancel = $true
    }
    elseif ($f.DialogResult -eq 'OK') {
        $r = $relay.Text.Trim()
        $bad = ($r -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[A-Za-z0-9.\-]+:\d{1,5}$' })
        if ($bad -or ($lock.Checked -and -not $r)) {
            [Windows.Forms.MessageBox]::Show("Relay address must look like relay.example.com:8443 (comma-separated for several)." + $(if ($lock.Checked -and -not $r) { " It is required when relay settings are locked." })); $_.Cancel = $true
        }
    }
})
if ($f.ShowDialog() -ne 'OK') { return }

$name = ($org.Text -replace '[\p{Cc}]', '').Trim()
$slug = ($name -replace '[^\p{L}\p{N}]+', '-').Trim('-').ToLower()
if (-not $slug) { $slug = "org" }
$dir = Join-Path $root "branding\$slug"
New-Item -ItemType Directory -Force $dir | Out-Null
$devName = ($dev.Text -replace '[\p{Cc}]', '').Trim(); if (-not $devName) { $devName = 'Toolveriq' }
$json = [ordered]@{ organization = $name; maxConcurrentUsers = [int]$users.Value; developedBy = $devName; relayLocked = [bool]($lock.Checked -and $relay.Text.Trim()) } | ConvertTo-Json -Compress
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
# Relay settings go to the build through environment variables (not the command line, which other processes can read); they are cleared afterwards.
# The access key is never written into the branding folder.
$env:RT_DEFAULT_RELAY = $relay.Text.Trim(); $env:RT_DEFAULT_RELAY_FP = $fp.Text.Trim(); $env:RT_DEFAULT_RELAY_KEY = $key.Text.Trim()
try { Build $dir }
finally { Remove-Item Env:RT_DEFAULT_RELAY, Env:RT_DEFAULT_RELAY_FP, Env:RT_DEFAULT_RELAY_KEY -ErrorAction SilentlyContinue }
