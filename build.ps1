<#
    AUTHOR: MARCO LEWEKE
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String]$Src,

    [Parameter(Mandatory=$true)]
    [string]$Dest,

    [Parameter(Mandatory=$true)]
    [string]$Templates,

    [Parameter(Mandatory=$true)]
    [switch]$Production,

    [Parameter(Mandatory=$true)]
    [string]$Style,

    [Parameter(Mandatory=$false)]
    [string]$StyleExtension,

    [Parameter(Mandatory=$false)]
    [string]$StyleTheme,

    # Definiere die Tiefe der Inhaltsverzeichnisses auf der Startseite
    [Parameter(Mandatory=$true)]
    [string]$TocLevels,

    # Behält die ursprünliche Verzeichnisstruktur bei, wenn -Flatten:$false
    [Parameter(Mandatory=$true)]
    [switch]$Flatten = $true,

    [Parameter(Mandatory=$true)]
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
    $line = [string]::Format("{0} {1,-6}", $stamp, $Level)
    for($i = 0; $i -le $Depth; $i++)
    {
        $line += "  "
    }
    $line += $Message
    if(Is-RightLevel -WriteLevel $Level)
    {
        Write-Host $line
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
        [array]$Template,

        [Parameter(Mandatory=$true)]
        [string]$Caller
    )
    $TemplatePath = "$Templates\$Template"
    $Content = Get-Content $TemplatePath -Encoding UTF8
    $Resolved = ""
    $Content | % {
        $Line = "$_`n"
        $Line = $Line.Replace("[backToCaller]", "$Caller")
        $Line = $Line.Replace("[TocLevels]", "$TocLevels")
        $Resolved += $Line
    }
    Return $Resolved
}

Function Render-ContentLink
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Link,

        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$true)]
        [array]$Content
    )
    $Text = "===== link:$TargetLink[$Title]`n"
    $ContentSummary = Render-ContentSummary $Content
    $Text += "[horizontal]`n&mdash;::: $ContentSummary`n `n"
    Return $Text
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
        [string]$Css,

        [Parameter(Mandatory=$true)]
        [string]$Caller,

        [Parameter(Mandatory=$true)]
        [int]$LogDepth
    )
    $RenderStopwatch =  [system.diagnostics.stopwatch]::StartNew()

    $File = Get-Content $FilePath -Encoding UTF8
    $FileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $FullFileName = [System.IO.Path]::GetFileName($FilePath)
    $IndexFileContent = ""

    $Title = ""

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
            If($Doc -like "prod:*")
            {
                If(-not $Production)
                {
                    $IndexFileContent += ""
                    Continue
                }
                Else
                {
                    $Doc = $Doc.Substring(5)
                }
            }
            If($Doc -like "include:*")
            {
                $Doc = $Doc.Substring(8)
                Write-Log "Build include: $Doc" INFO ($LogDepth + 1)
                $IndexFileContent += Render-IncludeFile $Doc $Css "\$FileName" ($LogDepth + 2)
            }
            ElseIf($Doc -like "index:*")
            {
                $Doc = $Doc.Substring(6)
                Write-Log "Build index: $Doc" INFO ($LogDepth + 1)
                $IndexFileContent += Render-IndexFile "$Src\$Doc" $Css "\$FileName" ($LogDepth + 2)
            }
            ElseIf($Doc -like ":dewey-template:*")
            {
                $Doc = $Doc.Substring(17)
                $IndexFileContent += "`n"
                $IndexFileContent += Resolve-Template $Doc $Caller
                $IndexFileContent += "`n"
            }
            Else
            {
                If($Doc -match "^= ")
                {
                    $Title = $Doc.Substring(2)
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
            $IndexFileContent += "`n"
        }
    }
    $Index = "$Dest\$FullFileName"
    $IndexFileContent | Out-File -FilePath $Index -Encoding UTF8

    $BuildStopwatch =  [system.diagnostics.stopwatch]::StartNew()
    & asciidoctor.bat -a stylesheet=$Css -a lang=de -q $Index
    $BuildStopwatch.Stop()
    $BuildTime = $BuildStopwatch.Elapsed.ToString('hh\:mm\:ss\:fff')
    Write-Log "Build time ($FullFileName): $BuildTime" DEBUG $LogDepth

    $TargetLink = ".\$FileName"
    If(-not $Production)
    {
        $TargetLink += ".html"
    }

    $Link = Render-ContentLink $TargetLink $Title $File
    $RenderStopwatch.Stop()
    $RenderTime = $RenderStopwatch.Elapsed.ToString('hh\:mm\:ss\:fff')
    Write-Log "Render time ($FullFileName): $RenderTime" DEBUG $LogDepth
    Return $Link
}

Function Render-IncludeFile
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$File,

        [Parameter(Mandatory=$true)]
        [string]$Css,

        [Parameter(Mandatory=$true)]
        [string]$Caller,

        [Parameter(Mandatory=$true)]
        [int]$LogDepth
    )

    $RenderStopwatch =  [system.diagnostics.stopwatch]::StartNew()
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
            $Content = Resolve-Template $TemplateName $Caller
        }
        return $Content
    }
    If(-not (Test-Path $BuildPath))
    {
        $SrcPath = $DocumentItem.DirectoryName
        $BuildFile = "$SrcPath\_$FileName"
        $BuildContent | Out-File -FilePath $BuildFile -Encoding UTF8
        $BuildStopwatch =  [system.diagnostics.stopwatch]::StartNew()
        & asciidoctor.bat -o $BuildPath -a stylesheet=$Css -a lang=de $BuildFile
        Remove-Item -Force $BuildFile
        $BuildStopwatch.Stop()
        $BuildTime = $BuildStopwatch.Elapsed.ToString('hh\:mm\:ss\:fff')
        Write-Log "Build time ($FileName): $BuildTime" DEBUG $LogDepth
    }
    Else
    {
        Write-Log "Skip existing: $FileName" DEBUG $LogDepth
    }

    # baue den Link zur enrsprechenden Seite (sowie eine kurze Zusammenfassung der Themen) auf
    $Link = Render-ContentLink $TargetLink $Title $OriginalContent
    $RenderStopwatch.Stop()
    $RenderTime = $RenderStopwatch.Elapsed.ToString('hh\:mm\:ss\:fff')
    Write-Log "Render time ($FileName): $RenderTime" DEBUG $LogDepth
    Return $Link
}

# eigentliches Skript
Write-Log "Start :DEWEY: => Params:"
Write-Log "Src = $Src" INFO 1
Write-Log "Dest = $Dest" INFO 1
Write-Log "Style = $Style" INFO 1
Write-Log "StyleExtension = $StyleExtension" INFO 1
Write-Log "StyleTheme = $StyleTheme" INFO 1
Write-Log "Templates = $Templates" INFO 1
Write-Log "Production = $Production" INFO 1
Write-Log "TocLevels = $TocLevels" INFO 1
Write-Log "Flatten = $Flatten" INFO 1
Write-Log "LogLevel = $LogLevel" INFO 1
$Stopwatch =  [system.diagnostics.stopwatch]::StartNew()

# build Verzeichnis leeren und neu aufbauen
If(Test-Path $Dest)
{
    Remove-Item -Path $Dest -Force -Recurse
}
New-Item $Dest -ItemType "directory" | Out-Null

# Erstelle build-style Datei (aus default+theme), nutze diese und lösche sie danach
# Pfad für (temporäre) build-CSS
$BuildCss = "$Dest\_build.css"
$BuildStyle = @()
$DefaultStyle = Get-Content $Style -Encoding UTF8
$DefaultStyle | % { $BuildStyle += $_ }

If($StyleExtension -and (Test-Path $StyleExtension))
{
    $CustomStyle = Get-Content $StyleExtension -Encoding UTF8
    $CustomStyle | % { $BuildStyle += $_ }
}

If($StyleTheme -and (Test-Path $StyleTheme))
{
    $ThemeStyle = Get-Content $StyleTheme -Encoding UTF8
    $ThemeStyle | % { $BuildStyle += $_ }
}

$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines($BuildCss, $BuildStyle, $Utf8NoBomEncoding)
$BuildCss = (Get-Item $BuildCss).FullName


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
Write-Log "Build index: index.ad"
Render-IndexFile "$Src\index.ad" $BuildCss "~NONE~" 0 | Out-Null

If($Production)
{
    Write-Log "Delete build-Artifacts" DEBUG
    # lösche sämtliche anfallenden build-Artefakte
    Get-ChildItem $Dest | Remove-Item -Recurse -Include *.ad, *.adoc, *.asciidoc, *.css
    # lösche leere Verzeichnisse rekursiv
}
Remove-Empty $Dest
$Stopwatch.Stop()
$Time = $Stopwatch.Elapsed.ToString('hh\:mm\:ss\:fff')
Write-Log "Finished! Elapsed Time: $Time"
