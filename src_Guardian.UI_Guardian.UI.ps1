param([string]$ConfigPath = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$log = Join-Path $root 'artifacts\guardian-events.jsonl'

$form = New-Object Windows.Forms.Form
$form.Text = 'WLAN Guardian'
$form.Width = 900
$form.Height = 600
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(760, 480)

$label = New-Object Windows.Forms.Label
$label.Text = 'WLAN GUARDIAN'
$label.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($label)

$status = New-Object Windows.Forms.Label
$status.Text = 'STATUS: unbekannt'
$status.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(20, 75)
$form.Controls.Add($status)

$text = New-Object Windows.Forms.TextBox
$text.Multiline = $true
$text.ReadOnly = $true
$text.ScrollBars = 'Vertical'
$text.Location = New-Object System.Drawing.Point(20, 125)
$text.Size = New-Object System.Drawing.Size(840, 350)
$form.Controls.Add($text)

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    if (Test-Path -LiteralPath $log) {
        $lines = @(Get-Content -LiteralPath $log -Tail 1 -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 0) {
            foreach ($line in $lines) {
                try {
                    $obj = $line | ConvertFrom-Json
                    $status.Text = "STATUS: $($obj.GuardianState)"
                    $text.Text = $obj | ConvertTo-Json -Depth 8
                }
                catch {}
            }
        }
    }
})

$timer.Start()
$form.Add_FormClosed({ $timer.Stop() })
[void]$form.ShowDialog()