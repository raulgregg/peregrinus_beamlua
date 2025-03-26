
mkdir C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\mods\unpacked


New-Item -Path C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\mods\unpacked\peregrinusDriveCommon -ItemType SymbolicLink -Value D:\Peregrinus\PereHobby\beamng\assets\images\Cars\00_common

New-Item -Path C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\mods\unpacked\peregrinusDriveETKSeries -ItemType SymbolicLink -Value D:\Peregrinus\PereHobby\beamng\assets\images\Cars\01_ETK_Series

New-Item -Path C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\mods\unpacked\peregrinusDriveRallySeries -ItemType SymbolicLink -Value D:\Peregrinus\PereHobby\beamng\assets\images\Cars\02_Rally_Series

New-Item -Path C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\lua -ItemType SymbolicLink -Value D:\Peregrinus\PereHobby\beamng\scripts\lua


# New-Item -Path C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\mods\unpacked\ayotundePamilekunayo -ItemType SymbolicLink -Value D:\Peregrinus\PereHobby\beamng\assets\images\Cars\ayotundePamilekunayo

# New-Item -ItemType SymbolicLink -Path D:\Peregrinus\PereTech\websites\peregrinus\peregrinus\data\beamng_data.xlsx -Target D:\Peregrinus\PereHobby\beamng\beamng_data.xlsx


# Creates a symlink for the file and not for the folder
New-Item -Path "C:\Users\Marekz\AppData\Local\BeamNG.drive\0.34\beamng.db" -ItemType SymbolicLink -Target "D:\Peregrinus\PereHobby\beamng\data\beamng.db"
