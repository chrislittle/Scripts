#Remove CrowdStrick Files
$volumes = get-volume

foreach ($volume in $Volumes) {
    $driveletter = $volume.DriveLetter
    $path = $driveletter + ":\windows\System32\drivers\CrowdStrike\"
    $testpath = Test-Path -Path $path
    if ($testpath -eq $true) {
    $removeitems = $path + "C-00000291*.sys"
    Remove-Item -Path $removeitems -Force
    }
}