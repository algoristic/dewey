@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -Production -TocLevels 3"
pause
