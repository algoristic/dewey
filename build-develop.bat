@echo off

set COMMAND=.\build.ps1
set COMMAND=%COMMAND% -Src .\src\main\docs
set COMMAND=%COMMAND% -Dest .\dist
set COMMAND=%COMMAND% -Resources .\src\main\resources
set COMMAND=%COMMAND% -Theme dark
set COMMAND=%COMMAND% -TocLevels 4
set COMMAND=%COMMAND% -Production:$false
set COMMAND=%COMMAND% -Flatten:$false
set COMMAND=%COMMAND% -LogLevel DEBUG

powershell.exe -ExecutionPolicy Unrestricted -Command %COMMAND%

pause
