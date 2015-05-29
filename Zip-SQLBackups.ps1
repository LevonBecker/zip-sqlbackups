#requires –version 2.0

#region Info

<#
.SYNOPSIS
        Compress SQL flat file backups in a given path.
.DESCRIPTION
        This Powershell script will zip up all the files in a directory based on a given file extension.
.NOTES
        AUTHOR:  Levon Becker
        TITLE:   Zip-SQLBackups
        VERSION: 1.0.6
        ENV:     Powershell v2
        REQUIREMENTS:
        1)      7-Zip v9.20 or higher installed
        2)      PowerShell Set-ExecutionPolicy to RemoteSigned or Unrestricted
        CHANGE LOG:
        01/05/2012:  Created
.EXAMPLE
        .\Zip-SQLBackups.ps1
        Defaults are .bak files in this path C:\Program Files\Microsoft SQL Server\MSSQL.1\MSSQL\Backup
.EXAMPLE
        .\Zip-SQLBackups.ps1 -filepath "D:\SQL Backups" -fileextension ".trn" -7zip "C:\Program Files (x86)\7-zip\7z.exe"
        Different path, file extension and 7-zip executable location set.
.PARAMETER filepath
        Full path to SQL Backup files.
.PARAMETER fileextension
        File extension to search for and select for compression.
.PARAMETER 7zip
        Full path including executable for 7-zip CLI application.
.PARAMETER scriptlog
        Full path and filename for script log.
.LINK
        http://www.bonusbits.com/wiki/HowTo:Use_PowerShell_Script_to_Zip_SQL_Backups
        http://www.bonusbits.com/wiki/How_to_Zip_SQL_Backup_Files_with_Scheduled_Task_and_PowerShell_Script
#>

#endregion Info

#region Parameters

        [CmdletBinding()]
        Param (
                [parameter(Mandatory=$false)][string]$filepath = 'C:\Program Files\Microsoft SQL Server\MSSQL.1\MSSQL\Backup',
                [parameter(Mandatory=$false)][string]$fileextension = '.bak',
                [parameter(Mandatory=$false)][string]$7zip = 'C:\Program Files\7-Zip\7z.exe',
                [parameter(Mandatory=$false)][string]$scriptlog = (Join-Path -Path $filepath -ChildPath 'Zip-SQLBackups.log')
        )

#endregion Parameters

#region Variables

        # SCRIPT
        [datetime]$starttime = Get-Date
        [string]$scriptver = '1.006'
        $files = $null

        # LOCALHOST
        [string]$systemname = Get-Content Env:\COMPUTERNAME
        [string]$userdomain = Get-Content Env:\USERDOMAIN
        [string]$username = Get-Content Env:\USERNAME

#endregion Variables

#region Functions

        Function Calc-Runtime {
                Param (
                        $starttime
                )

                # Clear old psobject if present
                If ($global:calcruntime) {
                        Remove-Variable calcruntime -Scope Global
                }

                $success = $false
                $notes = $null
                $endtime = $null
                $endtimef = $null
                $timespan = $null
                $mins = $null
                $hrs = $null
                $sec = $null
                $runtime = $null

                $endtime = Get-Date
                $endtimef = Get-Date -Format g
                $timespan = New-TimeSpan -Start $starttime -End $endtime
                $mins = ($timespan).Minutes
                $hrs = ($timespan).Hours
                $sec = ($timespan).Seconds
                $runtime = [String]::Format("{0:00}:{1:00}:{2:00}", $hrs, $mins, $sec)

                If ($runtime) {
                        $success = $true
                        $notes = 'Completed'
                }

                # Create Results PSObject
                $global:calcruntime = New-Object -TypeName PSObject -Property @{
                        Startime = $starttime
                        Endtime = $endtime
                        Endtimef = $endtimef
                        Runtime = $runtime
                        Success = $success
                        Notes = $notes
                }
        }

#endregion Functions

#region Log Header

        $datetime = Get-Date -format g
        Add-Content -Path $scriptlog -Encoding ASCII -Value ''
        Add-Content -Path $scriptlog -Encoding ASCII -Value '##############################################################################################################'
        Add-Content -Path $scriptlog -Encoding ASCII -Value "JOB STARTED:     $datetime"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "SCRIPT VER:      $scriptver"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "ADMINUSER:       $userdomain\$username"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "LOCALHOST:       $systemname"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "FILEPATH:        $filepath"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "FILE EXT:        $fileextension"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "7ZIPPATH:        $7zip"

#endregion Log Header

#region Tasks

        # GET BACKUP FILE LIST
        [array]$files = Get-Childitem -Path $filepath -recurse | Where-Object {$_.extension -match $fileextension}
        Add-Content -Path $scriptlog -Encoding ASCII -Value ''
        Add-Content -Path $scriptlog -Encoding ASCII -Value 'FILES SELECTED:'
        Add-Content -Path $scriptlog -Encoding ASCII -Value '---------------'
        $files | Select -ExpandProperty fullname | Add-Content -Path $scriptlog -Encoding ASCII

        # IF FILE LIST NOT EMPTY CONTINUE PROCESS
        If ($files) {
                Foreach ($file in $files) {
                        [datetime]$substarttime = Get-Date
                        # SET ZIP FILE NAME
                        $zipfile = $null
                        $zipfullname = $null
                        $zipfile = ($file -replace 'bak','zip')
                        $zipfullname = ($file.fullname -replace 'bak','zip')

                        # IF ZIP FILE NAME SET CONTINUE
                        If ($zipfullname) {
                                # UPDATE LOG
                                $datetime = Get-Date -format g
                                Add-Content -Path $scriptlog -Encoding ASCII -Value ''
                                Add-Content -Path $scriptlog -Encoding ASCII -Value "START:           $datetime"

                                # REMOVE EXISTING ZIP WITH SAME NAME IF PRESENT (Maybe it didn't finish and would rather start fresh)
                                If ((Test-Path -Path $zipfullname) -eq $true) {
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "DELETING:        $zipfile"
                                        Remove-Item -Path $zipfullname -Force
                                }

                                # COMPRESS FILE
                                Add-Content -Path $scriptlog -Encoding ASCII -Value "COMPRESSING:     $file to $zipfile"
                                . $7zip a -tzip $zipfullname $file.fullname

                                # SET TIMESTAMP TO MATCH ORIGINAL FILE (So SQL Maintenance Plan can remove based on date)
                                $creationtime = $null
                                $creationtimeutc = $null
                                $lastwritetime = $null
                                $lastwritetimeutc = $null
                                $creationtime = $file.CreationTime
                                $creationtimeutc = $file.CreationTimeUtc
                                $lastwritetime = $file.LastWriteTime
                                $lastwritetimeutc = $file.LastWriteTimeUtc
                                # IF GET ORIGINAL FILE TIMESTAMP THE SET ON ZIP FILE ELSE SKIP
                                If ($creationtime -and $creationtimeutc -and $lastwritetime -and $lastwritetimeutc) {
                                        Set-ItemProperty -Path $zipfullname -Name CreationTime -Value $creationtime
                                        Set-ItemProperty -Path $zipfullname -Name CreationTimeUtc -Value $creationtimeutc
                                        Set-ItemProperty -Path $zipfullname -Name LastWriteTime -Value $lastwritetime
                                        Set-ItemProperty -Path $zipfullname -Name LastWriteTimeUtc -Value $lastwritetimeutc
                                }
#                               LastAccessTime
#                               LastAccessTimeUtc

                                # CALCULATE RUNTIME FOR SUBTASK
                                Calc-Runtime -starttime $substarttime
                                $runtime = $global:calcruntime.Runtime

                                # CHECK SUCCESS
                                If ((Test-Path -Path $zipfullname) -eq $true) {
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "DELETING:        $file"
                                        # DELETE BAK FILE IF ZIP FILE EXISTS
                                        Remove-Item -Path $file.fullname -Force

                                        # UPDATE LOG
                                        $datetime = Get-Date -format g
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "END:             $datetime"
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value 'SUCCESS:         YES'
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "RUNTIME:         $runtime"
                                }
                                Else {
                                        # UPDATE LOG
                                        $datetime = Get-Date -format g
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "END:             $datetime"
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value 'SUCCESS:         NO'
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value "RUNTIME:         $runtime"
                                }
                        } # IF ZIP FILE NAME SET
                        Else {
                                        # UPDATE LOG
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value ''
                                        Add-Content -Path $scriptlog -Encoding ASCII -Value 'ERROR:           Zip File Name Blank'
                        }
                }
        } # If not empty
        Else {
                Add-Content -Path $scriptlog -Encoding ASCII -Value ''
                Add-Content -Path $scriptlog -Encoding ASCII -Value 'ERROR:           NO FILES FOUND'
        }

#endregion Tasks

#region Log Footer

        # CALCULATE TOTAL RUNTIME
        Calc-Runtime -starttime $starttime
        $runtime = $global:calcruntime.Runtime

        # WRITE LOG FOOTER
        $datetime = Get-Date -format g
        Add-Content -Path $scriptlog -Encoding ASCII -Value ''
        Add-Content -Path $scriptlog -Encoding ASCII -Value "JOB ENDED:       $datetime"
        Add-Content -Path $scriptlog -Encoding ASCII -Value "RUNTIME:         $runtime"
        Add-Content -Path $scriptlog -Encoding ASCII -Value '-----------------------------------------------------------------------------------------------------------------'
        Add-Content -Path $scriptlog -Encoding ASCII -Value ''

#endregion Log Footer