﻿if (!(Test-Path function:Log)) {
  function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
    Write-Host -ForegroundColor $color $line 
  }
}

#Install Choco
Log "Install Choco"
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco feature enable -n allowGlobalConfirmation

Log "Install git"
choco install git --force

Log "Install Edge Insider"
choco install microsoft-edge-insider

Log "Install Chrome"
choco install googlechrome

Log "Install firefox"
choco install firefox

Log "Install Office 365 Business"
choco install office365business

Log "Install PowerBI Desktop"
choco install powerbi

#Add VSCode Extensions
"eamodio.gitlens", "ms-vscode.PowerShell", "heaths.vscode-guid", "github.vscode-pull-request-github", "formulahendry.docker-explorer" | % {
    Log "Install VSCode Extension: $_"
    code --install-extension $_
}

. "C:\DEMO\Settings.ps1"
& "C:\Program Files\GIT\bin\git.exe" config --global core.safecrlf false
& "C:\Program Files\GIT\bin\git.exe" config --global user.email "$($vmAdminUsername)@$($hostName)"
& "C:\Program Files\GIT\bin\git.exe" config --global user.name "$vmAdminUsername"
