@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -LogLevel DEBUG -Flatten:$false"
pause
