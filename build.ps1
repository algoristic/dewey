<#
    AUTHOR: MARCO LEWEKE
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String]$Src,

    [Parameter(Mandatory=$true)]
    [string[]]$Dest,

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
[System.Collections.ArrayList]$CompileDocuments = @()
$SrcDocs = Get-ChildItem -Recurse -Path $Src | ? { $_.Extension -in ".asciidoc",".adoc",".ad" }
Foreach ($SrcDoc in $SrcDocs)
{
    $SrcPath = $SrcDoc.FullName
    $Content = Get-Content $SrcPath
    $Meta = $Content | ? { $_.Contains(":dewey:") }
    If($Meta)
    {
        # entferne führendes '= ' vom Titel
        $Title = $Content[0]
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
        # den Pfad für's kompilieren schonmal merken
        $CompileDocuments.Add(".$($BuildPath)") | Out-Null

        # es ist evtl. nicht notwendig hier bereits den $Dest-Teil davor zu hängen, da die
        # Pfade ja relativ zu einer Datei im obersten build-Verzeichnis funkionieren sollen!
        $BuildPath = ".\$($BuildPath.Substring($Src.Length))"
        # alle asciidoc-Endungen durch die kompilierte html-Variante ersetzen
        $BuildPath = $BuildPath -Replace ".asciidoc",".html" -Replace ".adoc",".html" -Replace ".ad",".html"

        $CurrentTopics = $AllTopics
        For($index = 0; $index -le $Meta.Length; $index++)
        {
            If($index -eq ($Meta.Length))
            {
                # das hier ist berets die Tiefste Stufe = wir fügen unser Thema der Liste hinzu
                $CurrentTopics.add($Title, $BuildPath)
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

Function Get-Whitespace
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [int32]$Depth
    )

    $Whitespace = ""
    For($index = 0; $index -lt $Depth; $index++)
    {
        $Whitespace += "    "
    }
    return $Whitespace
}

Function Get-Colons
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [int32]$Depth
    )

    $Colons = "::"
    For($index = 0; $index -lt $Depth; $index++)
    {
        $Colons += ":"
    }
    return $Colons
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
            $Colons = Get-Colons -Depth $Depth
            $Whitespace = Get-Whitespace -Depth $Depth
            $Result = $Result + "$($Whitespace)$($_)$($Colons)`n"
            $Result += Print-Topics -Depth ($Depth + 1) -Topics $Value
        }
        Else
        {
            $Whitespace = Get-Whitespace -Depth $Depth
            $Result = $Result + "$($Whitespace)link:$($Value)[$($_)] +`n"
        }
    }
    return $Result
}

$Doc = "= Handbuch _Marco Herzig_


"

# erstelle eine Navigations-Seite
$Doc += Print-Topics -Depth 0 -Topics $AllTopics

# build Verzeichnis leeren und neu aufbauen
If(Test-Path $Dest)
{
    Remove-Item -Path $Dest -Force -Recurse
}
New-Item $Dest -ItemType "directory" | Out-Null

# schreibe die Navigations-Seite heraus und kompiliere und lösche sie anschließend
$OutFile = "$($Dest)\_index.adoc"
$Doc | Out-File -FilePath $OutFile -Encoding ASCII
& "asciidoctor.bat" $OutFile
Remove-Item $OutFile

# kompiliere asciidoc nach html
$SrcPath = (Get-Item $Src).FullName
$DestPath = (Get-Item $Dest).FullName
$CompileDocuments | % {
    $FilePath = (Get-Item $_).FullName
    Write-Log "Compile: $FilePath"
    Write-Log "Src: $SrcPath, Dest: $DestPath" DEBUG
    & C:\tools\ruby30\bin\asciidoctor.bat -R $SrcPath -D $DestPath $FilePath
    Write-Log "Finished: $FilePath" DEBUG
}
