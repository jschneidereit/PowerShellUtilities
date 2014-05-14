#=============================================
# Script Name: Enable-AutoLogonWinPE.ps1
# Created: May 14, 2014
# Revised: N/A
# Author: t0rqued
# Company: redacted
# Email: redacted
#=============================================
# Purpose: To automatically reboot into windows 7 from winpe and run specified script
# Intended: As part of CUSTOM TASK SEQUENCE
# Requirements: PowerShell and .NET included in WinPE image
# Requirements Cont.: Place a target script in your script root in MDT, or disable related lines of code if you just want the autologon functionality
#*=============================================

#region Configuration Variables
$Localadmin = "Administrator"
$Localadminpass = "localadminpasswordhere"
$ScriptName = "runscripthere.ps1"
$ExecutionPolicy = "Unrestricted"
$FileName = "ITUtilities"
#endregion

#biggest assumption of script (that you are in the "C" drive) fix later
REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM

if (!(Test-Path D:\$FileName)) { New-Item -Path D:\ -Name $FileName -ItemType Directory} else { continue }

Copy-Item -Path $tsenv:deployroot\Scripts\$ScriptName -Destination D:\$FileName -Force

$LocalComputer = (Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Control\ComputerName\ComputerName).computername

#Force admin auto logon
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value "1" -Type String -Force
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name ForceAutoLogon -Value "1" -Type String -Force
#Set admin auto logon credentials
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultDomainName -Value $LocalComputer -Type String -Force
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUserName -Value $Localadmin -Type String -Force
#Generate and set admin password
New-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value $Localadminpass -Type String -ErrorAction SilentlyContinue -Force
Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value $Localadminpass -Type String -ErrorAction SilentlyContinue -Force
#Sets count of allowed auto logon times
New-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoLogonCount -Value 5 -Type DWord -ErrorAction SilentlyContinue -Force
#Set autorun command for script that was copied from deployment share
New-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name RunLiteTouch -Value "C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -Command `"`& `'C:\$FileName\$ScriptName`'`"" -Force

Set-ItemProperty 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\ScriptedDiagnostics' -Name ExecutionPolicy -Value $ExecutionPolicy -ErrorAction SilentlyContinue -Force