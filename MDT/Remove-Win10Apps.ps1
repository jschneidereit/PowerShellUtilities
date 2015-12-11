$targets = @("3dbuilder", "windowsalarms", "windowscalculator",
             "windowscommunicationsapps", "windowscamera", "officehub",
             "skypeapp", "getstarted", "zunemusic", "windowsmaps",
             "solitairecollection", "bingfinance", "zunevideo",
             "bingnews", "onenote", "people", "windowsphone", "photos",
             "windowsstore", "bingsports", "soundrecorder", "bingweather",
             "xboxapp")

ForEach ($target in $targets) {
    $app = "*$target*"
    Get-AppxPackage $app | Remove-AppxPackage -ErrorAction SilentlyContinue
}