﻿function Log([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt"
}

Log "SetupStart, User: $env:USERNAME"

. (Join-Path $PSScriptRoot "settings.ps1")

if (Test-Path -Path "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1") {
    Import-module "C:\demo\navcontainerhelper-dev\NavContainerHelper.psm1" -DisableNameChecking
} else {
    Import-Module -name navcontainerhelper -DisableNameChecking
}

if ("$ContactEMailForLetsEncrypt" -ne "" -and $AddTraefik -ne "Yes") {

    Log "Installing ACME-PS PowerShell Module"
    Install-Module -Name ACME-PS -RequiredVersion "1.1.0-beta" -AllowPrerelease -Force

    Log "Using Lets Encrypt certificate"
    # Use Lets encrypt
    # If rate limits are hit, log an error and revert to Self Signed
    try {
        $plainPfxPassword = [GUID]::NewGuid().ToString()
        $certificatePfxFilename = "c:\ProgramData\navcontainerhelper\certificate.pfx"
        New-LetsEncryptCertificate -ContactEMailForLetsEncrypt $ContactEMailForLetsEncrypt -publicDnsName $publicDnsName -CertificatePfxFilename $certificatePfxFilename -CertificatePfxPassword (ConvertTo-SecureString -String $plainPfxPassword -AsPlainText -Force)

        # Override SetupCertificate.ps1 in container
        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePfxFile, $certificatePfxPassword)
$certificateThumbprint = $cert.Thumbprint
Write-Host "Certificate File Thumbprint $certificateThumbprint"
if (!(Get-Item Cert:\LocalMachine\my\$certificateThumbprint -ErrorAction SilentlyContinue)) {
    Write-Host "Import Certificate to LocalMachine\my"
    Import-PfxCertificate -FilePath $certificatePfxFile -CertStoreLocation cert:\localMachine\my -Password $certificatePfxPassword | Out-Null
}
$dnsidentity = $cert.GetNameInfo("SimpleName",$false)
if ($dnsidentity.StartsWith("*")) {
    $dnsidentity = $dnsidentity.Substring($dnsidentity.IndexOf(".")+1)
}
') | Set-Content "c:\myfolder\SetupCertificate.ps1"

        # Create RenewCertificate script
        ('$CertificatePfxPassword = ConvertTo-SecureString -String "'+$plainPfxPassword+'" -AsPlainText -Force
$certificatePfxFile = "'+$certificatePfxFilename+'"
$publicDnsName = "'+$publicDnsName+'"
Renew-LetsEncryptCertificate -publicDnsName $publicDnsName -certificatePfxFilename $certificatePfxFile -certificatePfxPassword $certificatePfxPassword
Start-Sleep -seconds 30
Restart-NavContainer -containerName navserver -renewBindings
') | Set-Content "c:\demo\RenewCertificate.ps1"

    } catch {
        Log -color Red $_.Exception.Message
        Log -color Red "Reverting to Self Signed Certificate"
    }
}

Log "Installing Az module"
Install-Module Az -Force

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

if ($requestToken) {
    if (!(Get-ScheduledTask -TaskName request -ErrorAction Ignore)) {
        Log "Registering request task"
        $xml = [System.IO.File]::ReadAllText("c:\demo\RequestTaskDef.xml")
        Register-ScheduledTask -TaskName request -User $vmadminUsername -Password $plainPassword -Xml $xml
    }
}

if ("$createStorageQueue" -eq "yes") {
    
    Log "Installing AzTable Module"
    Install-Module AzTable -Force

    $taskName = "RunQueue"
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\RunQueue.ps1"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT5M"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    $task = Register-ScheduledTask -TaskName $taskName `
                           -Action $startupAction `
                           -Trigger $startupTrigger `
                           -Settings $settings `
                           -RunLevel Highest `
                           -User $vmAdminUsername `
                           -Password $plainPassword
    
    $task.Triggers.Repetition.Interval = "PT5M"
    $task | Set-ScheduledTask -User $vmAdminUsername -Password $plainPassword | Out-Null

    Start-ScheduledTask -TaskName $taskName
}

Log "Register RestartContainers Task to start container delayed"
$taskName = "RestartContainers"
$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -file c:\demo\restartcontainers.ps1"
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT5M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
$task = Register-ScheduledTask -TaskName $taskName `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -Settings $settings `
                       -RunLevel Highest `
                       -User $vmadminUsername `
                       -Password $plainPassword

Log "Launch SetupVm"
$onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
Register-ScheduledTask -TaskName SetupVm `
                       -Action $onceAction `
                       -RunLevel Highest `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

Start-ScheduledTask -TaskName SetupVm
