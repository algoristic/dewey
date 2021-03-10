<#
    AUTHOR: MARCO LEWEKE
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String]$Src,

    [Parameter(Mandatory=$true)]
    [string[]]$Dest
)

$AllTopics = @{}
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
        # es ist evtl. nicht notwendig hier bereits den $Dest-Teil davor zu hängen, da die
        # Pfade ja relativ zu einer Datei im obersten build-Verzeichnis funkionieren sollen!
        # $BuildPath = "$($Dest)\$($BuildPath.Substring($Src.Length))"
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
