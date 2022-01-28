#Requires -Version 7.0
<#

.SYNOPSIS
Optimize the AADConnect Config Export file into individual files.

.DESCRIPTION
Using an AADConnect Config Export file, writes each rule into a separate file
to make it easier for version or environment comparisons.
All files are created in a subfolder based on the name of the input file.

.PARAMETER InputFilePath
Path to the input AADConnect Config Export file.

.INPUTS
You cannot pipe input into this script.

.OUTPUTS
This script does not pipeline any output objects.

.EXAMPLE
.\Write-ExportedRulesToFolder.ps1 -InputFilePath C:\temp\Export.json
This will read all the content in the Export.json file and write them to the output folder.
Each file name is based on the rule's name.

#>

[CmdletBinding()]
Param(
      [Parameter(Mandatory=$True)]  [string]$InputFilePath
)

function ConvertTo-Hashtable {
    #Original code reference for this function from Adam Bertram https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $object
                }
            ) | Sort-Object
            Write-Output -NoEnumerate $collection
        } elseif ($InputObject -is [psobject]) {
            $hash = [ordered] @{}
            foreach ($property in ($InputObject.PSObject.Properties | Sort-Object -Property "Name")) {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            $hash
        } else {
            $InputObject
        }
    }
}

function ConvertTo-SortedHashTableByName {
    param (
        [array] $InputObject
    )

    $ItemNames_Position = @{}
    $Position = 0
    ForEach ($Item in $InputObject) {
        $ItemNames_Position[$Item.Name] = $Position
        $Position++
    }
    
    $SortedItems = @()
    ForEach ($Item in ($ItemNames_Position.Keys | Sort-Object)) {
        $SortedItems += $InputObject[$ItemNames_Position[$Item]]
    }

    $SortedItems
        
}

If (!(Test-Path -PathType Leaf -Path $InputFilePath)) {
    Write-Error "Did not find Input file $InputFilePath"
    exit 1
}

#Ensure the Output folder has been created and is empty
$OutputFolder = ($InputFilePath.Trim() + ".ForCompare").Replace("\.ForCompare", ".ForCompare")
If (Test-Path $OutputFolder ) {
	Remove-Item $OutputFolder\* -recurse
} else {
	New-Item -Path $OutputFolder -type directory | Out-Null
}

#Read in the JSON 
$JSON = get-content -raw $InputFilePath | ConvertFrom-Json

#Make some normalizations to the rules
#on prem can have multiple MAs, so is an array, AAD connector is not array indexed

#Default sort the JSON into ordered hashtables

$Config = $JSON | ConvertTo-HashTable

#Custom sort the rules by name
for($i = 0; $i -lt $Config.onpremisesDirectoryPolicy.count; $i++) {
    $SortedRules = ConvertTo-SortedHashTableByName $Config.onpremisesDirectoryPolicy[$i].customSynchronizationRules
    $Config["onpremisesDirectoryPolicy"][$i]["customSynchronizationRules"] = $SortedRules
    $SortedRules = ConvertTo-SortedHashTableByName $Config.onpremisesDirectoryPolicy[$i].standardSynchronizationRules
    $Config["onpremisesDirectoryPolicy"][$i]["standardSynchronizationRules"] = $SortedRules
}

$SortedRules = ConvertTo-SortedHashTableByName $Config.azureDirectoryPolicy.customSynchronizationRules
$Config["azureDirectoryPolicy"]["customSynchronizationRules"] = $SortedRules
$SortedRules = ConvertTo-SortedHashTableByName $Config.azureDirectoryPolicy.standardSynchronizationRules
$Config["azureDirectoryPolicy"]["standardSynchronizationRules"] = $SortedRules


#Normalize the GUIDs of the sync rules
for($i = 0; $i -lt $Config.onpremisesDirectoryPolicy.count; $i++) {
    ForEach ($SyncRule in $Config.onpremisesDirectoryPolicy[$i].customSynchronizationRules) {
        $SyncRule["internalIdentifier"] = "GUID"
        $SyncRule["uniqueIdentifier"] = "GUID"
    }
    ForEach ($SyncRule in $Config.onpremisesDirectoryPolicy[$i].standardSynchronizationRules) {
        $SyncRule["uniqueIdentifier"] = "GUID"
    }
}
ForEach ($SyncRule in $Config.azureDirectoryPolicy.customSynchronizationRules) {
    $SyncRule["internalIdentifier"] = "GUID"
    $SyncRule["uniqueIdentifier"] = "GUID"
}
ForEach ($SyncRule in $Config.azureDirectoryPolicy.standardSynchronizationRules) {
    $SyncRule["uniqueIdentifier"] = "GUID"
}

#Normalize the connector GUIDs
for($i = 0; $i -lt $Config.onpremisesDirectoryPolicy.count; $i++) {
    $Config["onpremisesDirectoryPolicy"][$i]["uniqueIdentifier"] = "GUID"
}

#Output each rule
for($i = 0; $i -lt $Config.onpremisesDirectoryPolicy.count; $i++) {
    ForEach ($SyncRule in $Config.onpremisesDirectoryPolicy[$i].customSynchronizationRules) {
        $RuleName = $Config.onpremisesDirectoryPolicy[$i].friendlyName + " - CUSTOM - " + $SyncRule."name"
        $RuleName = $RuleName.Replace("\", "").Replace("/", "").Replace("*", "").Replace(":", "").Replace("?", "").Replace("<", "").Replace(">", "").Replace("|", "")
        $SyncRule | ConvertTo-Json -Depth 64 | Out-File (Join-Path -Path $OutputFolder -ChildPath ($RuleName + ".json"))
    }
    ForEach ($SyncRule in $Config.onpremisesDirectoryPolicy[$i].standardSynchronizationRules) {
        $RuleName = $Config.onpremisesDirectoryPolicy[$i].friendlyName + " - DEFAULT - " + $SyncRule."name"
        $RuleName = $RuleName.Replace("\", "").Replace("/", "").Replace("*", "").Replace(":", "").Replace("?", "").Replace("<", "").Replace(">", "").Replace("|", "")
        $SyncRule | ConvertTo-Json -Depth 64 | Out-File (Join-Path -Path $OutputFolder -ChildPath ($RuleName + ".json"))
    }
}
ForEach ($SyncRule in $Config.azureDirectoryPolicy.customSynchronizationRules) {
    $RuleName = "AAD - CUSTOM - " + $SyncRule."name"
    $RuleName = $RuleName.Replace("\", "").Replace("/", "").Replace("*", "").Replace(":", "").Replace("?", "").Replace("<", "").Replace(">", "").Replace("|", "")
    $SyncRule | ConvertTo-Json -Depth 64 | Out-File (Join-Path -Path $OutputFolder -ChildPath ($RuleName + ".json"))
}
ForEach ($SyncRule in $Config.azureDirectoryPolicy.standardSynchronizationRules) {
    $RuleName = "AAD - DEFAULT - " + $SyncRule."name"
    $RuleName = $RuleName.Replace("\", "").Replace("/", "").Replace("*", "").Replace(":", "").Replace("?", "").Replace("<", "").Replace(">", "").Replace("|", "")
    $SyncRule | ConvertTo-Json -Depth 64 | Out-File (Join-Path -Path $OutputFolder -ChildPath ($RuleName + ".json"))
}

#Clear the rules from the Config
for($i = 0; $i -lt $Config.onpremisesDirectoryPolicy.count; $i++) {
    $Config["onpremisesDirectoryPolicy"][$i]["customSynchronizationRules"] = $null
    $Config["onpremisesDirectoryPolicy"][$i]["standardSynchronizationRules"] = $null
}
$Config["azureDirectoryPolicy"]["customSynchronizationRules"] = $null
$Config["azureDirectoryPolicy"]["standardSynchronizationRules"] = $null

#Output final JSON
$Config | ConvertTo-Json -Depth 64 | Out-File (Join-Path -Path $OutputFolder -ChildPath ("_config.json"))

