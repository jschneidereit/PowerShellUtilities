#=============================================
# Script Name: Enable-AutoLogonWinPE.ps1
# Created: May 14, 2014
# Revised: N/A
# Author: Jim Schneidereit
# Company: redacted
# Email: redacted
#=============================================
# Purpose: To automatically reboot into windows 7 from winpe and run specified script
# Intended: As part of CUSTOM TASK SEQUENCE
# Requirements: PowerShell and .NET included in WinPE image
# Requirements Cont.: Place a target script in your script root in MDT, or disable related lines of code if you just want the autologon functionality
#*=============================================

REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM

$localadminpass = ""
$localComputer = (Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Control\ComputerName\ComputerName).computername
$localDirectory = "ITUtilities"
$copyScript = "runLiteTouch.ps1"
$exPolicy = "Unrestricted"

$LogonHash = @{ 
    AutoAdminLogon = [pscustomobject]@{ Name = "AutoAdminLogon"; Value = "1"; Type = "String" }
    ForceAutoLogon = [pscustomobject]@{ Name = "ForceAutoLogon"; Value = "1"; Type = "String" }
    DefaultDomainName = [pscustomobject]@{ Name = "DefaultDomainName"; Value = $localComputer; Type = "String" }
    DefaultUserName = [pscustomobject]@{ Name = "DefaultUserName"; Value = "Administrator"; Type = "String" }
    DefaultPassword = [pscustomobject]@{ Name = "DefaultPassword"; Value = $localadminpass; Type = "String" }
    AutoLogonCount = [pscustomobject]@{ Name = "AutoLogonCount"; Value = 5; Type = "DWord" }
}

function Configure-RegistryProperty($Node, $Name, $Value, $Type) { 
    if (!(Get-ItemProperty $Node -Name $Name -ErrorAction SilentlyContinue)) {
        New-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    } else {
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    }
}


if (!(Test-Path "D:\$localDirectory")) { New-Item -Path D:\ -Name $localDirectory -ItemType Directory} else { continue }
Copy-Item -Path "$tsenv:deployroot\Scripts\$copyScript" -Destination "D:\$localDirectory" -Force
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\ScriptedDiagnostics' -Name ExecutionPolicy -Value $exPolicy -ErrorAction SilentlyContinue -Force
New-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name RunLiteTouch -Value "C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -Command `"`& `'C:\$localDirectory\$copyScript`'`"" -Force

if (Test-Path HKLM:\MNTSOFTWARE\ -ErrorAction SilentlyContinue) {
    $32Node = 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $32Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} else { 
    Continue
}

if (Test-Path HKLM:\MNTSOFTWARE\Wow6432Node\ -ErrorAction SilentlyContinue) {
    $64Node = 'HKLM:\MNTSOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $64Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} else { 
    Continue
}
