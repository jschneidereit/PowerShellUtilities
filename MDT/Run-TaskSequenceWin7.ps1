#=============================================
# Script Name: Run-TaskSequenceWin7.ps1
# Created: May 14, 2014
# Revised: N/A
# Author: Jim Schneidereit
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


function Verify-NetworkConnection ($Server) {
    $TimeOutCount = 15
    $SecondsSlept = 0
    $Interval = 1

    Write-Host "Waiting for server connection..."
    While ( $SecondsSlept -le $TimeOutCount ) {
        Write-Host "$SecondsSlept . . ."
        if(! (Test-Connection -ComputerName $Server -ErrorAction SilentlyContinue)) {
            
            Start-Sleep -Seconds $Interval
            $SecondsSlept += $Interval
        } else {
            Break
        }
    }
    if (! (Test-Connection -ComputerName $Server -ErrorAction SilentlyContinue)) {
        Write-Warning "Connection to server failed"
    } else {
        Write-Host "Connection to server successful"
    }
}

Verify-NetworkConnection $wdsServer

if ($PSVersionTable.PSVersion.Major -ge 3) {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare" -Credential $Credentials
} else {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare"
}

& S:\scripts\litetouch.vbs "/tasksequenceID:$tasksequenceID" "/skiptasksequence:YES" "/rulesfile:\\$wdsServer\$deploymentShare\Control\CustomSettings.ini"

$32Node = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$64Node = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'

Set-ItemProperty $32Node -Name DefaultDomainName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $32Node -Name DefaultUserName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $32Node -Name DefaultPassword -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $32Node -Name DefaultDomainName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $32Node -Name AutoAdminLogon -Value "0" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $32Node -Name ForceAutoLogon -Value "0" -ErrorAction SilentlyContinue -Force

Set-ItemProperty $64Node -Name DefaultDomainName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $64Node -Name DefaultUserName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $64Node -Name DefaultPassword -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $64Node -Name DefaultDomainName -Value "" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $64Node -Name AutoAdminLogon -Value "0" -ErrorAction SilentlyContinue -Force
Set-ItemProperty $64Node -Name ForceAutoLogon -Value "0" -ErrorAction SilentlyContinue -Force

#Remove-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce -Name "RunLiteTouch" -ErrorAction SilentlyContinue
#If (Test-Path C:\$FileName -ErrorAction SilentlyContinue) { Remove-Item -Path C:\$FileName -Recurse -Force } else {continue}

$x = Read-Host "press enter to continue"