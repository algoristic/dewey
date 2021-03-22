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
        Write $line
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

# eigentliches Skript
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

# verarbeite index.ad
$IndexFile = Get-Content $Src\index.ad -Encoding UTF8
$IndexFileContent = Get-Content "$Resources\templates\index.root.ad" -Encoding UTF8
$IndexFileContent = $IndexFileContent | % {
    $_.Replace("[TocLevels]", "$TocLevels")
}
$IndexFileContent += "`n"
Foreach ($_ in $IndexFile)
{
    If($_ -and (-not ($_ -like "=*")))
    {
        $Doc = $_
        If($Doc -like "dev:*")
        {
            # im Prod-build werden mit dev: markierte Bereiche weggelassen, da sich diese noch in Arbeit befinden
            If($Production)
            {
                $IndexFileContent += ""
                Break
            }
            Else
            {
                # im dev-build werden dev: Bereiche drin gelassen
                $Doc = $Doc.Substring(4)
                # liegt hier allerdings eine Üerschrift vor, so wird diese einfach übernommen und muss nicht weiterverarbeitet werden
                If($Doc -like "=*")
                {
                    $IndexFileContent += "$Doc`n `n"
                    Break
                }
            }
        }
        $Document = "$Src\$Doc"
        $DocumentItem = Get-Item($Document)
        $DocumentPath = $DocumentItem.FullName
        $BuildPath = "$Dest\$Doc"
        $TargetLink = $Doc
        $FileName = [System.IO.Path]::GetFileName($DocumentPath)
        If($Flatten)
        {
            $BuildPath = "$Dest\$FileName"
            $TargetLink = $FileName
        }
        # alle asciidoc-Endungen durch die kompilierte html-Variante ersetzen
        $BuildPath = $BuildPath -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"
        $TargetLink = $TargetLink -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"

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
                $TemplatePath = "$Resources\templates\$TemplateName"
                    $Content = Get-Content $TemplatePath -Encoding UTF8
            }
            return $Content
        }
        $SrcPath = $DocumentItem.DirectoryName
        $BuildFile = "$SrcPath\_$FileName"
        $BuildContent | Out-File -FilePath $BuildFile -Encoding UTF8
        Write-Log "Compile: $BuildFile"
        Write-Log "Src: $Src, Dest: $Dest" DEBUG 1
        Write-Log "Build target: $BuildPath" DEBUG 1
        Write-Log "Reference in index.html: $TargetLink" DEBUG 1
        & asciidoctor.bat -o $BuildPath -a stylesheet=$BuildCss -a lang=de $BuildFile
        Remove-Item -Force $BuildFile

        # baue den Link zur enrsprechenden Seite (sowie eine kurze Zusammenfassung der Themen) auf
        $ReplaceValue = "`n===== link:$TargetLink[$Title]`n `n"
        $ContentSummary = ""
        $OriginalContent | ? { $_ -match "^== " } | % {
            $ContentSummary += ($_.Substring(3) + ", ")
        }
        $ContentSummary = $ContentSummary.Substring(0, ($ContentSummary.Length - 2))
        $ReplaceValue += "[horizontal]`n&mdash;:: $ContentSummary`n `n"
        $IndexFileContent += $ReplaceValue
    }
    Else
    {
        $IndexFileContent += "$_`n `n"
    }
}

$IndexFile = "$Dest\index.ad"
Write-Log "Create $IndexFile"
$Doc | Out-File -FilePath $IndexFile -Encoding UTF8
Write-Log "Compile $IndexFile "
& asciidoctor.bat -a stylesheet=$BuildCss -a lang=de $IndexFile

# lösche sämtliche anfallenden build-Artefakte
###Get-ChildItem $Dest | Remove-Item -Recurse -Include *.ad, *.adoc, *.asciidoc, *.css
# lösche leere Verzeichnisse rekursiv
Remove-Empty $Dest
