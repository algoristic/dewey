@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -LogLevel DEBUG -TocLevels 4 -Flatten:$false"
pause
