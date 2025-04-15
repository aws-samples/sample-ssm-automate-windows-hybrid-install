<#
This PowerShell script completes the following task on your utility server

1 - Connects to SSM Service and creates a hybrid activation
2 - Opens automation script in local folder and updates activation code and ID
3 - Copies the updates script to shared folder location that will be referened in the group policy deployment

Script output is logged to %TEMP%\ssm\ssm-automate-script.log

#>


# Script Settings
$SharedFolder = "\\servername\foldername"
$LocalFolder = "c:\scripts"
$Region = "us-west-2"
$Dir = Join-Path -Path $env:TEMP -ChildPath "ssm"
$RegistrationLimit = 500
$HybridActivationRole = "SSMHybridNodeRole"
$CurrentDateTime = Get-Date -format yyyy-MM-dd-HH:mm:ss

try {
    # Start logging terminal commands
    Start-Transcript -Path (Join-Path -Path $Dir -ChildPath "\ssm-automate-script-$CurrentDateTime.log")
    Write-Output "Logging started"
    $ProgressPreference = 'SilentlyContinue'

    # Set TLS version to 1.3, verify and install NuGet Provider if not installed
    [System.Net.ServicePointManager]::SecurityProtocol = "TLS13"
    Write-Output "Set TLS version to 1.3"
    Get-PackageProvider -Name NuGet -Force
    Set-Location $LocalFolder
    Write-Output "Set path to $LocalFolder"

    # Verify AWS Tools SSM module is installed and install to local user profile if it is not, then import module
    if ((Get-Module -Name AWS.Tools.SimpleSystemsManagement -ListAvailable).version -le [System.Version]"4.0") {
        Install-Module -Name AWS.Tools.SimpleSystemsManagement -Scope CurrentUser -AllowClobber -Force
        Write-Output "SSM PowerShell module installed in current user context"
    }
    # Temporarily add local user scope path to PSModulePath for import
    $env:PSModulePath += ";$($Home)\Documents\WindowsPowerShell\Modules"
    Import-Module -Name AWS.Tools.SimpleSystemsManagement
    Write-Output "SSM PowerShell module successfully imported"

    # Create SSM Hybrid Activation
    $Activation = New-SSMActivation -Description "Automated hybrid activations for Windows systems" -IamRole $HybridActivationRole -RegistrationLimit $RegistrationLimit -Region $Region
    $ActivationID = $Activation.ActivationId
    $ActivationCode = $Activation.ActivationCode
    Write-Output "Generated new activation"

    # Update variables and copy it to automation folder
    $ScriptContent = "`$Code = '{0}'`r`n`$ID = '{1}'" -f $ActivationCode, $ActivationID
    Set-Content -Path 'win-ssm-variables.ps1' -Value $ScriptContent
    Write-Output "Updated variables script with new activation ID and activation code"

    # Copy script to shared folder
    Copy-Item -Path win-ssm-variables.ps1 -Destination $SharedFolder
    Remove-Item -Path win-ssm-variables.ps1
    Write-Output "Copied updated variables script to $SharedFolder"

    #Remove variables and clear garbage
    Remove-Variable -Name Activation,ActivationID,ActivationCode,ScriptContent -ErrorAction SilentlyContinue
    [System.GC]::Collect()

    # Stop Logging
    Stop-Transcript
}

catch {
    Write-Error "Error: $_"
    Stop-Transcript
}