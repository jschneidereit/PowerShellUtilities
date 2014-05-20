#
#=============================================
# Script Name: Find-FinalErrorCount.ps1
# Created: May, 20 2014
# Revised:
# Author: Jim Schneidereit
# Company: redacted
# Email: redacted
#=============================================
# Purpose: Determines error and warning count and sets task sequence variable accordingly
# Intendend: As task sequence script to disable unnecessary final summary
# Requirements: PowerShell, MDT and associated softwares
# Usage: Place in task sequence before final summary is displayed
#*=============================================

$results = "C:\Users\Administrator\AppData\Local\Temp\Results.xml"
if (Test-Path $results -ErrorAction SilentlyContinue) {
    $xml = [xml](Get-Content $results -ErrorAction Stop)
    $errorCount = [int]($xml.Results.Errors)
    $warningCount = [int]($xml.Results.Warnings)
    if ($errorCount -gt 0 -or $warningCount -gt 0) { $TSEnv:SkipFinalSummary="NO" } else { $TSEnv:SkipFinalSummary="YES" }
}
