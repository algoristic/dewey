@echo off

set COMMAND=.\build.ps1
set COMMAND=%COMMAND% -Src .\src\main\docs
set COMMAND=%COMMAND% -Dest .\dist
set COMMAND=%COMMAND% -Style .\src\main\resources\lib\style.css
set COMMAND=%COMMAND% -StyleExtension .\src\main\resources\web\custom.css
set COMMAND=%COMMAND% -StyleTheme .\src\main\resources\web\themes\classic-dark.css
set COMMAND=%COMMAND% -Templates .\src\main\resources\templates
set COMMAND=%COMMAND% -TocLevels 4
set COMMAND=%COMMAND% -Production:$false
set COMMAND=%COMMAND% -Flatten:$true
set COMMAND=%COMMAND% -LogLevel INFO

powershell.exe -ExecutionPolicy Unrestricted -Command %COMMAND%

pause
