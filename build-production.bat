@echo off

set COMMAND=.\build.ps1
set COMMAND=%COMMAND% -Src .\src\main\docs
set COMMAND=%COMMAND% -Dest .\dist
set COMMAND=%COMMAND% -Resources .\src\main\resources
set COMMAND=%COMMAND% -Theme dark
set COMMAND=%COMMAND% -TocLevels 4
set COMMAND=%COMMAND% -Production:$true
set COMMAND=%COMMAND% -Flatten:$true
set COMMAND=%COMMAND% -LogLevel INFO

powershell.exe -ExecutionPolicy Unrestricted -Command %COMMAND%

pause
