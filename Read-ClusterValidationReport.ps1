﻿Function Read-ClusterValidationReport {
<#
    .SYNOPSIS
        Return the status of a cluster validation report

    .DESCRIPTION
        Return any warnings or errors showed within a cluster validation report.
        These reports are generated by using the Test-Cluster command.

    .PARAMETER Report
        The path to the .htm validation report or the FileInfo object of the report, as returned by the Test-Cluster command

    .PARAMETER IgnoreWarnings
        Include any warnings in the output

    .PARAMETER IgnoreCancelled
        Include any cancelled tests in the output

    .EXAMPLE
        Read-ClusterValidationReport -Report 'C:\Windows\Cluster\Reports\Validation Report 2019.01.01 At 12.00.00.htm'

    .EXAMPLE
        Test-Cluster | Read-ClusterValidationReport -IgnoreWarnings -IgnoreCancelled -Verbose

    .NOTES
        For additional information please see my GitHub page

    .LINK
        https://github.com/My-Random-Thoughts/
#>

    [CmdletBinding()]
    [OutputType([object])]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({
            If ($_ -is [string])             { Test-Path -Path $_          }
            If ($_ -is [System.Io.FileInfo]) { Test-Path -Path $_.FullName }
        })]
        [object]$Report,

        [switch]$IgnoreWarnings,

        [switch]$IgnoreCancelled
    )

    Begin {
        [string]  $htmlRegex  = '<\/?\w+((\s+\w+(\s*=\s*(?:".*?"|[^">\s]+))?)+\s*|\s*)\/?>'    # Regex to detect all HTML tags with double quotes
        [string]  $incWarnCan = 'Failed'
        If (-not $IgnoreWarnings.IsPresent ) { $incWarnCan += '|Warning' }
        If (-not $IgnoreCancelled.IsPresent) { $incWarnCan += '|Cancel'  }
    }

    Process {
        [System.Collections.ArrayList]$returnData = @()
        [boolean]$h2Sect = $false
        [string] $item   = $null
        [string] $desc   = $null
        [string] $check  = $null
        [string] $prev   = $null
        [string] $status = $null

        If ($Report -is [System.IO.FileInfo]) { $path = $Report.FullName }
        If ($Report -is [string])             { $path = $Report }

        # Split and rejoin file
        [string[]]$fileContent = (((Get-Content -Path $Path -Raw).Replace('<br>','^').Replace([char]13,'^').Replace('^^','^')).Split('^'))

        ForEach ($line In $fileContent) {
            If ($line -match '</h2>')       { $h2Sect = $true; $check = ''; $desc = 'None'; $item = ($line -replace $htmlRegex, '') }
            If ($line -match 'Back to top') { $h2Sect = $false }
            If (-not $h2Sect) { Continue }

            If ($line -match '<div><b>Description:</b>') { $desc = (($line -replace $htmlRegex, '').Replace('Description:','').Trim()) }
            If ($line -match '(<div class="info">)(Validating|Verifying|Analyzing|(Testing(?! has completed)))') { $check = (($line -replace $htmlRegex, '').Trim()) }

            [boolean]$merge  = $false    # Merge consecutive warnings/errors/cancelled
            [boolean]$fMerge = $false    # Force merge non-html lines with previous ones
            If (-not $line.Trim().StartsWith('<')) { $fMerge = $true }
            If (($line -notmatch '(<div class=")(warn|error|cancel)(">)') -and ($prev -notmatch 'An error occurred while executing the test')) { Continue }

            # Line merging rules
            If ($line -match '<div class="warn">'  ) { $status = 'Warning';   If ($prev -match '<div class="warn">'  ) { $merge = $true } }
            If ($line -match '<div class="error">' ) { $status = 'Failed';    If ($prev -match '<div class="error">' ) { $merge = $true } }
            If ($line -match '<div class="cancel">') { $status = 'Cancelled'; If ($prev -match '<div class="cancel">') { $merge = $true } }

            If (($fMerge -eq $true) -or (($merge -eq $true) -and (($prev -match '>The following') -or ($line -match 'Exception from HRESULT')))) {
                $returnData[-1].Result += " $(($line -replace $htmlRegex, '').Trim())"
            }    #                         ^ note the space at the front
            Else {
                If (($IgnoreWarnings.IsPresent ) -and ($status -eq 'Warning'  )) { Continue }
                If (($IgnoreCancelled.IsPresent) -and ($status -eq 'Cancelled')) { Continue }

                If ([string]::IsNullOrEmpty($check)) { $check = $desc }
                [void]($returnData.Add([pscustomobject][ordered]@{
                    Status =  ($status.Trim())
                    Item   =  ($item.Trim())
                    Check  =  ($check.Trim())
                    Result = (($line -replace $htmlRegex, '').Trim())
                }))
            }

            If ($prev -notmatch '>The following') { $prev = $line }
        }

        Return $returnData
    }

    End {
    }
}