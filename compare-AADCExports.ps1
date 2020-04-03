<#

.SYNOPSIS
Analyse a set of AADConnect exports to ensure they are consistent with each other.

.DESCRIPTION
Using an AADConnect Pending Export CSV file from two different time periods from both
the active and staging servers, compare those exports to help highlight any data or config
differences between the active and staging servers.  A second set of exports taken
a few hours apart is needed to remove any normal but transient exports that just
hadn't been processed yet.  This removes as much noise as possible from the final report.

.PARAMETER Active1InputFilePath
Path to the Active side first export

.PARAMETER Active2InputFilePath
Path to the Active side second export

.PARAMETER Active1InputFilePath
Path to the Staging side first export

.PARAMETER Staging2InputFilePath
Path to the Staging side second export

.INPUTS
You cannot pipe input into this script

.OUTPUTS
This script puts the unique exports onto the pipeline

.EXAMPLE
.\compare-AADCExports.ps1
 -Active1InputFilePath "C:\temp\primary1.csv"
 -Active2InputFilePath "C:\temp\primary2.csv"
 -Staging1InputFilePath "C:\temp\staging1.csv"
 -Staging2InputFilePath "C:\temp\staging2.csv" | Out-File c:\temp\compare.csv

.NOTES
To create the CSV files used as input to this script, we need to run CSExport.exe against the the Connector being reviewed.
Typical command line will be similar to:
"C:\Program Files\Microsoft Azure AD Sync\Bin\csexport.exe" "MAName" ExportFileName.xml /f:x

After creating the XML of the pending exports, convert it into CSV with a command line similar to:
"C:\Program Files\Microsoft Azure AD Sync\Bin\CSExportAnalyzer.exe" ExportFileName.xml > %temp%\export.csv


#>

[CmdletBinding()]
Param(
      [Parameter(Mandatory=$True)]  [string]$Active1InputFilePath
    , [Parameter(Mandatory=$True)]  [string]$Active2InputFilePath
    , [Parameter(Mandatory=$True)]  [string]$Staging1InputFilePath
    , [Parameter(Mandatory=$True)]  [string]$Staging2InputFilePath
)

If (!(Test-Path -PathType Leaf -Path $Active1InputFilePath)) {
    Write-Error "Did not find Input file $Active1InputFilePath"
    exit 1
}
If (!(Test-Path -PathType Leaf -Path $Active2InputFilePath)) {
    Write-Error "Did not find Input file $Active2InputFilePath"
    exit 1
}
If (!(Test-Path -PathType Leaf -Path $Staging1InputFilePath)) {
    Write-Error "Did not find Input file $Staging1InputFilePath"
    exit 1
}
If (!(Test-Path -PathType Leaf -Path $Staging2InputFilePath)) {
    Write-Error "Did not find Input file $Staging2InputFilePath"
    exit 1
}

$Active1InputFile = Get-Item $Active1InputFilePath
$Active2InputFile = Get-Item $Active2InputFilePath
$Staging1InputFile = Get-Item $Staging1InputFilePath
$Staging2InputFile = Get-Item $Staging2InputFilePath

#Build array with common entries for Active

$ActiveExports = [System.Collections.ArrayList]@()
$Content1 = Get-Content $Active1InputFile
$Content2 = Get-Content $Active2InputFile


ForEach ($Entry in $Content2) {
    If ($Content1.Contains($Entry)) {
        $ActiveExports.Add($Entry) | Out-Null
    }
}

#Build array with common entries for Staging

$StagingExports = [System.Collections.ArrayList]@()
$Content1 = Get-Content $Staging1InputFile
$Content2 = Get-Content $Staging2InputFile


ForEach ($Entry in $Content2) {
    If ($Content1.Contains($Entry)) {
        $StagingExports.Add($Entry) | Out-Null
    }
}

#Build array of differences
$MissingExports = [System.Collections.ArrayList]@()
ForEach ($Entry in $ActiveExports) {
    If (!($StagingExports.Contains($Entry))) {
        $BadRecord = "ActiveOnlyExport," + $Entry
        $MissingExports.Add($BadRecord) | Out-Null
    }
}
ForEach ($Entry in $StagingExports) {
    If (!($ActiveExports.Contains($Entry))) {
        $BadRecord = "StagingOnlyExport," + $Entry
        $MissingExports.Add($BadRecord) | Out-Null
    }
}

$MissingExports | Sort-Object

