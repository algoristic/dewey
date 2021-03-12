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
        $line += "`t"
    }
    $line += $Message
    if(Is-RightLevel -WriteLevel $Level)
    {
        Write $line
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
        $TempItem = "$BuildDirectory\$TempItemName"
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

        # kompiliere .adoc nach .html
        Write-Log "Compile: $TempItem"
        Write-Log "Src: $Src, Dest: $Dest" DEBUG
        & asciidoctor.bat -R $Src -D $Dest $TempItem
        Remove-Item -Force $TempItem
        Write-Log "Finished: $_" DEBUG

        # es ist evtl. nicht notwendig hier bereits den $Dest-Teil davor zu hängen, da die
        # Pfade ja relativ zu einer Datei im obersten build-Verzeichnis funkionieren sollen!
        $TargetPath = ".$($TempItem.Substring($Src.Length))"
        # alle asciidoc-Endungen durch die kompilierte html-Variante ersetzen
        $TargetPath = $TargetPath -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"

        $CurrentTopics = $AllTopics
        For($index = 0; $index -le $Meta.Length; $index++)
        {
            If($index -eq ($Meta.Length))
            {
                # das hier ist berets die Tiefste Stufe = wir fügen unser Thema der Liste hinzu
                $CurrentTopics.add($Title, $TargetPath)
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
            $Prefix = Get-Prefix $Depth "" "======" " "
            $Result = $Result + "$($Prefix)link:$($Value)[$($_)]`n `n"
        }
    }
    return $Result
}
$Doc = Get-Content "$TemplateRoot/index.root.ad" -Encoding UTF8
$Doc += "`n"

# erstelle eine Navigations-Seite
$Doc += Print-Topics -Depth 0 -Topics $AllTopics

# schreibe die Navigations-Seite heraus und kompiliere und lösche sie anschließend
$OutFile = "$($Dest)/index.adoc"
Write-Log "Create $OutFile"
$Doc | Out-File -FilePath $OutFile -Encoding UTF8
Write-Log "Compile $OutFile "
& asciidoctor.bat $OutFile
Remove-Item $OutFile
