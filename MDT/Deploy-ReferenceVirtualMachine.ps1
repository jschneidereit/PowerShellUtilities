#requires -version 3.0
#=============================================
# Script Name: Deploy-ReferenceVirtualMachine.ps1
# Created: May, 16 2014
# Revised:
# Author: Jim Schneidereit
# Company: redacted
# Email: redacted
#=============================================
# Purpose: Automates reference (generic) image creation
# Intendend: As scheduled event on WDS/MDT server - monthly to take advantage of WSUS updates
# Requirements: PowerShell V3.0 or higher, MDT and associated softwares
# Note: Does not "import" the wim, and as such might not work well with task sequence, true importing is trivial but does not allow for zero human interface
#*=============================================

<#   Will restart script as "run as administrator" - DO NOT MODIFY   #>
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
   Break
}

#region Configurable Variables

$DeploymentShareDirectory = "C:\DeploymentShares"
$VirtualMachineDirectory = "C:\Virtual Machines"

<#   Reference Depoyment Share   #>
$RDS = @{
    Path = "$DeploymentShareDirectory\Reference"
    Name = "Reference"
}

<#   Target Deployment Share   #>
$TDS = @{
    Path = "$DeploymentShareDirectory\Target"
    Name = "Target"
    OSFileName = "GENERIC"
}

<#   Virtual Machine Settings   #>
$VM = @{
    Path = "$VirtualMachineDirectory"
    Name = "GENERIC"
    RAM = 2048MB
    VHDSize = 128GB
    <#   This switch will be created if it doesn't exist   #>
    Switch = "Virtual Switch"
    <#   This is the iso that the RDS generates when you "update deployment share"   #>
    ISO = "$($RDS.Path)\Boot\LiteTouchPE_x64.iso"
}

#implement later
<#   MDT Administrators - for emailing reports   #>
$MDTAdministrators = @{
    "server" = "user.name@domain.com"
    "server2" = "user.name@domain.com"
}

#endregion

$ScriptVersion = "1"
$VHDPath = "$($VM.Path)\$($VM.Name).vhdx"
$LogPath = "$DeploymentShareDirectory\Logs\"


<#   Use this to cleanup mess from other functions   #>
Function Clean-SpecifiedLocation {
    Param ( $SpecifiedLocation )
    
    if (Get-ChildItem -Path $SpecifiedLocation) {
        Write-Log "Cleaning up the specified location: $SpecifiedLocation"
        Get-ChildItem -Path $SpecifiedLocation | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "You tried to cleanup the specified location: $SpecifiedLocation, but nothing was there"
    }
}

<#   Creates a virtual switch for the VM to use to connect   #>
Function New-VirtualSwitch {
    If (!(Get-NetAdapter | ? {($_.Name -like "vEthernet ($($VM.Switch))")})) {
        $Adapters = Get-NetAdapter -Physical | ? {($_.Status -eq 'Up')}
        if ($Adapters.count) {
            $AvailableAdapters = $Adapters.GetEnumerator() | % { $_.name }
            $Adapter = $AvailableAdapters[0] 
        } else {
            $Adapter = $Adapters[0].Name
        }
    }
    try {
        New-VMSwitch -Name $VM.Switch -NetAdapterName $Adapter -AllowManagementOS $true -ErrorAction Stop -ErrorVariable $temperror
        Write-Log "A new virtual switch $($VM.Switch) has been generated"
    } catch [Microsoft.HyperV.PowerShell.VirtualizationOperationFailedException] {  
        if (Get-NetAdapter | % {$_.Name -match $VM.Switch}) { 
            Write-Log "A virtual switch with the name $($VM.Switch) had already been generated, continuing on"
        } else {
           Write-Log "Something horrible happened - Couldn't add the virtual switch, the rest of this script will not complete successfully and will exit"
        }
    } catch {
        Write-Log "Something horrible happened - Couldn't add the virtual switch, the rest of this script will not complete successfully and will exit"
    }
}

<#   Removes the virtual switch created for the VM   #>
Function Remove-VirtualSwitch {
    If ( Get-NetAdapter | ? {($_.Name -like "vEthernet ($($VM.Switch))")} ) {
        Write-Log "Removing the switch: $($VM.Switch)"
        Remove-VMSwitch -Name $VM.Switch -Force
    } else {
        Write-Log "There wasn't a switch by the name $($VM.Switch)"
    }
}

    


<#   Creates a new virtual machine to run the task sequence, defined in $VM hastable   #>
Function New-VirtualMachine {
    
    If (!(Get-VM | % {$_.Name -match $VM.Name} )) {
        Write-Log "Creating the new Virtual Machine named $($VM.Name) on $env:ComputerName"
        New-VM -Name $VM.Name -BootDevice CD -MemoryStartupBytes $VM.RAM -SwitchName $VM.Switch -Path $VM.Path -NoVHD -Verbose
    } else {
        Write-Log "A Virtual Machine name $($VM.Name) already exists on $env:ComputerName"
    }

    If (!(Get-VHD -Path $VHDPath -ErrorAction SilentlyContinue)) {
        Write-Log "Creating a new VHD at $VHDPath"
        New-VHD -Path $VHDPath -SizeBytes $VM.VHDSize -Verbose
    } else {
        Write-Log "A VHD already exists at $VHDPath removing and then rebuilding"
        Remove-Item $VHDPath -Force
        Write-Log "Creating a new VHD at $VHDPath"
        New-VHD -Path $VHDPath -SizeBytes $VM.VHDSize -Verbose
    }

    Add-VMHardDiskDrive -VMName $VM.Name -Path $VHDPath -Verbose
    Set-VMDvdDrive -VMName $VM.Name -Path $VM.ISO -Verbose
    Start-VM -VMName $VM.Name
}


<#   Waits for the virtual machine defined in the $VM hashtable   #>
Function Wait-VirtualMachine {
    Write-Log "The virtual machine is running, waiting for it to complete"
    $VirtualMachine = Get-VM -Name $VM.Name
    
    While ($VirtualMachine.State -ne "off") {
        Sleep -Seconds 120
    }

    Write-Log "The virtual machine went offline, the wait is over"
}

<#   Removes the virtual machine defined in the $VM hashtable   #>
Function Remove-VirtualMachine {
    Write-Log "Removing the virtual machine $($VM.Name)"
    Remove-VM -Name $VM.Name -Force
    Remove-Item -Path "$($VM.Path)\$($VM.Name)" -Recurse -Force
    Remove-Item -Path "$($VM.Path)\$($VM.Name).vhdx" -Recurse -Force 
    #Remove-VirtualSwitch
}

<#   Copies the captured image from the VM task sequence to the Target Deployment Share   #>
Function Copy-CapturedImage {
    Write-Host "Beginning the copy of captured image"
    Write-Host "This will clobber whatever image was already there..."
    
    $Capture = (Get-ChildItem ($RDS.Path + "\Captures")).FullName
    $Destination =  ($TDS.Path + "\Operating Systems\" + $TDS.OSFileName + "\" + $TDS.OSFileName)

    If (Test-Path -Path ($Destination  + ".WIM")) {
        If (Test-Path -Path ($Destination + ".old")) {Remove-Item ($Destination + ".old") -Verbose}
        Rename-Item ($Destination + ".WIM") ($TDS.OSFileName + ".old") -Force -Verbose 
    }

    If (Test-Path -Path $Capture) {
        Copy-Item -Path $Capture -Destination ($TDS.Path + "\Operating Systems\" + $TDS.OSFileName) -Force -Verbose
        If ($?) { 
            Write-Log "Copy successful!"
            Remove-Item $Capture 
        } Else { 
            Write-Log "The copy of the image from the RDS to the TDS was not successful"
        }
    } Else {
        Write-Log "The captured image was not where it should have been"
    }
}

<#   Builds log file if necessary   #>
Function Build-Log {
    $LogFile = ($LogPath + "VMLog_" + (Get-Date -Format s).Replace(":","") + ".txt")
    if (!(Test-Path -Path $LogFile)) { New-Item -Path $LogFile -ItemType File -Force} else { continue }
    Return $LogFile
}

<#   Initializes the log file   #>
Function Initialize-Log {
     "`nStarted processing at [$(Get-Date)]. Running script version [$ScriptVersion]." | Out-File -FilePath $LogFile -Append -Force
}

<#   Writes the message with a time stamp to the log file   #>
Function Write-Log {
    Param ( $Message )

    $FormatedMessage = "`n$(Get-Date -Format t)  -  $Message"
    Write-Verbose $FormatedMessage
    #$FormatedMessage | Out-File -FilePath $LogFile -Append -Force
}

<#   Ends the log   #>
Function Complete-Log {
    "`nCompleted processing at [$(Get-Date)]." | Out-File -FilePath $LogFile -Append -Force
}

#$LogFile = Build-Log
#Initialize-Log
if (!(Get-Module -Name Hyper-V)) {Import-Module -Name Hyper-V}
Write-Host "hello good sir"
Clean-SpecifiedLocation ($RDS.Path + "\Captures")
Write-Host "gonna do virtual switch"
New-VirtualSwitch
Write-Host "gonna do virtual machine"
New-VirtualMachine
Write-Host "gonna wait..."
Wait-VirtualMachine
Write-Host "gonna copy captured image"
Copy-CapturedImage
Remove-VirtualMachine
#Complete-Log 
