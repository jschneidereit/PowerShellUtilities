$TargetDirectory = "D:\blah\blah\*"
$TargetExtension = "*.wim"
$TargetAge = "90"

$Comparison = (Get-Date).AddDays(-$TargetAge)

Get-ChildItem -Path $TargetDirectory -Include $TargetExtension | ? { $_.LastWriteTime -le $Comparison } | Remove-Item -Force