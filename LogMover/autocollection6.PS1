Write-Host "Autocollection is running...Press CTRL+C to stop."
while ($true) {
    # Write-Host "Running. Press CTRL+C to stop."
    Start-Sleep -Seconds 5

# Specify the directory
#$sourceFilePath = "C:\" 

# Specify the cut off date                                                                                      
$daysOld = 1
                                                                                                  
$cutoffDate = (Get-Date).AddDays(-$daysOld)

#change .atd to .atdx
 #Get-ChildItem -Path  "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\*.ATD" -File | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}
#Get-ChildItem -Path  "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\HELION ENERGY\TEST\*.ATD" -File | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}


#$NewFiles = Get-ChildItem -Path "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\*pass.atd" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}

#$NewFiles = Get-ChildItem -Path "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\DZSI\Saber\*pass.atd*" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | Copy-Item -Destination "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" -Force
#$NewFiles = Get-ChildItem -Path \\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\ISI\*pass.atd* -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | Copy-Item -Destination "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" -Force
#$NewFiles = Get-ChildItem -Path "\\10.100.31.50\FLYINGPROBE-IBONGMB\TAKAYA-APT1400F\TEST-LOGS\CUSTOMERS\TESLA\*pass.atd*" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | Copy-Item -Destination "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" -Force

#$NewFiles = Get-ChildItem -Path "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe\*pass.atd" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | ForEach {Rename-Item $_.FullName -NewName ($_.name).Replace(".ATD",".atdx")}

$NewFiles = Get-ChildItem -Path "\\10.100.1.21\data\PUBLIC\auto collection test\test\*pass.atdx" -Recurse | Where-Object {$_.LastWriteTime -gt $cutoffDate} | Move-Item -Destination "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" -Force

#robocopy "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" "\\10.100.1.21\data\PUBLIC\Auto Collection\3315 Flying Probe"  /mon:1 /mov /z /m
#robocopy "\\10.100.1.21\data\PUBLIC\auto collection test\3315 Flying Probe" "\\10.100.1.21\data\PUBLIC\auto collection test\test"  /mon:1 /move /m

}
