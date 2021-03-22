<#
    AUTHOR: MARCO LEWEKE
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String]$Src,

    [Parameter(Mandatory=$true)]
    [string]$Dest,

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
    [string]$TemplateRoot = "./src/main/resources/templates",

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
$AllTopics = @{}

# build Verzeichnis leeren und neu aufbauen
If(Test-Path $Dest)
{
    Remove-Item -Path $Dest -Force -Recurse
}
New-Item $Dest -ItemType "directory" | Out-Null

# Erstelle build-style Datei (aus default+theme), nutze diese und lösche sie danach
$DefaultCss = "$Src/resources/lib/style.css"
$DefaultCssPath = (Get-Item $DefaultCss).FullName
$ThemeCss = "$Src/resources/web/themes/$Theme.css"
$CustomCss = "$Src/resources/web/custom.css"
$ThemeExists = Test-Path $ThemeCss
$BuildCss = $DefaultCssPath
If($ThemeExists)
{
    Write-Log "Use theme $theme"
    # Pfad für temporäre build-CSS
    $BuildCss = "$Dest/_build.css"
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
    New-Item $Dest/pages/images -ItemType "directory" | Out-Null
    Get-ChildItem -Path $Src -Recurse -Filter *.png | Copy-Item -Destination $Dest/pages/images
}
Else
{
    Get-ChildItem $Src | Copy-Item -Destination $Dest -Recurse -Filter *.png
}

$SrcDocs = Get-ChildItem -Recurse -Path $Src | ? { $_.Extension -in ".asciidoc",".adoc",".ad" }
Foreach ($SrcDoc in $SrcDocs)
{
    $SrcPath = $SrcDoc.FullName
    $OriginalContent = Get-Content $SrcPath -Encoding UTF8
    $Meta = $OriginalContent | ? { $_.Contains(":dewey:") }
    If($Meta)
    {
        ### Sammle Daten für index-Dokument
        # entferne führendes '= ' vom Titel
        $Title = $OriginalContent[0]
        $Title = $Title.Substring(2).Trim()

        # entferne ':dewey:'-Deklaration und baue Liste aus der Themenhierarchie
        $Meta = ($Meta -Split ":dewey:")[1]
        $Meta = $Meta -Split ";" | % { $_.Trim() }
        # wenn nur ein Thema ausgezeichnet ist, wrappe das Thema in einer Liste mit einem Eintrag
        If(($Meta | Measure-Object).Count -eq 1)
        {
            $Meta = @($Meta)
        }

        # erstelle den build-Path, indem die Verzeichnisse miteinander geschnitten werden
        # schneide den aboluten Pfad heraus
        $AbsolutePart = $SrcPath.IndexOf($Src.Substring(1))
        $BuildPath = $SrcPath.Substring($AbsolutePart)
        $BuildPath = ".$BuildPath"

        # erstelle ein temporäres build-Dokument, in dem die ':dewey-x'-Platzhalter aufgelöst werden
        $OriginalItem = Get-Item $BuildPath
        $OriginalName = $OriginalItem.Name
        $TempItemName = "_$OriginalName"
        $BuildDirectory = $OriginalItem.DirectoryName
        $TempItem = "$BuildDirectory/$TempItemName"
        # schreibe die Inhalte des Original-Dokuments in das temporäre build-Dokument
        $BuildContent = $OriginalContent | % {
            $Content = $_
            If($_.Contains(":dewey-template:"))
            {
                $TemplateName = $_.Substring(":dewey-template: ".Length)
                $TemplatePath = "$TemplateRoot/$TemplateName"
                $Content = Get-Content $TemplatePath -Encoding UTF8
            }
            return $Content
        }
        $BuildContent | Out-File -FilePath $TempItem -Encoding UTF8
        $TempItem = $TempItem.Substring($AbsolutePart)
        $TempItem = ".$TempItem"

        # Pfade ja relativ zu einer Datei im obersten build-Verzeichnis funkionieren sollen!
        $TargetPath = ".$($TempItem.Substring($Src.Length))"
        $TargetPath = $TargetPath.Substring(0, ($TargetPath.Length - ($TempItemName.Length + 1)))
        If($Flatten) {
            $TargetPath = "pages/$OriginalName"
        }
        Else
        {
            $TargetPath = "$TargetPath/$OriginalName"
        }
        # alle asciidoc-Endungen durch die kompilierte html-Variante ersetzen
        $TargetPath = $TargetPath -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"

        # bereite den Zielpfad als relativ zum root-Verzeichnis auf
        If($Flatten)
        {
            $BuildTarget = "$Dest/$TargetPath"
        }
        Else
        {
            $BuildTarget = "$Dest/$($TargetPath.Substring(2))"
        }

        # kompiliere .adoc nach .html
        Write-Log "Compile: $TempItem"
        Write-Log "Src: $Src, Dest: $Dest" DEBUG 1
        Write-Log "Build target: $BuildTarget" DEBUG 1
        Write-Log "Reference in index.html: $TargetPath" DEBUG 1
        & asciidoctor.bat -o $BuildTarget -a stylesheet=$BuildCss -a lang=de $TempItem
        Remove-Item -Force $TempItem
        Write-Log "Finished: $BuildTarget" DEBUG

        If($Production)
        {
            $TargetPath = $TargetPath.Substring(0, ($TargetPath.Length - 5))
        }
        $ContentSummary = ""
        $OriginalContent | ? { $_ -match "^== " } | % {
            $ContentSummary += ($_.Substring(3) + ", ")
        }
        $ContentSummary = $ContentSummary.Substring(0, ($ContentSummary.Length - 2))

        # verarbeite die angegebene Ordnung im Dokument für die Menüstruktur im index.html
        $CurrentTopics = $AllTopics
        For($index = 0; $index -le $Meta.Length; $index++)
        {
            If($index -eq ($Meta.Length))
            {
                # das hier ist berets die Tiefste Stufe = wir fügen unser Thema der Liste hinzu
                $CurrentTopics.add($Title, @( $TargetPath, $ContentSummary ))
            }
            Else
            {
                # wir prüfen, ob der Themenbereich existiert, falls nicht, wird er neu angelegt
                $Topic = $Meta[$index]
                If(-Not ($CurrentTopics.ContainsKey($Topic)))
                {
                    $CurrentTopics[$Topic] = @{}
                }
                $CurrentTopics = $CurrentTopics[$Topic]
            }
        }
    }
}

Function Get-Prefix
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [int32]$Depth,

        [Parameter(Mandatory=$false)]
        [string]$Prefix = "",

        [Parameter(Mandatory=$false)]
        [string]$Start = "",

        [Parameter(Mandatory=$false)]
        [string]$End = ""
    )

    $Result = $Start
    For($index = 0; $index -lt $Depth; $index++)
    {
        $Result += $Prefix
    }
    return ($Result + $End)
}

Function Print-Topics
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [int32]$Depth,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Topics
    )

    $Result = ""
    $Topics.keys | % {
        $Value = $Topics[$_]
        $IsTopic = $Value.GetType().Name -eq "Hashtable"
        If($IsTopic)
        {
            # hier startet die Rekursion
            $Prefix = Get-Prefix $Depth "=" "==" " "
            $Result = $Result + "$($Prefix)$($_)`n `n"
            $Result += Print-Topics -Depth ($Depth + 1) -Topics $Value
        }
        Else
        {
            $Prefix = Get-Prefix $Depth "" "=====" " "
            $Result += "$($Prefix)link:$($Value[0])[$($_)]`n `n"
            $Result += "[horizontal]`n&mdash;:: $($Value[1])`n `n"
        }
    }
    return $Result
}

$Doc = Get-Content "$TemplateRoot/index.root.ad" -Encoding UTF8
$Doc = $Doc | % {
    $_.Replace("[TocLevels]", "$TocLevels")
}
$Doc += "`n"

# erstelle eine Navigations-Seite
$Doc += Print-Topics -Depth 0 -Topics $AllTopics

# schreibe die Navigations-Seite heraus und kompiliere und lösche sie anschließend
$OutFile = "$($Dest)/index.adoc"
Write-Log "Create $OutFile"
$Doc | Out-File -FilePath $OutFile -Encoding UTF8
Write-Log "Compile $OutFile "
& asciidoctor.bat -a stylesheet=$BuildCss -a lang=de $OutFile
# lösche sämtliche anfallenden build-Artefakte
Get-ChildItem $Dest | Remove-Item -Recurse -Include *.ad, *.adoc, *.asciidoc, *.css
# lösche leere Verzeichnisse rekursiv
Remove-Empty $Dest
