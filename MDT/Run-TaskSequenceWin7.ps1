#=============================================
# Script Name: Run-TaskSequenceWin7.ps1
# Created: May 2014
# Revised: July 25, 2014
# Author: Jim Schneidereit
# URL: https://github.com/jschneidereit/PowerShellUtilities/tree/master/MDT
#=============================================
# Purpose: Kick off a task sequence as defined in the variable section and cleanup some settings from the script that created this one
# Intended: As part of CUSTOM TASK SEQUENCE
# Requirements: A functional task sequence
#*=============================================

$wdsServer = ""
$deploymentShare = "Images$"
$tasksequenceID = "CAPTURE"
$localUser = "" #service account with proper priveleges to add/remove domain and local admin on wds server
$Domain = ""
$fullUser = "$domain\$localUser"
$localPass = '' | ConvertTo-SecureString -AsPlainText -Force
$Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $fullUser, $localPass
$FileName = "ITUtilities"
$DomainKey = ((Get-ItemProperty HKLM:\SYSTEM\ControlSet001\Services\Tcpip\Parameters -Name Domain).Domain).ToUpper()

$LogonHash = @{ 
    AutoAdminLogon = [pscustomobject]@{ Name = "AutoAdminLogon"; Value = "0"; Type = "String" }
    ForceAutoLogon = [pscustomobject]@{ Name = "ForceAutoLogon"; Value = "0"; Type = "String" }
    DefaultDomainName = [pscustomobject]@{ Name = "DefaultDomainName"; Value = ""; Type = "String" }
    DefaultUserName = [pscustomobject]@{ Name = "DefaultUserName"; Value = ""; Type = "String" }
    DefaultPassword = [pscustomobject]@{ Name = "DefaultPassword"; Value = ""; Type = "String" }
    AutoLogonCount = [pscustomobject]@{ Name = "AutoLogonCount"; Value = 10; Type = "DWord" }
}

$Global:DomainStatus = 0
$Global:NetworkStatus = 0

$32Node = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$64Node = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'

#region Logging
#use a comma separated string for multiple emails: "email1@domain.com, email2@domain.com"
$AdminEmails = ""
$AdminOutEmail = ""
$SMTPServer = ""

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

$Global:LogMessage += (New-Log "Office server - $wdsServer")

#endregion

function Configure-RegistryProperty($Node, $Name, $Value, $Type) { 
    if (!(Get-ItemProperty $Node -Name $Name -ErrorAction SilentlyContinue)) {
        New-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    } else {
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue -Force
    }
}
    
function Verify-DomainDisconnect ($Domain, $Key) {
    if ($Key -eq $Domain) {
        $Global:LogMessage += (New-Error "There are still registry keys pointing to $Domain, please remove this workstation from the domain and try again.")
        #$x = Read-Host "press enter to continue"
    } elseif ((!($Key)) -or ($Key -eq "")) {
        $Global:LogMessage += (New-Log "The workstation is not on the specified domain $Domain")
        $Global:DomainStatus = 1
    } else {
        $Global:LogMessage += (New-Error "Something might be weird with the domain registry settings on this machine, please contact the Administrator")
        Write-Warning "Going to try running the task sequence any way in case the registry isn't up to date"
        $Global:DomainStatus = 1
    }
}

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
        $Global:LogMessage += (New-Error  "Connection to server failed")
        Write-Warning "Something is wrong with the network connection"
        Write-Host "You can either fix the issue and start over from the beginning, or fix it and run C:\ITUtilities\Run-TaskSequenceWin7.ps1"
        $x = Read-Host "press enter to continue"
        Exit
    } else {
        $Global:NetworkStatus = 1
        $Global:LogMessage += (New-Log  "Connection to server successful")
    }
}

Verify-NetworkConnection $wdsServer
Verify-DomainDisconnect -Domain $Domain -Key $DomainKey

if ($PSVersionTable.PSVersion.Major -ge 3) {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare" -Credential $Credentials
} else {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare"
}

if ($Global:NetworkStatus -and $Global:DomainStatus) {
    & S:\scripts\litetouch.vbs "/tasksequenceID:$tasksequenceID" "/skiptasksequence:YES" "/rulesfile:\\$wdsServer\$deploymentShare\Control\CustomSettings.ini"
    if ($?) { 
        $Global:LogMessage += (New-Log "Task Sequence started successfully") 
        If (Test-Path C:\$FileName -ErrorAction SilentlyContinue) { Remove-Item -Path C:\$FileName -Recurse -Force } else {continue}
        Remove-ItemProperty -Path 'HKLM:\MNTSOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name "Run-TaskSequenceWin7"
    } else { $Global:LogMessage += (New-Error "Task Sequence did not start successfully") }

    

        <# Configure 32 bit auto logon settings found in the mounted registry from the offline computer if available  #>
    if (Test-Path HKLM:\SOFTWARE\ -ErrorAction SilentlyContinue) {
        $32Node = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $32Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
    } else { 
        $Global:LogMessage += (New-Error "HLKM:\SOFTWARE couldn't be found, something is very wrong")
    }

    <# Configure 64 bit auto logon settings found in the mounted registry from the offline computer if available  #>
    if (Test-Path HKLM:\SOFTWARE\Wow6432Node\ -ErrorAction SilentlyContinue) {
        $64Node = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'
        $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $64Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
    } elseif (!(Test-Path HKLM:\SOFTWARE)) { 
        $Global:LogMessage += (New-Error "HLKM:\SOFTWARE couldn't be found, something is very wrong")
    } else {
        $Global:LogMessage += (New-Log "HLKM:\SOFTWARE\Wow6432Node\ couldn't be found, probably a 32 bit machine...")
    }

} else {
    $Global:LogMessage += (New-Error "This computer was either on the domain or does not have a connection to the server`n Capture Failed")
    $x = Read-Host "press enter to continue"
}



Complete-log -Content $Global:LogMessage -Errors $Global:ErrorCount -smtp $SMTPServer -to $AdminEmails -from $AdminOutEmail -subject "Win7 Task Sequence Capture Log - $((gwmi win32_bios).SerialNumber)"



#uncomment to have a pause
#$x = Read-Host "press enter to continue"