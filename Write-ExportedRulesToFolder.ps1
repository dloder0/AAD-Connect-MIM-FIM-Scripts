<#

.SYNOPSIS
Write AADConnect rules into individual files

.DESCRIPTION
Using an AADConnect Rule Export file, writes each rule into a separate file
to make it easier for version or environment comparisons.
All files are created in a subfolder based on the name of the input file

Optionally, include the path to a folder containing the Connector XML export files
and the name will include the source connector name.
This is very useful for multi-forest scenarios where the base rule name
is duplicated across multiple forests.

.PARAMETER InputFilePath
Path to the input AADConnect Rule Export file

.PARAMETER XMLFolderPath
Path to the folder containing the Connector XML export files

.INPUTS
You cannot pipe input into this script

.OUTPUTS
This script does not pipeline any output objects

.EXAMPLE
.\Write-ExportedRulesToFolder.ps1 -InputFilePath C:\temp\InboundRules.txt
This will read all the rules in the InboundRules.txt file and write them
to individual files in the InboundRules folder.  Each file name is based
on the rule's name.

.EXAMPLE
.\Write-ExportedRulesToFolder.ps1 -InputFilePath C:\temp\InboundRules.txt -XMLFolderPath C:\temp\connectors
This will read all the rules in the InboundRules.txt file and write them
to individual files in the InboundRules folder.  Each file name is based
on the rule's name and the name of the connector.

.NOTES
To create the input file, open the Synchronization Rules Editor on the AADConnect server,
select all of the inbound rules and click Export.  Repeat for the outbound rules.

To create the Connector XML export files open the Synchronization Service GUI on the AADConnect server,
navigate to the Connectors tab, highlight a connector and select Export Connector from the Actions menu.
Provide a File name and click Save.
Repeat for each connector.

#>

[CmdletBinding()]
Param(
      [Parameter(Mandatory=$True)]  [string]$InputFilePath
    , [Parameter(Mandatory=$false)] [string]$XMLFolderPath=""
)

If (!(Test-Path -PathType Leaf -Path $InputFilePath)) {
    Write-Error "Did not find Input file $InputFilePath"
    exit 1
}

$ConnectorGUID_Name = @{}

If ($XMLFolderPath -ne "") {
    If (!(Test-Path -PathType Container -Path $XMLFolderPath)) {
        Write-Error "Did not find XML folder $XMLFolderPath"
        exit 1
    }

    #Parse the XML files to get the GUID to Name mappings
    $XMLFiles = Get-ChildItem -Path "$XMLFolderPath\*" -Include *.xml
    ForEach ($XMLFile in $XMLFiles) {
        [xml]$XMLContent = Get-Content $XMLFile.FullName
        If ($XMLContent."saved-ma-configuration"."ma-data"."id" -ne $null) {
            $ConnectorGUID_Name[$XMLContent."saved-ma-configuration"."ma-data"."id"] = $XMLContent."saved-ma-configuration"."ma-data"."name"
            Write-Verbose ("Mapped " + $XMLContent."saved-ma-configuration"."ma-data"."id" + " to " + $XMLContent."saved-ma-configuration"."ma-data"."name")
        }
        If ($XMLContent."ma-data"."id" -ne $null) {
            $ConnectorGUID_Name[$XMLContent."ma-data"."id"] = $XMLContent."ma-data"."name"
            Write-Verbose ("Mapped " + $XMLContent."ma-data"."id" + " to " + $XMLContent."ma-data"."name")
        }
    }
}

If ($ConnectorGUID_Name.count -gt 0) {
    $ConnectorName = $true
} else {
    $ConnectorName = $false
}


$InputFile = Get-Item $InputFilePath

$Content = Get-Content $InputFile

#Create the Rules object that has the LineNumber for each Sync Rule
$Rules = $Content | Select-String -Pattern 'New-ADSyncRule ' | Select-Object Line, LineNumber

#For each sync rule, determine the starting line number, end line number and the rule's name
For ($RuleNumber = 0; $RuleNumber -lt $Rules.count; $RuleNumber++) {
	$Rule = $Rules[$RuleNumber]
	$Rule | Add-Member -type NoteProperty -name FirstLine -value ($Rule.LineNumber-1)
	If ($RuleNumber -eq $Rules.count-1) {
		$Rule | Add-Member -type NoteProperty -name LastLine -value ($Content.count-1)
	} else {
		$Rule | Add-Member -type NoteProperty -name LastLine -value (($Rules[$RuleNumber+1].LineNumber)-2)
	}
    For ($LineNumber = $Rule.FirstLine; $LineNumber -lt $rule.LastLine; $LineNumber++) {
        If ($Content[$LineNumber].StartsWith("-Name '")) {
            $Rule | Add-Member -type NoteProperty -name RuleName -value ($Content[$LineNumber].Substring(6))
        }
        If ($Content[$LineNumber].StartsWith("-Connector '")) {
            $Rule | Add-Member -type NoteProperty -name Id -value ($Content[$LineNumber].Substring(11))
        }
    }
}

#Ensure the Output folder has been created and is empty
$OutputFolder = Join-Path $InputFile.DirectoryName -ChildPath $InputFile.BaseName

If (Test-Path $OutputFolder ) {
	Remove-Item $OutputFolder\* -recurse
} else {
	New-Item -Path $OutputFolder -type directory | Out-Null
}


#Write each rule to a separate file
$Error.Clear()
ForEach ($Rule in $Rules) {
	if ($Rule.RuleName -match "'(.+?)'") {
		$RuleName = $matches[1]
	}
	if ($Rule.Id -match "'(.+?)'") {
		$Id = "{" + $matches[1] + "}"
	}
	$RuleName = $RuleName.Replace("\", "").Replace("/", "").Replace("*", "").Replace(":", "").Replace("?", "").Replace("<", "").Replace(">", "").Replace("|", "")
    If ($ConnectorName) {
        If ($ConnectorGUID_Name.ContainsKey($Id)) {
            $RuleName = $ConnectorGUID_Name[$Id] + " - " + $RuleName
        }
    }
	$OutputFile = Join-Path $OutputFolder -ChildPath ($RuleName + ".txt")
	$Content[($Rule.FirstLine)..($Rule.LastLine)] | Out-File -FilePath $OutputFile -Encoding default -NoClobber
}

If ($Error.Count -gt 0) {
    Write-Output "Errors encountered during output file creation."
    Write-Output "If this ruleset is for a multi-connector environment with overlapping rule names,"
    Write-Output "use the XMLFolderPath option to include the connector name, making the output filename unique."
}


