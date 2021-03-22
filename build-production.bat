@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -Src .\src\main -Dest .\dist -Production -TocLevels 3"
pause
