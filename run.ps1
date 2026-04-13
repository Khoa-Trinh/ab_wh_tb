# 1. Setup Environment
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$folderPath = $PSScriptRoot
if (-not $folderPath) { $folderPath = Get-Location }

# Helper to verify EXE
function Test-IsRealExe($path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        if ((Get-Item $path).Length -lt 10KB) { return $false }
        $fs = [System.IO.File]::OpenRead($path)
        $buf = New-Object byte[] 2
        $read = $fs.Read($buf, 0, 2)
        $fs.Close()
        if ($read -lt 2) { return $false }
        # Check for MZ (EXE) or PK (ZIP)
        return (($buf[0] -eq 0x4D -and $buf[1] -eq 0x5A) -or ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B))
    }
    catch { return $false }
}

# Session Data
$SavedCookie = "cf_clearance=22AuyLeFmRsXrVRGH0gStcFzeMUI5snc6vkz4bAT8KE-1776090317-1.2.1.1-INs_yv08vb8LuF.fKUavcwds3qe8NC3JMxutU1BKQ2wVpcYQmDWHWQLukXui3jOlSwp.99tpoD0QHxL2EtVEXG8FrsKqxD3UU.rID9QJh4ttM_6We1bc1KGMJcE.DOLc44bcA9.y3OPCMibDgK5_MJvsYUEIs2Cw1XFLNuE4DPHdmkjJFkirdmZJVm.moWyKljqInOvMvveLpyP.971Qqrl1ov_7WOdwjr__KYHH_Ieg5TRHJpw_RmOggze3mqdl6djCv92PdZHv.j21fndK7YsYlL62Le8Ceysa6NQgQHlzHaSQ2Oq.3HemMx.3XWAyqc6SwXQCKqHVD0C9.wDlIg"
$SavedUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
$SavedSecCH = @{
    "sec-ch-ua"                   = ''
    "sec-ch-ua-full-version-list" = ''
    "sec-ch-ua-platform-version"  = ''
    "sec-ch-ua-mobile"            = '?0'
    "sec-ch-ua-full-version"      = ''
    "sec-ch-ua-model"             = ''
    "sec-ch-ua-bitness"           = ''
    "sec-ch-ua-arch"              = ''
    "sec-ch-ua-platform"          = ''
}

$downloadUrl = "https://undetek.com/download/download.php"

# --- THE AUTO-REFRESH ENGINE ---
function Show-BypassTips {
    param($url)
    Write-Host "`n[!] CLOUDFLARE BLOCK DETECTED." -ForegroundColor Red
    Write-Host "Opening browser..." -ForegroundColor Cyan
    Start-Process $url
    
    Write-Host "`nStep 1: Solve the challenge in your browser." -ForegroundColor White
    Write-Host "Step 2: Copy the full cURL of the download request (F12 > Network > Right Click > Copy as cURL)" -ForegroundColor White
    Write-Host "        OR copy the 'cf_clearance' cookie value." -ForegroundColor Gray
    Write-Host "`n[LISTENING] I will resume automatically when you copy the info..." -ForegroundColor Yellow
    Write-Host "            (Or type 'm' and Enter to paste it manually)"
    
    $lastClip = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'm') {
                Write-Host "`n[Manual Mode] Paste the full cURL or Cookie below and press Enter:" -ForegroundColor Cyan
                $manualInput = Read-Host ">"
                if ($manualInput) { return Parse-SessionInput $manualInput }
            }
        }

        $clip = Get-Clipboard -Raw -ErrorAction SilentlyContinue
        if ($clip -and $clip -ne $lastClip -and $clip.Length -gt 20) {
            $lastClip = $clip
            $parsed = Parse-SessionInput $clip
            if ($parsed) { return $parsed }
        }
        Start-Sleep -Milliseconds 500
    }
}

function Parse-SessionInput($inputStr) {
    if (!$inputStr) { return $null }
    $s = [string]$inputStr
    
    $out = @{ Cookie = $null; UA = $null; Headers = @{} }
    
    # 1. Extract cf_clearance (Priority)
    # This regex catches it inside -b flags, -H 'cookie: ...', raw cookie strings, etc.
    if ($s -match "(cf_clearance=[^;'""]+)") {
        $out.Cookie = $Matches[1].Trim()
    }

    # 2. Extract User-Agent (Don't stop at semicolons as UAs contain them)
    if ($s -match "(?i)User-Agent:\s*([^'""\r\n]+)") {
        $out.UA = $Matches[1].Trim()
    }
    # Also check -A flag in cURL
    if ($s -match "(?i)-A\s+['""]([^'""\r\n]+)['""]") {
        $out.UA = $Matches[1].Trim()
    }

    # 3. Extract Sec-Ch headers (Optional but helpful)
    $secRegex = "(?i)(sec-ch-ua[^: ]*):\s*([^'""\r\n]+)"
    $matches_sec = [regex]::Matches($s, $secRegex)
    foreach ($m in $matches_sec) {
        $name = $m.Groups[1].Value.ToLower().Trim()
        $val = $m.Groups[2].Value.Trim()
        # Clean up quotes if present
        $val = $val -replace "^['""]|['""]$", ""
        $out.Headers[$name] = $val
    }

    if ($out.Cookie) {
        Write-Host "`n[+] Session Data Captured!" -ForegroundColor Green
        return $out
    }
    return $null
}

function Update-ScriptPersistence($sessionData) {
    $scriptLines = Get-Content $PSCommandPath
    $newLines = @()
    $skipping = $false

    foreach ($line in $scriptLines) {
        if ($line -match '^\$SavedCookie =') {
            $newLines += "`$SavedCookie = `"$($sessionData.Cookie)`""
            continue
        }
        if ($sessionData.UA -and $line -match '^\$SavedUA =') {
            $newLines += "`$SavedUA = `"$($sessionData.UA)`""
            continue
        }
        if ($line -match '^\$SavedSecCH = @\{') {
            $newLines += $line
            foreach ($key in $sessionData.Headers.Keys) {
                $newLines += "    ""$key"" = '$($sessionData.Headers[$key])'"
            }
            $skipping = $true
            continue
        }
        if ($skipping -and $line -match '^\}') {
            $skipping = $false
            $newLines += $line
            continue
        }
        if (-not $skipping) { $newLines += $line }
    }
    $newLines | Set-Content $PSCommandPath -Encoding UTF8
}
function Get-ServerInfo {
    param($cf, $ua, $url)

    try {
        # -I gets headers. If -L is included, curl shows headers for ALL redirects in the chain.
        $curlArgs = @("-s", "-L", "-I", "-H", "Cookie: $cf", "-A", $ua)
        foreach ($k in $SavedSecCH.Keys) { 
            if ($SavedSecCH[$k]) { $curlArgs += @("-H", "${k}: $($SavedSecCH[$k])") } 
        }
        $curlArgs += $url
        $headers = & curl.exe $curlArgs 2>$null
        
        # 1. Check for Maintenance/Redirects (301, 302, 307)
        # If the first status line is a redirect, we treat it as maintenance for this script.
        $firstLine = $headers | Select-Object -First 1
        if ($firstLine -match "HTTP/.* (301|302|307)") {
            return @{ Status = "Maintenance"; Version = $null }
        }

        # 2. Check for success and filename
        $disp = $headers | Select-String "Content-Disposition:"
        if ($disp -match 'filename="undetek-v(?<v>[\d\.]+)\.(exe|zip)"') {
            return @{ Status = "OK"; Version = $Matches['v'] }
        }
    }
    catch {}
    return @{ Status = "Error"; Version = $null }
}

try {
    Get-Process | Where { $_.ProcessName -like "*undetek-v*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "--- Health Check ---" -ForegroundColor Cyan
    
    # 1. Check Server for Latest Version
    $info = Get-ServerInfo -cf $SavedCookie -ua $SavedUA -url $downloadUrl
    if ($info.Status -eq "Maintenance") {
        Write-Host "`n[!] The download page is currently down for maintenance (302)." -ForegroundColor Yellow
        Write-Host "The website is likely updating their EXE. Please try again later." -ForegroundColor White
        Read-Host "`nDone. Press Enter to exit"; exit
    }

    $latestVersion = $info.Version
    if ($latestVersion) {
        Write-Host "Server Version: v$latestVersion" -ForegroundColor Gray
        $exeName = "undetek-v$latestVersion.exe"
    }
    else {
        Write-Host "[!] Could not verify latest version (Cloudflare block?)" -ForegroundColor Gray
        $newData = Show-BypassTips -url "https://undetek.com"
        if ($newData) {
            $SavedCookie = $newData.Cookie
            if ($newData.UA) { $SavedUA = $newData.UA }
            if ($newData.Headers.Count -gt 0) { $SavedSecCH = $newData.Headers }
            Update-ScriptPersistence $newData
            # Try once more to get version with fresh cookies
            $info = Get-ServerInfo -cf $SavedCookie -ua $SavedUA -url $downloadUrl
            $latestVersion = $info.Version
        }
        
        if ($latestVersion) {
            $exeName = "undetek-v$latestVersion.exe"
        }
        else {
            $exeName = "undetek-v10.25.exe"
        }
    }

    $exePath = Join-Path $folderPath $exeName
    
    if (Test-Path $exePath) {
        if (-not (Test-IsRealExe $exePath)) {
            Write-Host "Local file invalid, removing..." -ForegroundColor Yellow
            Remove-Item $exePath -Force
        }
    }
    
    Get-ChildItem -Path $folderPath -Filter "undetek-v*.exe" | Where-Object { $_.Name -ne $exeName } | Remove-Item -Force

    if (-not (Test-Path $exePath)) {
        $success = $false
        while (-not $success) {
            Write-Host "Attempting download..." -ForegroundColor Yellow
            
            $curlArgs = @("-s", "-L", "--compressed", "-H", "Cookie: $SavedCookie", "-A", $SavedUA)
            foreach ($k in $SavedSecCH.Keys) { 
                if ($SavedSecCH[$k]) { $curlArgs += @("-H", "${k}: $($SavedSecCH[$k])") } 
            }
            $curlArgs += @("-H", "Referer: https://undetek.com/free-cs2-cheats-download/")
            $curlArgs += @("--output", $exePath, $downloadUrl)

            & curl.exe @curlArgs
            
            if (Test-IsRealExe $exePath) {
                # ZIP Extraction Logic
                $fileBytes = [System.IO.File]::ReadAllBytes($exePath)
                if ($fileBytes.Count -ge 2 -and $fileBytes[0] -eq 0x50 -and $fileBytes[1] -eq 0x4B) {
                    Write-Host "ZIP Archive detected. Extraction..." -ForegroundColor Cyan
                    $tempZip = Join-Path $folderPath "temp.zip"
                    Move-Item $exePath $tempZip -Force
                    $extractPath = Join-Path $folderPath "temp_ext"
                    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
                    New-Item -ItemType Directory $extractPath | Out-Null
                    Expand-Archive $tempZip -DestinationPath $extractPath -Force
                    $realExe = Get-ChildItem $extractPath -Filter "*.exe" -Recurse | Sort-Object Length -Descending | Select -First 1
                    if ($realExe) {
                        Move-Item $realExe.FullName $exePath -Force
                        $success = $true
                    }
                    Remove-Item $tempZip, $extractPath -Recurse -Force
                }
                else { $success = $true }
            }
            else {
                if (Test-Path $exePath) {
                    # If it's HTML, it might be printing it. We remove it and prompt.
                    Remove-Item $exePath -Force
                }
                $newData = Show-BypassTips -url "https://undetek.com"
                if ($newData) {
                    $SavedCookie = $newData.Cookie
                    if ($newData.UA) { $SavedUA = $newData.UA }
                    if ($newData.Headers.Count -gt 0) { $SavedSecCH = $newData.Headers }
                    Update-ScriptPersistence $newData
                }
                else { exit }
            }
        }
    }

    Write-Host "Health Check: OK ($exeName is ready)." -ForegroundColor Green
    Write-Host "Launching $exeName..." -ForegroundColor Yellow
    # NOTE: Some loaders open a browser tab on launch (announcements/login). 
    # We wait longer to let that finish so we can steal focus back.
    Start-Process -FilePath $exePath
    Write-Host "Waiting for loader to initialize..." -ForegroundColor Gray
    Start-Sleep -Seconds 4

    
    # 2. Get and Inject PIN
    Write-Host "`n--- PIN Retrieval ---" -ForegroundColor Cyan
    $pinSuccess = $false
    while (-not $pinSuccess) {
        try {
            $pUrl = "https://undetek.com/download/undetek/getpin-53478634576234987435.php?_=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
            Write-Host "Requesting PIN..." -ForegroundColor Gray

            # Use curl.exe for better compatibility across PS5 and PS7 (especially on Lite Windows)
            $pCurlArgs = @("-s", "-L", "-H", "Cookie: $SavedCookie", "-A", $SavedUA)
            $pCurlArgs += @("-H", "Referer: https://undetek.com/free-cs2-cheats-download/")
            foreach ($k in $SavedSecCH.Keys) {
                if ($SavedSecCH[$k]) { $pCurlArgs += @("-H", "${k}: $($SavedSecCH[$k])") }
            }
            
            $pin = (& curl.exe @pCurlArgs $pUrl).Trim()
            
            if ($pin -match "<html" -or $pin -match "Cloudflare" -or $pin -match "Ray ID" -or $pin -match "403 Forbidden") { 
                throw "Cloudflare block or 403 detected on PIN retrieval." 
            }

            if ($pin -and $pin.Length -lt 20) {
                # Pins are usually short
                Write-Host "PIN found: $pin" -ForegroundColor White
                # P/Invoke for robust window management (needed for Ghost Toolbox/Lite OS)
                $user32Source = @"
                using System;
                using System.Runtime.InteropServices;
                public class User32 {
                    [DllImport("user32.dll")]
                    [return: MarshalAs(UnmanagedType.Bool)]
                    public static extern bool SetForegroundWindow(IntPtr hWnd);
                    [DllImport("user32.dll")]
                    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
                    [DllImport("user32.dll")]
                    public static extern bool IsIconic(IntPtr hWnd);
                }
"@
                if (-not ([System.Management.Automation.PSTypeName]"User32").Type) {
                    Add-Type -TypeDefinition $user32Source
                }

                $ws = New-Object -ComObject WScript.Shell
                $injected = $false
                $startTime = [DateTime]::Now
                Write-Host "--- Injection Process ---" -ForegroundColor Cyan
                
                # Escape special SendKeys characters in PIN (+, ^, %, ~, (, ), {, })
                $safePin = ""
                foreach ($char in $pin.ToCharArray()) {
                    if ("+^%~(){}[]" -contains $char) { $safePin += "{$char}" }
                    else { $safePin += $char }
                }

                # Security Context Check: Mismatched integrity levels often block SendKeys
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                
                # Compatibility Fix: Using standard IF/ELSE instead of Ternary operator
                if ($isAdmin) { $adminColor = "Green" } else { $adminColor = "Yellow" }
                # Write-Host "[INFO] Elevation: $isAdmin" -ForegroundColor $adminColor

                for ($i = 1; $i -le 60; $i++) {
                    $targetTitle = $null
                    
                    # 1. Process Discovery
                    # We check for the process name matching the versioned name or part of it
                    $procMatch = Get-Process | Where-Object { $_.ProcessName -like "*undetek*" } | Select-Object -First 1
                    
                    if ($null -eq $procMatch) {
                        if ($i % 10 -eq 0) { Write-Host "Searching for loader window... ($i/60)" -ForegroundColor DarkGray }
                    }
                    else {
                        # 2. Title Discovery
                        $titlesToTry = @()
                        if ($procMatch.MainWindowTitle) { 
                            $titlesToTry += $procMatch.MainWindowTitle 
                            # Found Window: $($procMatch.MainWindowTitle)
                        }
                        $titlesToTry += @("Undetek", "Undetek Loader", $exeName, $exeName.Replace(".exe", ""))
                        
                        # 3. Activation Attempt
                        # Strategy A: Try PID activation (Most reliable for WScript)
                        if ($ws.AppActivate($procMatch.Id)) {
                            # AppActivate(PID) success
                            $targetTitle = $procMatch.Id
                        } 
                        # Strategy B: Try Title activation
                        elseif ($null -ne $procMatch.MainWindowTitle) {
                            foreach ($t in ($titlesToTry | Select-Object -Unique)) {
                                if (-not $t) { continue }
                                if ($ws.AppActivate($t)) {
                                    # AppActivate(Title) success
                                    $targetTitle = $t
                                    break
                                }
                            }
                        }
                        
                        # Strategy C: P/Invoke Force Focus (The 'Nuke' for Lite OS)
                        if (-not $targetTitle -and $procMatch.MainWindowHandle -ne 0) {
                            # Forcing focus via User32...
                            if ([User32]::IsIconic($procMatch.MainWindowHandle)) {
                                [User32]::ShowWindowAsync($procMatch.MainWindowHandle, 9) # SW_RESTORE
                            }
                            [User32]::SetForegroundWindow($procMatch.MainWindowHandle) | Out-Null
                            Start-Sleep -Milliseconds 500
                            # Check if we can activate it now by title since it's in foreground
                            if ($ws.AppActivate($procMatch.Id)) {
                                $targetTitle = $procMatch.Id
                                # Post-User32 AppActivate success.
                            }
                            else {
                                # Even if AppActivate fails, if we set foreground, SendKeys might still work
                                $targetTitle = "FORCED_BY_USER32"
                            }
                        }
                    }

                    if ($targetTitle) {
                        Write-Host "Window found! Focusing and injecting PIN..." -ForegroundColor Yellow
                        try {
                            if ($targetTitle -ne "FORCED_BY_USER32") {
                                # Double activation 'nudge'
                                $ws.AppActivate($targetTitle) | Out-Null
                                Start-Sleep -Milliseconds 300
                                $ws.AppActivate($targetTitle) | Out-Null
                            }
                            else {
                                # Already focused by User32
                                [User32]::SetForegroundWindow($procMatch.MainWindowHandle) | Out-Null
                            }
                            Start-Sleep -Milliseconds 500
                            
                            # Injection logic
                            $ws.SendKeys("{TAB}")
                            Start-Sleep -Milliseconds 300
                            $ws.SendKeys("^a")
                            Start-Sleep -Milliseconds 100
                            $ws.SendKeys("{BACKSPACE}")
                            Start-Sleep -Milliseconds 200
                            
                            foreach ($char in $safePin.ToCharArray()) {
                                $ws.SendKeys($char)
                                Start-Sleep -Milliseconds 60
                            }
                            
                            Start-Sleep -Milliseconds 500
                            $ws.SendKeys("{ENTER}")
                            
                            Write-Host "[+] Injection successful." -ForegroundColor Green
                            $injected = $true
                            break
                        }
                        catch {
                            Write-Host "[!] Error during injection: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }

                    # Diagnostics if stuck
                    if ($i -eq 20) {
                        # Write-Host "Checking for alternative windows..." -ForegroundColor Yellow
                    }

                    Start-Sleep -Milliseconds 500
                }

                if (-not $injected) {
                    Write-Host "[!] AUTO-INJECTION FAILED." -ForegroundColor Red
                    Write-Host "    Reason: Could not find or focus the loader window." -ForegroundColor White
                    Write-Host "    Help: Check if the loader is running and visible." -ForegroundColor Gray
                    Write-Host "    Manual PIN: $pin" -ForegroundColor Yellow
                }
                $pinSuccess = $true
            }
            else {
                throw "Unexpected PIN response format: $pin"
            }
        }
        catch {
            Write-Host "PIN Access Error: $($_.Exception.Message)" -ForegroundColor Yellow
            $newData = Show-BypassTips -url "https://undetek.com/free-cs2-cheats-download/"
            if ($newData) {
                $SavedCookie = $newData.Cookie
                if ($newData.UA) { $SavedUA = $newData.UA }
                if ($newData.Headers.Count -gt 0) { $SavedSecCH = $newData.Headers }
                Update-ScriptPersistence $newData
            }
            else { break }
        }
    }

}
catch { Write-Host "ERROR: $($_)" -ForegroundColor Red }

Read-Host "`nDone. Press Enter to close"
