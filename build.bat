@echo off
powershell.exe -ExecutionPolicy Unrestricted -Command ".\build.ps1 -Src .\src\test\buildscript -Dest .\build"
pause
