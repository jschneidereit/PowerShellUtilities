#=============================================
# Script Name: Enable-AutoLogonWinPE.ps1
# Created: May 14, 2014
# Revised: July 25, 2014
# Author: Jim Schneidereit
# URL: https://github.com/jschneidereit/PowerShellUtilities/tree/master/MDT
#=============================================
# Purpose: To automatically reboot into windows 7 from winpe and run specified script
# Intended: As part of CUSTOM TASK SEQUENCE
# Requirements: PowerShell and .NET included in WinPE image
# Requirements Cont.: Place a target script in your script root in MDT, or disable related lines of code if you just want the autologon functionality
#*=============================================

#region Variables
#region Configurable Variables
$localadminpass = ""
$localDirectory = "ITUtilities"
$copyScript = "Run-TaskSequenceWin7.ps1"
$Domain = ""

#use a comma separated string for multiple emails: "email1@domain.com, email2@domain.com"
$AdminEmails = ""
$AdminOutEmail = ""
$SMTPServer = ""
#endregion

REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM

$localComputer = (Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Control\ComputerName\ComputerName).computername
$DomainKey = ((Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Services\Tcpip\Parameters -Name Domain).Domain).ToUpper()

$LogonHash = @{ 
    AutoAdminLogon = [pscustomobject]@{ Name = "AutoAdminLogon"; Value = "1"; Type = "String" }
    ForceAutoLogon = [pscustomobject]@{ Name = "ForceAutoLogon"; Value = "1"; Type = "String" }
    DefaultDomainName = [pscustomobject]@{ Name = "DefaultDomainName"; Value = $localComputer; Type = "String" }
    DefaultUserName = [pscustomobject]@{ Name = "DefaultUserName"; Value = "Administrator"; Type = "String" }
    DefaultPassword = [pscustomobject]@{ Name = "DefaultPassword"; Value = $localadminpass; Type = "String" }
    AutoLogonCount = [pscustomobject]@{ Name = "AutoLogonCount"; Value = 10; Type = "DWord" }
}

#endregion

#region Logging

$Global:LogMessage = @()
$Global:ErrorCount = 0

#not currently in use
Function New-HardwareLog {
    $HardwareLog = New-Object PSObject
    $HardwareLog | Add-Member -type NoteProperty -name SerialNumber -Value ((gwmi win32_bios).SerialNumber)
    $HardwareLog | Add-Member -type NoteProperty -name Make -Value ((gwmi win32_ComputerSystem).Manufacturer)
    $HardwareLog | Add-Member -type NoteProperty -name Model -Value ((gwmi win32_ComputerSystem).Model)
    $HardwareLog | Add-Member -type NoteProperty -name LogDate -Value (Get-Date -Format g)
    Return $HardwareLog 
}

Function New-Error ($Value) {
    Write-Error $Value
    $Global:ErrorCount += 1
    Return ("ERROR: $Value`n`n").ToUpper()
}

Function New-Log ($Value) {
    Write-Host $Value
    Return "LOG: $Value`n`n"
}

Function Complete-Log ($Content, $Errors, $smtp, $to, $from, $subject) {
    $MessagePriority = "Normal"
    if ($Errors -ge 1) { $MessagePriority = "High" }

    $outMessage = New-Object System.Net.Mail.MailMessage $from, $to
    $outMessage.Subject = $subject
    $outMessage.IsBodyHtml = $false
    $outMessage.Priority = $MessagePriority
    $outMessage.Body = $Content

    $smtpObject = New-Object Net.Mail.SmtpClient($smtp)
    $smtpObject.Send($outMessage)
    
}

$HardwareArray += (New-HardwareLog)

#endregion

function Configure-RegistryProperty($Node, $Name, $Value, $Type) { 
    if (!(Get-ItemProperty $Node -Name $Name -ErrorAction SilentlyContinue)) {
        $Global:LogMessage += (New-Log "$Name registry key does not exist, creating it now")
        New-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    } else {
        $Global:LogMessage += (New-Log "$Name registry key found, setting it's value now")
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    }
}

function Verify-RegistryConnection ($Path) {
    Write-Host "Waiting for registry..."
    if(! (Test-Path $Path -ErrorAction SilentlyContinue)) {
        $Global:LogMessage += (New-Error "The registry is not there, attempting to mount it again.")
        REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
        REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM
    }

    if (! (Test-Path $Path -ErrorAction SilentlyContinue)) {
        $Global:LogMessage += (New-Error "Connection to registry failed, did you unencrypt the drive? Try again if not.")
    } else {
        $Global:LogMessage += (New-Log "Connection to registry $Path successful")
    }
}

function Verify-DomainDisconnect ($Domain, $Key) {
    if ($Key -eq $Domain) {
        $Global:LogMessage += (New-Error "There are still registry keys pointing to $Domain, if you removed from the domain ignore this message.`n Otherwise, please remove this workstation from the domain and try again.")
    } elseif ((!($Key)) -or ($Key -eq "")) {
        $Global:LogMessage += (New-Log "The workstation is not on the specified domain $Domain")
    } else {
        $Global:LogMessage += (New-Error "Something might be weird with the domain registry settings on this machine, please contact the Administrator")
    }
}


<# ### Could be useful for future itterations ###
if (Test-Path "$tsenv:deployroot\Tools\Modules\ZTIUtility") {
    Import-Module $tsenv:deployroot\Tools\Modules\ZTIUtility\ZTIUtility.psm1
}
#>

Verify-RegistryConnection 'HKLM:\MNTSOFTWARE\'
Verify-RegistryConnection 'HKLM:\MNTSYSTEM\'
Verify-DomainDisconnect -Domain $Domain -Key $DomainKey

<# Configure 32 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\MNTSOFTWARE\ -ErrorAction SilentlyContinue) {
    $32Node = 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $32Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }

    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\ScriptedDiagnostics' -Name "ExecutionPolicy" -Value "Unrestricted" -Type "String"
    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' -Name "ExecutionPolicy" -Value "Unrestricted" -Type "String"
    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name "Run-TaskSequenceWin7" `
        -Value "C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -Command `"`& `'C:\$localDirectory\$copyScript`'`"" -Type "String"
} else { 
    $Global:LogMessage += (New-Error "HLKM:\MNTSOFTWARE couldn't be found, this issue needs to be resolved and then try again")
}

<# Configure 64 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\MNTSOFTWARE\Wow6432Node\ -ErrorAction SilentlyContinue) {
    $64Node = 'HKLM:\MNTSOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $64Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} elseif (!(Test-Path HKLM:\MNTSOFTWARE)) { 
    $Global:LogMessage += (New-Error "HLKM:\MNTSOFTWARE couldn't be found, this issue needs to be resolved and then try again")
} else {
    $Global:LogMessage += (New-Log "HLKM:\MNTSOFTWARE\Wow6432Node\ couldn't be found, probably a 32 bit machine...")
}

<# Adds a directory to the C drive to store the targetted powershell script found in the scripts directory of the deployment share to run at autologon  #>
if (!(Test-Path "D:\$localDirectory" -ErrorAction SilentlyContinue)) { 
    $Global:LogMessage += (New-Log "C:\$localDirectory was not found, creating it now")
    New-Item -Path D:\ -Name $localDirectory -ItemType Directory
} else { 
    $Global:LogMessage += (New-Log "Found C:\$localDirectory")
}

<# Copies the targetted file "runLiteTouch.ps1" to the directory created on the C drive (or D while in WinPE) #>
if (!(Test-Path "$tsenv:deployroot\Scripts\")) { 
    $Global:LogMessage += (New-Error "Could not connect to the deploy root to copy Run-TaskSequenceWin7.ps1")
} else {
    Copy-Item -Path "$tsenv:deployroot\Scripts\$copyScript" -Destination "D:\$localDirectory" -Force
    $Global:LogMessage += (New-Log "Copied $copyScript yay!")
}

Complete-log -Content $Global:LogMessage -Errors $Global:ErrorCount -smtp $SMTPServer -to $AdminEmails -from $AdminOutEmail -subject "WinPE set autologon Log - $((gwmi win32_bios).SerialNumber)"