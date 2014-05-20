#
#=============================================
# Script Name: Import-ScheduledTasks.ps1
# Created: May, 20 2014
# Revised:
# Author: Jim Schneidereit
# Company: redacted
# Email: redacted
#=============================================
# Purpose: Determines error and warning count and sets task sequence variable accordingly
# Intendend: As task sequence script to disable unnecessary final summary
# Requirements: PowerShell, MDT and associated software
# Usage: Place in task sequence at custom settings and options
# Credits: Modified from here to work with MDT -> http://jon.netdork.net/2011/03/10/powershell-and-importing-xml-scheduled-tasks/
#*=============================================

#place xml files in the script root, in subfolder named "Tasks"
$tasks = "$tsenv:deployroot\Scripts\Tasks\*.xml" #"$PSScriptRoot\*.xml"
$User = "user"
$Pass = "pass"


$ScheduleService = New-Object -ComObject("Schedule.Service")
$ScheduleService.Connect("LocalHost")
$TasksFolder = $ScheduleService.GetFolder("\")

Get-Item $tasks | % {
    $Name = $_.Name.Replace('.xml', '')
    $XML = Get-Content $_.FullName

    $Task = $ScheduleService.NewTask($null)
    $Task.XmlText = $XML

    $TasksFolder.RegisterTaskDefinition($Name, $Task, 6, $User, $Pass, 1, $null)
}