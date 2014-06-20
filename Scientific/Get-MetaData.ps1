<#
.SYNOPSIS
This script was created for Nick Ellis to pull useful metadata out of xml files saved by imaging software on a microscope.
...for scciiiieeeeeeence!


.DESCRIPTION
Placed in the directory and run will cause the script to get all data from any 
file beneath it's current location and output the data to a .csv file in the same 
directory as the script or in the user defined path

.PARAMETER TargetDirectory
optional paramter that overrides the current directory

.EXAMPLE
Place in directory of interest
.\Get-MetaData.ps1

or

.\Get-MetaData.ps1 "C:\Somedir"
***NOTE: no tailing \ sign on user defined directory***

.NOTES
This script does not handle cases where the data is not present
like when the camera is set to automatic, it will show up as 
an empty line with the file name only
#>


param ([string] $TargetDirectory = (Split-Path $MyInvocation.MyCommand.Path))


$TargetDirectory

$ResultsArray = @()

Write-Host "Beginning awesomeness!...`n"

$TargetDirectory | Get-ChildItem -Include "*.xml" -Recurse | % {
    Write-Host "Processing file - $($_.name)..."  
    $CurrentXml = New-Object -TypeName XML
    $CurrentXml.Load($_.FullName)
        
    $CameraNode = $CurrentXml.GetElementsByTagName("Camera")
    $ImageNodes = $CurrentXml.GetElementsByTagName("ImageValue")
    $MicroScopeZoomMag = $ImageNodes | ? { $_.Name -eq "Microscope_Zoom_Magnification" } | Select-Object -ExpandProperty "Value"

    $ImageObject = New-Object PSObject
    $ImageObject | Add-Member -MemberType NoteProperty -Name "File Name" -Value $_.name
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Magnification" -Value ($MicroScopeZoomMag.InnerText)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Camera Name" -Value ($CameraNode.Name)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Exposure" -Value ($CameraNode.Exposure)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Gamma" -Value ($CameraNode.Gamma)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Gain" -Value ($CameraNode.Gain)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Image Type" -Value ($CameraNode.Image_Type)
    $ImageObject | Add-Member -MemberType NoteProperty -Name "Capture Format" -Value ($CameraNode.Capture_Format)

    $ResultsArray += $ImageObject
}

$OutFile = ($TargetDirectory + "\" + (Get-Date -Format s).Replace(":", ".") + ".csv")

$ResultsArray | Export-Csv -Path $OutFile -NoTypeInformation -Force

#need to implement error handling later, rushed job :)
if ($?) { Write-Host "`nYou can find your file here: $OutFile" } else { Write-Host "`nSomething horrible happened!" }

Write-Host "`nPress enter to continue..."

$x = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
