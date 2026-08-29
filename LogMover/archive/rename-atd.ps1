Write-Host "Autocollection is running...Press CTRL+C to stop."
while ($true) {
    # Write-Host "Running. Press CTRL+C to stop."
    Start-Sleep -Seconds 5

# Specify the directory
#$sourceFilePath = "C:\" 

# Specify the cut off date                                                                                      
$daysOld = 1
                                                                                                  
$cutoffDate = (Get-Date).AddDays(-$daysOld)


#$NewFiles = Get-ChildItem -Path "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe\*pass.atd" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}
$NewFiles = Get-ChildItem  -Path  "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\*pass.atd" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}

}