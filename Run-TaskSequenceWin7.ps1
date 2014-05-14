#=============================================
# Script Name: Run-TaskSequenceWin7.ps1
# Created: May 14, 2014
# Revised: N/A
# Author: t0rqued
# Company: redacted
# Email: redacted
#=============================================
# Purpose: Kick off a task sequence as defined in the variable section and cleanup some settings from the script that created this one
# Intended: As part of CUSTOM TASK SEQUENCE, Enable-AutoLogonWinPE.ps1 will configure the autologon required for this to aid in zero touch deployment
# Requirements: A functional task sequence
#*=============================================

#region Configuration Variables
$wdsServer = "Server"
$deploymentShare = "DeploymentShare$"
$localUser = "UserWithAccessToDS"
$tasksequenceID = "SEQID"
$fullUser = "$wdsServer\$localUser"
$localPass = "ThePassword" | ConvertTo-SecureString -AsPlainText -Force
$Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $fullUser, $localPass
$FileName = "ITUtilities"
#endregion

Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultDomainName -Value "" -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUserName -Value "" -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultDomainName -Value "" -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value "0" -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name ForceAutoLogon -Value "0" -Force

if ($PSVersionTable.PSVersion.Major -ge 3) {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare" -Credential $Credentials
} else {
    Write-Warning "You don't have PowerShell 3 or greater, sad day...`nGoing to try to connect to the deployment share anyway..."
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare"
}

Remove-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce -Name "RunLiteTouch" -ErrorAction SilentlyContinue

& S:\scripts\litetouch.vbs "/tasksequenceID:$tasksequenceID" "/skiptasksequence:YES" "/rulesfile:\\$wdsServer\$deploymentShare\Control\CustomSettings.ini"

If (Test-Path C:\$FileName -ErrorAction SilentlyContinue) { Remove-Item -Path C:\$FileName -Recurse -Force } else {continue}