<#
    AUTHOR: MARCO LEWEKE
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [String]$Src = ".\src\main\docs",

    [Parameter(Mandatory=$false)]
    [string]$Dest = ".\dist",

    [Parameter(Mandatory=$false)]
    [string]$Resources = ".\src\main\resources",

    [Parameter(Mandatory=$false)]
    [switch]$Production = $false,

    [Parameter(Mandatory=$false)]
    [string]$Theme = "dark",

    # Definiere die Tiefe der Inhaltsverzeichnisses auf der Startseite
    [Parameter(Mandatory=$false)]
    [string]$TocLevels = 10,

    # Behält die ursprünliche Verzeichnisstruktur bei, wenn -Flatten:$false
    [Parameter(Mandatory=$false)]
    [switch]$Flatten = $true,

    [Parameter(Mandatory=$false)]
    [string]$TemplateRoot = ".\src\main\resources\templates",

    [Parameter(Mandatory=$false)]
    [ValidateSet("TRACE", "DEBUG","INFO","WARN","ERROR")]
    [String]$LogLevel = "INFO"
)

# Logging Standardbausteine
Function Is-RightLevel
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$WriteLevel
    )

    $Levels = "TRACE", "DEBUG","INFO","WARN","ERROR"
    $LogPriority = $Levels.IndexOf($LogLevel)
    $WritePriority = $Levels.IndexOf($WriteLevel)
    return ($LogPriority -le $WritePriority)
}
Function Write-Log
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("TRACE", "DEBUG","INFO","WARN","ERROR")]
        [String]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [String]$Depth = 0
    )

    $stamp = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
    $line = "$stamp $Level"
    for($i = 0; $i -le $Depth; $i++)
    {
        $line += "  "
    }
    $line += $Message
    if(Is-RightLevel -WriteLevel $Level)
    {
        Write-Output $line
    }
}

Function Remove-Empty
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$Dir
    )
    Get-ChildItem $Dir | % {
        If($_.PSIsContainer)
        {
            Remove-Empty $_.FullName
            If(!(Get-ChildItem -Recurse -Path $_.FullName))
            {
                Remove-Item $_.FullName -Confirm:$false
            }
        }
    }
}

Function Resolve-Template
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [array]$Template
    )
    $TemplatePath = "$Resources\templates\$Template"
    $Content = Get-Content $TemplatePath -Encoding UTF8
    $Resolved = ""
    $Content | % {
        $Resolved += "$_`n"
    }
    Return $Resolved
}

Function Render-ContentSummary
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [array]$Content
    )

    $ContentSummary = ""
    $Content | ? { $_ -match "^== " } | % {
        $ContentSummary += ($_.Substring(3) + ", ")
    }
    If($ContentSummary.Length -gt 2)
    {
        $ContentSummary = $ContentSummary.Substring(0, ($ContentSummary.Length - 2))
    }
    return $ContentSummary
}

Function Render-IndexFile
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$Css

    )
    $File = Get-Content $FilePath -Encoding UTF8
    $IndexFileContent = ""

    $Title = $File[0]
    $Title = $Title.Substring(2).Trim()

    Foreach ($_ in $File)
    {
        $Doc = $_
        If($Doc)
        {
            If($Doc -like "dev:*")
            {
                If($Production)
                {
                    $IndexFileContent += ""
                    Continue
                }
                Else
                {
                    $Doc = $Doc.Substring(4)
                }
            }
            If($Doc -like "include:*")
            {
                $Doc = $Doc.Substring(8)
                $IndexFileContent += Render-IncludeFile $Doc $Css
            }
            ElseIf($Doc -like "index:*")
            {
                $Doc = $Doc.Substring(6)
                $IndexFileContent += Render-IndexFile "$Src\$Doc" $Css
            }
            ElseIf($Doc -like ":dewey-template:*")
            {
                $Doc = $Doc.Substring(17)
                $IndexFileContent += "`n"
                $IndexFileContent += Resolve-Template $Doc
            }
            Else
            {
                If($Doc -match "^= ")
                {
                    $IndexFileContent += $Doc
                }
                Else
                {
                    $IndexFileContent += "$Doc`n"
                }
            }
        }
        Else
        {
            $IndexFileContent += ""
        }
    }
    $FileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $Index = "$Dest\$FileName.ad"
    $IndexFileContent | Out-File -FilePath $Index -Encoding UTF8
    & asciidoctor.bat -a stylesheet=$Css -a lang=de -q $Index

    $TargetLink = ".\$FileName"
    If(-not $Production)
    {
        $TargetLink += ".html"
    }

    $Value = "=== link:$TargetLink[$Title]`n"
    $ContentSummary = Render-ContentSummary $File
    $Value += "&mdash; $ContentSummary`n `n"
    Return $Value
}

Function Render-IncludeFile
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$File,

        [Parameter(Mandatory=$true)]
        [string]$Css
    )

    $Document = "$Src\$File"
    $DocumentItem = Get-Item($Document)
    $DocumentPath = $DocumentItem.FullName
    $BuildPath = "$Dest\$File"
    $TargetLink = $File
    $FileName = [System.IO.Path]::GetFileName($DocumentPath)
    If($Flatten)
    {
        $BuildPath = "$Dest\$FileName"
        $TargetLink = $FileName
    }
    # alle asciidoc-Endungen durch die kompilierte html-Variante ersetzen
    $BuildPath = $BuildPath -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"
    $Ending = ".html"
    If($Production)
    {
        $Ending = ""
    }
    $TargetLink = $TargetLink -Replace ".asciidoc",$Ending -Replace ".adoc",$Ending -Replace ".ad",$Ending

    # verarbeite die Zieldatei
    $OriginalContent = Get-Content $Document -Encoding UTF8
    # Sammle Daten für index-Dokument
    # entferne führendes '= ' vom Titel
    $Title = $OriginalContent[0]
    $Title = $Title.Substring(2).Trim()
    # ersetze im Inhalt den Template-Verweis durch das tatsächliche Template
    $BuildContent = $OriginalContent | % {
        $Content = $_
        If($_.Contains(":dewey-template:"))
        {
            $TemplateName = $_.Substring(":dewey-template: ".Length)
            $Content = Resolve-Template $TemplateName
        }
        return $Content
    }
    $SrcPath = $DocumentItem.DirectoryName
    $BuildFile = "$SrcPath\_$FileName"
    $BuildContent | Out-File -FilePath $BuildFile -Encoding UTF8
    & asciidoctor.bat -o $BuildPath -a stylesheet=$Css -a lang=de $BuildFile
    Remove-Item -Force $BuildFile

    # baue den Link zur enrsprechenden Seite (sowie eine kurze Zusammenfassung der Themen) auf
    $ReplaceValue = "link:$TargetLink[$Title]::`n"
    $ContentSummary = Render-ContentSummary $OriginalContent
    $ReplaceValue += "&mdash; $ContentSummary`n `n"
    Return $ReplaceValue
}

# eigentliches Skript
Write-Log "Src: $Src, Dest: $Dest"
# build Verzeichnis leeren und neu aufbauen
If(Test-Path $Dest)
{
    Remove-Item -Path $Dest -Force -Recurse
}
New-Item $Dest -ItemType "directory" | Out-Null

# Erstelle build-style Datei (aus default+theme), nutze diese und lösche sie danach
$DefaultCss = "$Resources\lib\style.css"
$DefaultCssPath = (Get-Item $DefaultCss).FullName
$ThemeCss = "$Resources\web\themes\$Theme.css"
$CustomCss = "$Resources\web\custom.css"
$ThemeExists = Test-Path $ThemeCss
$BuildCss = $DefaultCssPath
If($ThemeExists)
{
    Write-Log "Use theme $theme"
    # Pfad für temporäre build-CSS
    $BuildCss = "$Dest\_build.css"
    # lese Inhalte (Standard und Theme)
    $DefaultStyle = Get-Content $DefaultCss -Encoding UTF8
    $CustomStyle = Get-Content $CustomCss -Encoding UTF8
    $ThemeStyle = Get-Content $ThemeCss -Encoding UTF8
    # schreibe Inhalte in build-CSS
    $BuildStyle = @()
    $DefaultStyle | % { $BuildStyle += $_ }
    $CustomStyle | % { $BuildStyle += $_ }
    $ThemeStyle | % { $BuildStyle += $_ }

    # Wichtig: das Rausschreiben funktioniert nur so, da auf dem Standardweg (via Out-File)
    # der Output-Typ immer "UTF-8-BOM" ist (anstatt) "UTF-8".
    # Das wiederum sorgt dafür, dass das CSS keine externen Quellen lädt - wie z. B. fonts.google oder fontawesome.io
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($BuildCss, $BuildStyle, $Utf8NoBomEncoding)
    $BuildCss = (Get-Item $BuildCss).FullName
}
Else
{
    Write-Log "Theme $Theme does not exist (under path '$ThemeCss')" WARN
    Write-Log "Use default asciiDoc theme"
}

# Bilder kopieren
If($Flatten) {
    New-Item $Dest\images -ItemType "directory" | Out-Null
    Get-ChildItem -Path $Src -Recurse -Filter *.png | Copy-Item -Destination $Dest\images
}
Else
{
    Get-ChildItem $Src | Copy-Item -Destination $Dest -Recurse -Filter *.png
}

# verarbeite zentrale index.ad
Render-IndexFile "$Src\index.ad" $BuildCss | Out-Null

If($Production)
{
    Write-Log "Delete build-Artifacts" DEBUG
    # lösche sämtliche anfallenden build-Artefakte
    Get-ChildItem $Dest | Remove-Item -Recurse -Include *.ad, *.adoc, *.asciidoc, *.css
    # lösche leere Verzeichnisse rekursiv
}
Remove-Empty $Dest
Write-Log "Finished!"
