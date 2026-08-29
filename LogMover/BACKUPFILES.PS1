#robocopy "\\APT2600\TAKAYA\APT-1400\CUSTOMERS\" "\\10.100.31.80\TAKAYA\TestPrograms\"  *.* /mon:1 /z /MAXAGE:10 /s /m
#robocopy "\\APT2600\TAKAYA\APT-1400\CUSTOMERS\" "\\10.100.31.80\TAKAYA\TestPrograms\APT-1400\"  *.* /mon:1 /z /s /m
robocopy "\\APT2600\TAKAYA\APT-1600\CUSTOMERS\" "\\10.100.31.80\TAKAYA\TestPrograms\APT-1600\"  *.* /mon:1 /z /s /m
#robocopy "\\APT2600\TAKAYA\APT-2600\CUSTOMERS\" "\\10.100.31.80\TAKAYA\TestPrograms\APT-2600\"  *.* /mon:1 /z /s /m

