@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -Src .\src\main -Dest .\dist -Production"
pause
