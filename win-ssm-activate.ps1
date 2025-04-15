<#
This PowerShell script completes the following tasks on Windows Systems

1 - Checks for the AWS Systems Manager agent service on the system and installs if it is not present
2 - Activates the AWS Systems Manager agent with a hybrid activation
3 - Validates the install

Script output is logged to %TEMP%\ssm\ssm-activate.log

#>

# Script Settings
$Region = "us-west-2"
$Dir = Join-Path -Path $env:TEMP -ChildPath "ssm"
$SharedFolder = "\\servername\foldername"
$CurrentDateTime = Get-Date -format yyyy-MM-dd-HH:mm:ss

try {
    # Start logging terminal commands
    Start-Transcript -Path (Join-Path -Path $Dir -ChildPath "\ssm-activate-script-$CurrentDateTime.log")
    Write-Output "Logging started"
    $ProgressPreference = 'SilentlyContinue'

    # Import dynamic variables for activation ID and activation code
    . $SharedFolder\win-ssm-variables.ps1
    Write-Output "Imported variables for Activation"

    # Set TLS version to 1.3, verify and install NuGet Provider if not installed, set location to tmp directory
    [System.Net.ServicePointManager]::SecurityProtocol = 'TLS13'
    Write-Output "Set TLS version to 1.3"
    Get-PackageProvider -Name NuGet -Force
    Set-Location $Dir
    Write-Output "Set path to $Dir"

    # Verify AWS Tools SSM module is installed and install to local user profile if it is not, then import module
    if ((Get-Module -Name AWS.Tools.SimpleSystemsManagement -ListAvailable).version -le [System.Version]"4.0") {
        Install-Module -Name AWS.Tools.SimpleSystemsManagement -Scope CurrentUser -AllowClobber -Force
        Write-Output "SSM PowerShell module installed in current user context"
    }
    # Temporarily add local user scope path to PSModulePath for import
    $env:PSModulePath += ";$($Home)\Documents\WindowsPowerShell\Modules"
    Import-Module -Name AWS.Tools.SimpleSystemsManagement
    Write-Output "SSM PowerShell module successfully imported"

    # Download 64 bit installer
    if ([System.Environment]::Is64BitOperatingSystem -eq 'True')
    {
        Invoke-WebRequest -Uri "https://amazon-ssm-$region.s3.$region.amazonaws.com/latest/windows_amd64/ssm-setup-cli.exe" -Outfile (Join-Path -Path $Dir -ChildPath "\ssm-setup-cli.exe")
    }

    # Download 32 bit installer
    elseif ([System.Environment]::Is64BitOperatingSystem -eq 'False')
    {
        Invoke-WebRequest -Uri "https://amazon-ssm-$region.s3.$region.amazonaws.com/latest/windows_386/ssm-setup-cli.exe" -Outfile (Join-Path -Path $Dir -ChildPath "\ssm-setup-cli.exe")
    }
    
    # Undefined OS/Error Catching
    else {
        Write-Error "Undefined OS architecture - script halted"
        Stop-Transcript
        throw "Undefined OS Architecture - script halted"
    }

    # Install and register SSM agent
    Start-Process -FilePath "ssm-setup-cli.exe" -ArgumentList "-register","-activation-code=`"$Code`"","-activation-id=`"$ID`"","-region=`"$Region`"" -Wait
    Remove-Item -Path ssm-setup-cli.exe
    Write-Output "SSM Agent Installed"

    # Validate install 
    Get-Service -Name "AmazonSSMAgent"
    Write-Output "Verified SSM Agent installed and running"

    Remove-Variable -Name Code,Id -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    
    # Stop Logging
    Stop-Transcript
}
catch {
    Write-Error "Error: $_"
    Stop-Transcript
}