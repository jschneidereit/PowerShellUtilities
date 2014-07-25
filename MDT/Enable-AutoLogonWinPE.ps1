#=============================================
# Script Name: Enable-AutoLogonWinPE.ps1
# Created: May 14, 2014
# Revised: July 24, 2014
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
#endregion

REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM

$localComputer = (Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Control\ComputerName\ComputerName).computername
$DomainKey = ((Get-ItemProperty HKLM:\MNTSYSTEM\ControlSet001\Services\Tcpip\Parameters -Name Domain).Domain).ToUpper()
$ErrorAction = 'SilentlyContinue'

$LogonHash = @{ 
    AutoAdminLogon = [pscustomobject]@{ Name = "AutoAdminLogon"; Value = "1"; Type = "String" }
    ForceAutoLogon = [pscustomobject]@{ Name = "ForceAutoLogon"; Value = "1"; Type = "String" }
    DefaultDomainName = [pscustomobject]@{ Name = "DefaultDomainName"; Value = $localComputer; Type = "String" }
    DefaultUserName = [pscustomobject]@{ Name = "DefaultUserName"; Value = "Administrator"; Type = "String" }
    DefaultPassword = [pscustomobject]@{ Name = "DefaultPassword"; Value = $localadminpass; Type = "String" }
    AutoLogonCount = [pscustomobject]@{ Name = "AutoLogonCount"; Value = 5; Type = "DWord" }
}

#endregion

#region Logging

$Message = @()
$ErrorCount = 0

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
    #$ErrorLog = New-Object PSObject
    #$ErrorLog | Add-Member -Type NoteProperty -Name Time -Value (Get-Date -Format T)
    #$ErrorLog | Add-Member -Type NoteProperty -Name ErrorTranscript -Value $Value
    Write-Error $Value
    Return "ERROR: $Value`n"
}

Function New-Log ($Value) {
    #$Log = New-Object PSObject
    #$Log | Add-Member -Type NoteProperty -Name Time -Value (Get-Date -Format T)
    #$Log | Add-Member -Type NoteProperty -Name LogTranscript -Value $Value
    Write-Host $Value
    Return "LOG: $Value`n"
}

Function Complete-Log ($HTML, $ErrorCount, $smtp, $to, $from, $subject) {
    $MessagePriority = "Normal"
    if ($ErrorCount -ge 1) { $MessagePriority = "High" }

    $message = New-Object System.Net.Mail.MailMessage $from, $to
    $message.Subject = $subject
    $message.IsBodyHtml = $true
    $message.Priority = $MessagePriority
    $message.Body = $HTML

    $smtpObject = New-Object Net.Mail.SmtpClient($smtp)
    $smtpObject.Send($message)
    
}

$HardwareArray += (New-HardwareLog)

#endregion

function Configure-RegistryProperty($Node, $Name, $Value, $Type) { 
    if (!(Get-ItemProperty $Node -Name $Name -ErrorAction $ErrorAction)) {
        $Message += (New-Log "$Name registry key does not exist, creating it now")
        New-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
    } else {
        $Message += (New-Log "$Name registry key found, setting it's value now")
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
    }
}

function Verify-RegistryConnection ($Path) {
    $TimeOutCount = 15
    $SecondsSlept = 0
    $Interval = 1

    $Message += (New-Log "Waiting for registry...")

    While ( $SecondsSlept -le $TimeOutCount ) {
        if(! (Test-Path $Path -ErrorAction SilentlyContinue)) {
            $Message += (New-Error "the registry is not there, attempting to mount it again")

            REG LOAD HKLM\MNTSOFTWARE D:\Windows\system32\config\SOFTWARE
            REG LOAD HKLM\MNTSYSTEM D:\Windows\system32\config\SYSTEM

            Start-Sleep -Seconds $Interval

            $SecondsSlept += $Interval
        } else {
            break
        }
    }
    if (! (Test-Path $Path -ErrorAction $ErrorAction)) {
        $Message += (New-Error "Connection to registry failed")
    } else {
        $Message += (New-Log "Connection to registry successful")
    }
}

function Verify-DomainDisconnect ($Domain, $Key) {
    if ($Key -eq $Domain) {
        $Message += (New-Error "There are still registry keys pointing to $Domain, if you removed from the domain this will successfully work. Otherwise, please remove this workstation from the domain and try again.")
    } elseif ((!($Key)) -or ($Key -eq "")) {
        $Message += (New-Log "The workstation is not on the specified domain $Domain")
    } else {
        $Message += (New-Error "Something might be weird with the domain")
    }
}



if (Test-Path "$tsenv:deployroot\Tools\Modules\ZTIUtility") {
    Import-Module $tsenv:deployroot\Tools\Modules\ZTIUtility\ZTIUtility.psm1
}

Verify-RegistryConnection 'HKLM:\MNTSOFTWARE\'
Verify-RegistryConnection 'HKLM:\MNTSYSTEM\'
Verify-DomainDisconnect -Domain $Domain -Key $DomainKey

<# Configure 32 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\MNTSOFTWARE\ -ErrorAction SilentlyContinue) {
    $32Node = 'HKLM:\MNTSOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $32Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }

    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\ScriptedDiagnostics' -Name "ExecutionPolicy" -Value "Unrestricted" -Type "String"
    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' -Name "ExecutionPolicy" -Value "Unrestricted" -Type "String"
    Configure-RegistryProperty -Node 'HKLM:\MNTSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name "Run-TaskSequenceWin7" `
        -Value "C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -Command `"`& `'C:\$localDirectory\$copyScript`'`"" -Type "String"
} else { 
    $Message += (New-Error "Dafuq HLKM:\MNTSOFTWARE couldn't be found")
}

<# Configure 64 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\MNTSOFTWARE\Wow6432Node\ -ErrorAction SilentlyContinue) {
    $64Node = 'HKLM:\MNTSOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $64Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} else { 
    $Message += (New-Log "HLKM:\MNTSOFTWARE\Wow6432Node\ couldn't be found, probably a 32 bit machine...")
}

<# Adds a directory to the C drive to store the targetted powershell script found in the scripts directory of the deployment share to run at autologon  #>
if (!(Test-Path "D:\$localDirectory" -ErrorAction SilentlyContinue)) { 
    $Message += (New-Log "C:\$localDirectory was not found, creating it now")
    New-Item -Path D:\ -Name $localDirectory -ItemType Directory
} else { 
    $Message += (New-Log "Found C:\$localDirectory")
}

<# Copies the targetted file "runLiteTouch.ps1" to the directory created on the C drive (or D while in WinPE) #>
if (!(Test-Path "$tsenv:deployroot\Scripts\")) { 
    $Message += (New-Log "Could not connect to the deploy root to copy Run-TaskSequenceWin7.ps1")
} else {
    Copy-Item -Path "$tsenv:deployroot\Scripts\$copyScript" -Destination "D:\$localDirectory" -Force
}

<#
$HTML = $HardwareArray | ConvertTo-Html
$HTML += "<BR>"
$HTML += $ErrorArray #| ConvertTo-Html
$HTML += "<BR>"
$HTML += $LogArray #| ConvertTo-Html
#>

Complete-log -HTML $Message -ErrorCount 0 -smtp "smtpserver" -to "jims email" -from "service account" -subject "weeeeee! (Dat error log doe)"

















#    Set-ItemProperty $32Node -Name AutoAdminLogon -Value "1" -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $32Node -Name ForceAutoLogon -Value "1" -Type String -ErrorAction SilentlyContinue -Force
    #Set admin auto logon credentials
#    Set-ItemProperty $32Node -Name DefaultDomainName -Value $localComputer -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $32Node -Name DefaultUserName -Value "Administrator" -Type String -ErrorAction SilentlyContinue -Force
    #Generate and set admin password
#    New-ItemProperty $32Node -Name DefaultPassword -Value $localadminpass -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $32Node -Name DefaultPassword -Value $localadminpass -Type String -ErrorAction SilentlyContinue -Force
    #Sets count of allowed auto logon times
#    New-ItemProperty $32Node -Name AutoLogonCount -Value 5 -Type DWord -ErrorAction SilentlyContinue -Force


#    Set-ItemProperty $64Node -Name AutoAdminLogon -Value "1" -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $64Node -Name ForceAutoLogon -Value "1" -Type String -ErrorAction SilentlyContinue -Force
    #Set admin auto logon credentials
#    Set-ItemProperty $64Node -Name DefaultDomainName -Value $localComputer -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $64Node -Name DefaultUserName -Value "Administrator" -Type String -ErrorAction SilentlyContinue -Force
    #Generate and set admin password
#    New-ItemProperty $64Node -Name DefaultPassword -Value $localadminpass -Type String -ErrorAction SilentlyContinue -Force
#    Set-ItemProperty $64Node -Name DefaultPassword -Value $localadminpass -Type String -ErrorAction SilentlyContinue -Force
    #Sets count of allowed auto logon times
#    New-ItemProperty $64Node -Name AutoLogonCount -Value 5 -Type DWord -ErrorAction SilentlyContinue -Force