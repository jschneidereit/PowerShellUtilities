#=============================================
# Script Name: Run-TaskSequenceWin7.ps1
# Created: May 2014
# Revised:
# Author: Jim Schneidereit
# Company: EisnerAmper LLP
# Email: jim.schneidereit@eisneramper.com
#=============================================
# Purpose: Kick off a task sequence as defined in the variable section and cleanup some settings from the script that created this one
# Intended: As part of CUSTOM TASK SEQUENCE
# Requirements: A functional task sequence
#*=============================================

$wdsServer = ""
$deploymentShare = "Images$"
$tasksequenceID = "CAPTURE"
$localUser = ""
$Domain = ""
$fullUser = "\$localUser"
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
    AutoLogonCount = [pscustomobject]@{ Name = "AutoLogonCount"; Value = 5; Type = "DWord" }
}

$DomainStatus = 0
$NetworkStatus = 0

function Configure-RegistryProperty($Node, $Name, $Value, $Type) { 
    if (!(Get-ItemProperty $Node -Name $Name -ErrorAction $ErrorAction)) {
        Write-Host "$Name registry key does not exist, creating it now"
        New-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
    } else {
        Write-Host "$Name registry key found, setting it's value now"
        Set-ItemProperty $Node -Name $Name -Value $Value -Type $Type -ErrorAction $ErrorAction -Force
    }
}

function Verify-DomainDisconnect ($Domain, $Key) {
    
    if ($Key -eq $Domain) {
        Write-Error "There are still registry keys pointing to $Domain, if you removed from the domain this will successfully work. Otherwise, please remove this workstation from the domain and try again." -Category ResourceExists
        $x = Read-Host "press enter to continue"
    } elseif ((!($Key)) -or ($Key -eq "")) {
        $DomainStatus = 1
        Write-Host "The workstation is not on the specified domain $Domain"
    } else {
        $DomainStatus = 1
        Write-Host "The workstation is not on the specified domain $Domain"
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
        Write-Warning "Connection to server failed"
        Write-Warning "Something is wrong with the network connection"
        Write-Host "You can either fix the issue and start over from the beginning, or fix it and run C:\ITUtilities\Run-TaskSequenceWin7.ps1"
        $x = Read-Host "press enter to continue"
        Exit
    } else {
        $NetworkStatus = 1
        Write-Host "Connection to server successful"

    }
}

Verify-NetworkConnection $wdsServer
Verify-DomainDisconnect -Domain $Domain -Key $DomainKey

if ($PSVersionTable.PSVersion.Major -ge 3) {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare" -Credential $Credentials
} else {
    New-PSDrive -Name S -PSProvider FileSystem -Root "\\$wdsServer\$deploymentShare"
}

if ($NetworkStatus -and $DomainStatus) {
    & S:\scripts\litetouch.vbs "/tasksequenceID:$tasksequenceID" "/skiptasksequence:YES" "/rulesfile:\\$wdsServer\$deploymentShare\Control\CustomSettings.ini"
}

$32Node = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$64Node = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'

<# Configure 32 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\SOFTWARE\ -ErrorAction $ErrorAction) {
    $32Node = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $32Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} else { 
    Write-Warning "Dafuq HLKM:\SOFTWARE couldn't be found"
}

<# Configure 64 bit auto logon settings found in the mounted registry from the offline computer if available  #>
if (Test-Path HKLM:\SOFTWARE\Wow6432Node\ -ErrorAction $ErrorAction) {
    $64Node = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $LogonHash.GetEnumerator() | % { Configure-RegistryProperty -Node $64Node -Name $_.Value.Name -Value $_.Value.Value -Type $_.Value.Type }
} else { 
    Write-Warning "HLKM:\SOFTWARE\Wow6432Node\ couldn't be found, probably a 32 bit machine..."
}

Start-Sleep -Seconds 5

If (Test-Path C:\$FileName -ErrorAction SilentlyContinue) { Remove-Item -Path C:\$FileName -Recurse -Force } else {continue}






<#
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
#>