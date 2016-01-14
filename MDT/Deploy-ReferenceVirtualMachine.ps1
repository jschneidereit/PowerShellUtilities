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
# Note: Does not "import" the wim, and as such might not work well with task sequence, true importing is trivial but does not allow for any human interface
#*=============================================

<#   Will restart script as "run as administrator" - DO NOT MODIFY   #>

Function Assert-AdminInstance {
    If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
        $arguments = "& '" + $myinvocation.mycommand.definition + "'"
        Start-Process powershell -Verb runAs -ArgumentList $arguments
       Break
    }
}


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
Function New-VirtualSwitch($vmswitchname) {
    If (!(Get-NetAdapter | ? {($_.Name -like "vEthernet ($vmswitchname)")})) {
        $Adapters = Get-NetAdapter -Physical | ? {($_.Status -eq 'Up')}
        if ($Adapters.count) {
            $AvailableAdapters = $Adapters.GetEnumerator() | % { $_.name }
            $Adapter = $AvailableAdapters[0] 
        } else {
            $Adapter = $Adapters[0].Name
        }
    }
    try {
        New-VMSwitch -Name $vmswitchname -NetAdapterName $Adapter -AllowManagementOS $true -ErrorAction Stop -ErrorVariable $temperror
        Write-Log "A new virtual switch $vmswitchname has been generated"
    } catch [Microsoft.HyperV.PowerShell.VirtualizationOperationFailedException] {  
        if (Get-NetAdapter | % {$_.Name -match $vmswitchname}) { 
            Write-Log "A virtual switch with the name $vmswitchname had already been generated, continuing on"
        } else {
           Write-Log "Something horrible happened - Couldn't add the virtual switch, the rest of this script will not complete successfully and will exit"
        }
    } catch {
        Write-Log "Something horrible happened - Couldn't add the virtual switch, the rest of this script will not complete successfully and will exit"
    }
}

<#   Removes the virtual switch created for the VM   #>
Function Remove-VirtualSwitch($vmswitchname) {
    If ( Get-NetAdapter | ? {($_.Name -like "vEthernet ($vmswitchname)")} ) {
        Write-Log "Removing the switch: $vmswitchname"
        Remove-VMSwitch -Name $vmswitchname -Force
    } else {
        Write-Log "There wasn't a switch by the name $vmswitchname"
    }
}

<#   Creates a new virtual machine to run the task sequence, defined in $VM hastable   #>
Function New-VirtualMachine($vmname, $vmram, $vmswitch, $vmpath, $vhdpath, $vhdsize, $vmiso) {
   
    New-VirtualSwitch -vmswitchname $vmswitch

    If (!(Get-VM | % {$_.Name -match $vmname} )) {
        Write-Log "Creating the new Virtual Machine named $vmname on $env:ComputerName"
        New-VM -Name $VM.Name -BootDevice CD -MemoryStartupBytes $vmram -SwitchName $vmswitch -Path $vmpath -NoVHD -Verbose
    } else {
        Write-Log "A Virtual Machine name $vmname already exists on $env:ComputerName"
    }

    If (!(Get-VHD -Path $vhdpath -ErrorAction SilentlyContinue)) {
        Write-Log "Creating a new VHD at $vhdpath"
        New-VHD -Path $vhdpath -SizeBytes $vhdsize -Verbose
    } else {
        Write-Log "A VHD already exists at $vhdpath removing and then rebuilding"
        Remove-Item $vhdpath -Force
        Write-Log "Creating a new VHD at $vhdpath"
        New-VHD -Path $vhdpath -SizeBytes $vhdsize -Verbose
    }

    Add-VMHardDiskDrive -VMName $vmname -Path $VHDPath -Verbose
    Set-VMDvdDrive -VMName $vmname -Path $vmiso -Verbose
    Start-VM -VMName $vmname
}

<#   Waits for the virtual machine defined in the $VM hashtable   #>
Function Wait-VirtualMachine($vmname) {
    Write-Log "The virtual machine is running, waiting for it to complete"
    $VirtualMachine = Get-VM -Name $vmname
    
    While ($VirtualMachine.State -ne "off") {
        Sleep -Seconds 120
    }

    Write-Log "The virtual machine went offline, the wait is over"
}

<#   Removes the virtual machine defined in the $VM hashtable   #>
Function Remove-VirtualMachine($vmname, $vmpath) {
    Write-Log "Removing the virtual machine $($vmname)"
    Remove-VM -Name $vmname -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$vmpath\$vmname" -Recurse -Force  -ErrorAction SilentlyContinue
    Remove-Item -Path "$vmpath\$vmname.vhdx" -Recurse -Force  -ErrorAction SilentlyContinue
}

<#   Copies the captured image from the VM task sequence to the Target Deployment Share   #>
Function Copy-CapturedImage($ReferencePath, $TargetPath, $TargetOSFileName) {
    Write-Host "Beginning the copy of captured image"
    Write-Host "This will clobber whatever image was already there..."
    
    $Capture = (Get-ChildItem ($ReferencePath + "\Captures")).FullName
    $Destination =  ($TargetPath + "\Operating Systems\" + $TargetOSFileName + "\" + $TargetOSFileName)

    If (Test-Path -Path ($Destination  + ".WIM")) {
        If (Test-Path -Path ($Destination + ".old")) {Remove-Item ($Destination + ".old") -Verbose}
        Rename-Item ($Destination + ".WIM") ($TDS.OSFileName + ".old") -Force -Verbose 
    }

    If (Test-Path -Path $Capture) {
        Copy-Item -Path $Capture -Destination ($TargetPath + "\Operating Systems\" + $TargetOSFileName) -Force -Verbose
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
Function Build-Log($LogPath) {
    $LogFile = ($LogPath + "VMLog_" + (Get-Date -Format s).Replace(":","") + ".txt")
    if (!(Test-Path -Path $LogFile)) { New-Item -Path $LogFile -ItemType File -Force} else { continue }
    Return $LogFile
}

<#   Initializes the log file   #>
Function Initialize-Log($LogFile, $ScriptVersion) {
     "`nStarted processing at [$(Get-Date)]. Running script version [$ScriptVersion]." | Out-File -FilePath $LogFile -Append -Force
}

<#   Writes the message with a time stamp to the log file   #>
Function Write-Log($Message) {
    $FormatedMessage = "`n$(Get-Date -Format t)  -  $Message"
    Write-Verbose $FormatedMessage
    #$FormatedMessage | Out-File -FilePath $LogFile -Append -Force
}

<#   Ends the log   #>
Function Complete-Log($LogFile) {
    "`nCompleted processing at [$(Get-Date)]." | Out-File -FilePath $LogFile -Append -Force
}


#region Configurable Variables




#endregion

Function New-DeploymentShare($Path, $Name, $OSFileName)
{
    $DS = New-Object PSObject
    $DS | Add-Member -NotePropertyName Path -NotePropertyValue $Path
    $DS | Add-Member -NotePropertyName Name -NotePropertyValue $Name
    $DS | Add-Member -NotePropertyName OSFileName -NotePropertyValue $OSFileName

    return $DS
}


Function New-VMObject($Path, $Name, $RAM, $VHDSize, $Switch, $DeploymentShare)
{
    $VM = New-Object PSObject
    $VM | Add-Member -NotePropertyName Path -NotePropertyValue $Path
    $VM | Add-Member -NotePropertyName Name -NotePropertyValue $Name
    $VM | Add-Member -NotePropertyName RAM -NotePropertyValue $RAM
    $VM | Add-Member -NotePropertyName VHDSize -NotePropertyValue $VHDSize
    $VM | Add-Member -NotePropertyName VHDPath -NotePropertyValue "$($Path)\$($Name).vhdx"
    $VM | Add-Member -NotePropertyName Switch -NotePropertyValue $Switch
    <#   This is the iso that MDT generates when you "update deployment share"   #>
    $VM | Add-Member -NotePropertyName ISO -NotePropertyValue "$($DeploymentShare.Path)\Boot\LiteTouchPE_x64.iso"

    return $VM
}

Function MDT-TestBuild($VM)
{
    if (!(Get-Module -Name Hyper-V)) {Import-Module -Name Hyper-V}
    New-VirtualMachine -vmname $vmname -vmram $vmram -vmswitch $VM.Switch -vmpath $VM.Path -vhdpath $VHDPath -vhdsize $VM.VHDSize -vmiso $VM.ISO
}

Function MDT-TestCleanup($VM)
{
    Remove-VirtualMachine -vmname $vmname -vmpath $VM.Path
}

Function Execute-VMBuild($VM)
{
    Assert-AdminInstance
    if (!(Get-Module -Name Hyper-V)) {Import-Module -Name Hyper-V}

    Clean-SpecifiedLocation($RDS.Path + "\Captures")

    New-VirtualMachine -vmname $VM.Name -vmram $VM.RAM -vmswitch $VM.Switch -vmpath $VM.Path -vhdpath $VM.VHDPath -vhdsize $VM.VHDSize -vmiso $VM.ISO
    Remove-VirtualMachine -vmname $VM.Name -vmpath $VM.Path
}


$ScriptVersion = "1"
$LogPath = "$DeploymentShareDirectory\Logs\"
$DeploymentShareDirectory = "C:\DeploymentShares"
$VirtualMachineDirectory = "C:\Virtual Machines"

$RDS = New-DeploymentShare -Name "Reference" -Path "$DeploymentShareDirectory\Reference" -OSFileName "GENERIC"
$RVM = New-VMObject -Path $VirtualMachineDirectory -Name "GENERIC" -RAM 2048MB -VHDSize 64GB -Switch "Virtual Switch" -DeploymentShare $RDS