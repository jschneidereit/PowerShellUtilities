#runs several applications that require elevated permissions on a standard account so I dont have to enter password all the time

$PasswordFile= 'C:\Scripts\pw.txt'
$AdminAccount= 'Administrator'

if (! (Test-Path -Path $PasswordFile -ErrorAction SilentlyContinue) ) {
    Write-Host "Enter password for $AdminAccount"
    read-host -AsSecureString | ConvertFrom-SecureString | Out-File $PasswordFile
}

$Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$Env:ComputerName\$AdminAccount", (Get-Content $PasswordFile | ConvertTo-SecureString)

if ($?) {
    Write-Host 'Loaded admin password!'
    $opt = Read-Host 'Enter a number to choose application, 1: Steam, 2: FRAPS, 3: Minecraft'
} else {
    Write-Host 'Failed to load admin password'
    Read-Host 'Press Enter to continue'
    Exit
}

switch ($opt) {
    1 { Start-Process 'C:\Program Files (x86)\Steam\Steam.exe' -Credential $Credentials }
    2 { Start-Process "$PSHOME\PowerShell.exe" -Credential $Credentials -ArgumentList "-command 'Start-Process 'C:\Program Files (x86)\fraps\fraps.exe -Verb runas''" }
    3 { Start-Process 'C:\Program Files (x86)\Minecraft\MinecraftLauncher.exe' -Credential $Credentials }
}


