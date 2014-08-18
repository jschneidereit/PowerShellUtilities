##Script to Delete .WIM Files older than 90 Days##

# Set Folder Path
$TargetDirectory = "c:\blah blah\*"

# Set File Extension
$TargetExtension = "*.ext"

# Set Minimum Age of Files
$Max_Age = "-90"

# Get the Current Date
$CurrentDate = Get-Date

# Determine How Far Back From Current Date to Delete
$DateToDelete = $CurrentDate.AddDays($Max_Age)

# Deletes Files Older than Days Specified Above
Get-ChildItem -include $TargetExtension $TargetDirectory | Where-Object { $_.LastWriteTime -lt $DateToDelete } |Where-Object { -not ($_.psiscontainer) } | Foreach-Object {Remove-Item $_.FullName}
