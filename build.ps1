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

$Topics = @{}
$SrcDocs = Get-ChildItem -Recurse -Path $Src | ? { $_.Extension -in ".asciidoc",".adoc",".ad" }
Foreach ($SrcDoc in $SrcDocs)
{
    $Content = Get-Content $SrcDoc.FullName
    $Meta = $Content | ? { $_.Contains(":dewey:") }
    if($Meta)
    {
        # entferne führendes '= ' vom Titel
        $Title = $Content[0]
        $Title = $Title.Substring(2).Trim()

        # entferne ':dewey:'-Deklaration und baue Liste aus der Themenhierarchie
        $Meta = ($Meta -Split ":dewey:")[1]
        $Meta = $Meta -Split ";" | % { $_.Trim() }
        # wenn nur ein Thema ausgezeichnet ist, wrappe das Thema in einer Liste mit einem Eintrag
        if(($Meta | Measure-Object).Count -eq 1)
        {
            $Meta = @($Meta)
        }

        for($index = 0; $index -lt $Meta.Length; $index++)
        {
            if($index -eq ($Meta.Length - 1))
            {
                echo "Ablage"
            }
            else
            {
                echo "Oberthema"
            }
        }
    }
}
