# 26

Describe "Last Backup Restore Test" -Tags TestLastBackup, Backup, $filename {
    if (-not (Get-DbcConfigValue skip.backup.testing)) {
        $destserver = Get-DbcConfigValue policy.backup.testserver
        $destdata = Get-DbcConfigValue policy.backup.datadir
        $destlog = Get-DbcConfigValue policy.backup.logdir
        if ($NotContactable -contains $psitem) {
            Context "Testing Backup Restore & Integrity Checks on $psitem" {
                It "Can't Connect to $Psitem" {
                    $true | Should -BeFalse -Because "The instance should be available to be connected to!"
                }
            }
        } else {
            if (-not $destserver) {
                $destserver = $psitem
            }
            Context "Testing Backup Restore & Integrity Checks on $psitem" {
                $srv = Connect-DbaInstance -SqlInstance $psitem
                $dbs = ($srv.Databases.Where{ $_.CreateDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours( - $graceperiod) -and $(if ($Database) { $_.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }).Name
                if (-not ($destdata)) { $destdata -eq $srv.DefaultFile }
                if (-not ($destlog)) { $destlog -eq $srv.DefaultLog }
                @(Test-DbaLastBackup -SqlInstance $psitem -Database $dbs -Destination $destserver -DataDirectory $destdata -LogDirectory $destlog -VerifyOnly).ForEach{ if ($psitem.DBCCResult -notmatch "skipped for restored master") {
                        It "Database $($psitem.Database) DBCC CheckDB should be success on $($psitem.SourceServer)" {
                            $psitem.DBCCResult | Should -Be "Success" -Because "You need to run DBCC CHECKDB to ensure your database is consistent"
                        }
                        It "Database $($psitem.Database) restore should be success on $($psitem.SourceServer)" {
                            $psitem.RestoreResult | Should -Be "Success" -Because "The backup file has not successfully restored - you have no backup"
                        }
                    }
                }
            }
        }
    }
}

Describe "Last Backup VerifyOnly" -Tags TestLastBackupVerifyOnly, Backup, $filename {
    $graceperiod = Get-DbcConfigValue policy.backup.newdbgraceperiod
    if ($NotContactable -contains $psitem) {
        Context "VerifyOnly tests of last backups on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "VerifyOnly tests of last backups on $psitem" {
            $DatabasesToCheck = ($InstanceSMO.Databases.Where{ $_.IsAccessible -eq $true }.Where{ $_.CreateDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours( - $graceperiod) -and $(if ($Database) { $_.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }).Name
            $BackUpVerify = $DatabasesToCheck.Foreach{
                $BackupVerifySplat = @{
                    SqlInstance     = $InstanceSMO
                    Database        = $psitem
                    VerifyOnly      = $true
                    EnableException = $true
                }
                try {
                    Test-DbaLastBackup @BackupVerifySplat
                } catch {
                    [pscustomobject]@{
                        $psitem.RestoreResult = $_.Exception.Message
                        $psitem.FileExists    = $_.Exception.Message
                    }
                }
            }
            $BackUpVerify.ForEach{
                It "Database $($psitem.Database) restore for Database should be success for $($psitem.SourceServer)" {
                    $psitem.RestoreResult | Should -Be "Success" -Because "The restore file has not successfully verified - you have no backup"
                }
                It "Database $($psitem.Database) last backup file exists for $($psitem.SourceServer)" {
                    $psitem.FileExists | Should -BeTrue -Because "Without a backup file you have no backup"
                }
            }
        }
    }
}

Describe "Last Good DBCC CHECKDB" -Tags LastGoodCheckDb, Varied, $filename {
    $maxdays = Get-DbcConfigValue policy.dbcc.maxdays
    $datapurity = Get-DbcConfigValue skip.dbcc.datapuritycheck
    $graceperiod = Get-DbcConfigValue policy.backup.newdbgraceperiod
    if ($NotContactable -contains $psitem) {
        Context "Testing Last Good DBCC CHECKDB on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Last Good DBCC CHECKDB on $psitem" {
            @(Get-DbaLastGoodCheckDb -SqlInstance $psitem -Database ($InstanceSMO.Databases.Where{ $_.CreateDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours( - $graceperiod) -and ($_.IsAccessible -eq $true) -and $(if ($database) { $psitem.name -in $Database }else { $ExcludedDatabases -notcontains $_.Name }) }).Name ).ForEach{
                if ($psitem.Database -ne "tempdb") {
                    It "Database $($psitem.Database) last good integrity check should be less than $maxdays days old on $($psitem.SqlInstance)" {
                        if ($psitem.LastGoodCheckDb) {
                            $psitem.LastGoodCheckDb | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddDays( - ($maxdays)) -Because "You should have run a DBCC CheckDB inside that time"
                        } else {
                            $psitem.LastGoodCheckDb | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddDays( - ($maxdays)) -Because "You should have run a DBCC CheckDB inside that time"
                        }
                    }
                    It -Skip:$datapurity "Database $($psitem.Database) has Data Purity Enabled on $($psitem.SqlInstance)" {
                        $psitem.DataPurityEnabled | Should -BeTrue -Because "the DATA_PURITY option causes the CHECKDB command to look for column values that are invalid or out of range."
                    }
                }
            }
        }
    }
}

Describe "Column Identity Usage" -Tags IdentityUsage, Medium, $filename {
    $maxpercentage = Get-DbcConfigValue policy.identity.usagepercent
    if ($NotContactable -contains $psitem) {
        Context "Testing Column Identity Usage on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Column Identity Usage on $psitem" {
            if ($version -lt 10) {
                It "Database dbachecksskipped Testing Column Identity Usage on $Instance" -Skip {
                    Assert-DatabaseDuplicateIndex -Instance $instance -Database $psitem
                }
            } else {
                $exclude = $ExcludedDatabases
                $exclude += $InstanceSMO.Databases.Where{ $_.IsAccessible -eq $false }.Name
                @(Test-DbaIdentityUsage -SqlInstance $psitem -Database $Database -ExcludeDatabase $exclude).ForEach{
                    if ($psitem.Database -ne "tempdb") {
                        $columnfqdn = "$($psitem.Database).$($psitem.Schema).$($psitem.Table).$($psitem.Column)"
                        It "Database $($psitem.Database) - The usage for $columnfqdn should be less than $maxpercentage percent on $($psitem.SqlInstance)" {
                            $psitem.PercentUsed -lt $maxpercentage | Should -BeTrue -Because "You do not want your Identity columns to hit the max value and stop inserts"
                        }
                    }
                }
            }
        }
    }
}

Describe "Duplicate Index" -Tags DuplicateIndex, $filename {
    $Excludeddbs = Get-DbcConfigValue policy.database.duplicateindexexcludedb
    $Excludeddbs += $ExcludedDatabases
    if ($NotContactable -contains $psitem) {
        Context "Testing duplicate indexes on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing duplicate indexes on $psitem" {
            if ($version -lt 10) {
                It "Database dbachecksskipped should return 0 duplicate indexes on $Instance" -Skip {
                    Assert-DatabaseDuplicateIndex -Instance $instance -Database $psitem
                }
            } else {
                $instance = $Psitem
                @(Get-Database -Instance $instance -Requiredinfo Name -Exclusions NotAccessible -Database $Database -ExcludedDbs $Excludeddbs).ForEach{
                    It "Database $psitem should return 0 duplicate indexes on $Instance" {
                        Assert-DatabaseDuplicateIndex -Instance $instance -Database $psitem
                    }
                }
            }
        }
    }
}

Describe "Unused Index" -Tags UnusedIndex, Medium, $filename {
    if ($NotContactable -contains $psitem) {
        Context "Testing Unused indexes on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Unused indexes on $psitem" {
            try {
                $Instance = $Psitem
                    (Get-Database -Instance $Instance -RequiredInfo Name -Exclusions NotAccessible -Database $Database -ExcludedDbs $Excludeddbs).ForEach{
                    $results = Find-DbaDbUnusedIndex -SqlInstance $psitem -Database $Database -ExcludeDatabase $ExcludedDatabases -EnableException
                    It "Database $psitem should return 0 Unused indexes on $($psitem.SQLInstance)" {
                        @($results).Count | Should -Be 0 -Because "You should have indexes that are used"
                    }
                }
            } catch {
                It -Skip "Database $psitem should return 0 Unused indexes on $($psitem.SQLInstance)" {
                    @($results).Count | Should -Be 0 -Because "You should have indexes that are used"
                }
            }
        }
    }
}

Describe "Disabled Index" -Tags DisabledIndex, Medium, $filename {
    if ($NotContactable -contains $psitem) {
        Context "Testing Disabled indexes on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Disabled indexes on $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) -and ($_.IsAccessible -eq $true) }.ForEach{
                $results = Find-DbaDbDisabledIndex -SqlInstance $psitem.Parent -Database $psitem.Name
                It "Database $($psitem.Name) should return 0 Disabled indexes on $($psitem.Parent.Name)" {
                    @($results).Count | Should -Be 0 -Because "Disabled indexes are wasting disk space"
                }
            }
        }
    }
}

Describe "Database Growth Event" -Tags DatabaseGrowthEvent, Low, $filename {
    $exclude = Get-DbcConfigValue policy.database.filegrowthexcludedb
    $daystocheck = Get-DbcConfigValue policy.database.filegrowthdaystocheck
    if ($null -eq $daystocheck) {
        $datetocheckfrom = '0001-01-01'
    } else {
        $datetocheckfrom = (Get-Date).ToUniversalTime().AddDays( - $daystocheck)
    }
    if ($NotContactable -contains $psitem) {
        Context "Testing database growth event on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing database growth event on $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $PSItem.Name -notin $exclude -and ($ExcludedDatabases -notcontains $PsItem.Name) }) }.ForEach{
                $results = @(Find-DbaDbGrowthEvent -SqlInstance $psitem.Parent -Database $psitem.Name).Where{ $_.StartTime -gt $datetocheckfrom }
                It "Database $($psitem.Name) should return 0 database growth events on $($psitem.Parent.Name)" {
                    @($results).Count | Should -Be 0 -Because "You want to control how your database files are grown"
                }
            }
        }
    }
}

Describe "Page Verify" -Tags PageVerify, Medium, $filename {
    $pageverify = Get-DbcConfigValue policy.pageverify
    if ($NotContactable -contains $psitem) {
        Context "Testing page verify on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing page verify on $psitem" {
            switch ($version) {
                8 {
                    It "Database Page verify is not available on SQL 2000 on $psitem" {
                        $true | Should -BeTrue
                    }
                }
                9 {
                    $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }.ForEach{
                        if ($Psitem.Name -ne 'tempdb') {
                            It "Database $($psitem.Name) should have page verify set to $pageverify on $($psitem.Parent.Name)" {
                                $psitem.PageVerify | Should -Be $pageverify -Because "Page verify helps SQL Server to detect corruption"
                            }
                        } else {
                            It "Database Page verify is not available on tempdb on SQL 2005 on $($psitem.Parent.Name)" {
                                $true | Should -BeTrue
                            }
                        }
                    }
                }
                Default {
                    $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }.ForEach{
                        It "Database $($psitem.Name) should have page verify set to $pageverify on $($psitem.Parent.Name)" {
                            $psitem.PageVerify | Should -Be $pageverify -Because "Page verify helps SQL Server to detect corruption"
                        }
                    }
                }
            }
        }
    }
}

Describe "Last Full Backup Times" -Tags LastFullBackup, LastBackup, Backup, DISA, Varied, $filename {
    $maxfull = Get-DbcConfigValue policy.backup.fullmaxdays
    $graceperiod = Get-DbcConfigValue policy.backup.newdbgraceperiod
    $skipreadonly = Get-DbcConfigValue skip.backup.readonly
    $skipsecondaries = Get-DbcConfigValue skip.backup.secondaries
    if ($NotContactable -contains $psitem) {
        Context "Testing last full backups on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing last full backups on $psitem" {
            $InstanceSMO.Databases.Where{ ($psitem.Name -ne 'tempdb') -and $Psitem.CreateDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours( - $graceperiod) -and $(if ($Database) { $PsItem.Name -in $Database } else { $ExcludedDatabases -notcontains $PsItem.Name }) }.ForEach{
                if ($psitem.AvailabilityGroupName) {
                    $agReplicaRole = $InstanceSMO.AvailabilityGroups[$psitem.AvailabilityGroupName].LocalReplicaRole
                } else {
                    $agReplicaRole = $null
                }
                $skip = ($psitem.Status -match "Offline") -or ($psitem.IsAccessible -eq $false) -or ($psitem.Readonly -eq $true -and $skipreadonly -eq $true) -or ($agReplicaRole -eq 'Secondary' -and $skipsecondaries -eq $true)
                It -Skip:$skip "Database $($psitem.Name) should have full backups less than $maxfull days old on $($psitem.Parent.Name)" {
                    $psitem.LastBackupDate.ToUniversalTime() | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddDays( - ($maxfull)) -Because "Taking regular backups is extraordinarily important"
                }
            }
        }
    }
}

Describe "Last Diff Backup Times" -Tags LastDiffBackup, LastBackup, Backup, DISA, Varied, $filename {
    if (-not (Get-DbcConfigValue skip.diffbackuptest)) {
        $maxdiff = Get-DbcConfigValue policy.backup.diffmaxhours
        $graceperiod = Get-DbcConfigValue policy.backup.newdbgraceperiod
        $skipreadonly = Get-DbcConfigValue skip.backup.readonly
        $skipsecondaries = Get-DbcConfigValue skip.backup.secondaries

        if ($NotContactable -contains $psitem) {
            Context "Testing last diff backups on $psitem" {
                It "Can't Connect to $Psitem" {
                    $true | Should -BeFalse -Because "The instance should be available to be connected to!"
                }
            }
        } else {
            Context "Testing last diff backups on $psitem" {
                @($InstanceSMO.Databases.Where{ (-not $psitem.IsSystemObject) -and $Psitem.CreateDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours( - $graceperiod) -and $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }).ForEach{
                    if ($psitem.AvailabilityGroupName) {
                        $agReplicaRole = $InstanceSMO.AvailabilityGroups[$psitem.AvailabilityGroupName].LocalReplicaRole
                    } else {
                        $agReplicaRole = $null
                    }
                    $skip = ($psitem.Status -match "Offline") -or ($psitem.IsAccessible -eq $false) -or ($psitem.Readonly -eq $true -and $skipreadonly -eq $true) -or ($agReplicaRole -eq 'Secondary' -and $skipsecondaries -eq $true)
                    It -Skip:$skip "Database $($psitem.Name) diff backups should be less than $maxdiff hours old on $($psitem.Parent.Name)" {
                            ($psitem.LastBackupDate.ToUniversalTime(), $psitem.LastDifferentialBackupDate.ToUniversalTime() | Measure-Object -Max).Maximum | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddHours( - ($maxdiff)) -Because 'Taking regular backups is extraordinarily important'
                    }
                }
            }
        }
    }
}

Describe "Last Log Backup Times" -Tags LastLogBackup, LastBackup, Backup, DISA, Varied, $filename {
    $maxlog = Get-DbcConfigValue policy.backup.logmaxminutes
    $graceperiod = Get-DbcConfigValue policy.backup.newdbgraceperiod
    $skipreadonly = Get-DbcConfigValue skip.backup.readonly
    $skipsecondaries = Get-DbcConfigValue skip.backup.secondaries
    [DateTime]$sqlinstancedatetime = $InstanceSMO.Query("SELECT getutcdate() as getutcdate").getutcdate
    [DateTime]$oldestbackupdateallowed = $sqlinstancedatetime.AddHours( - $graceperiod)
    if ($NotContactable -contains $psitem) {
        Context "Testing last log backups on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing last log backups on $psitem" {
            @($InstanceSMO.Databases.Where{ (-not $psitem.IsSystemObject) -and $Psitem.CreateDate.ToUniversalTime() -lt $oldestbackupdateallowed -and $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) }).ForEach{
                if ($psitem.RecoveryModel -ne "Simple") {
                    if ($psitem.AvailabilityGroupName) {
                        $agReplicaRole = $InstanceSMO.AvailabilityGroups[$psitem.AvailabilityGroupName].LocalReplicaRole
                    } else {
                        $agReplicaRole = $null
                    }
                    $skip = ($psitem.Status -match "Offline") -or ($psitem.IsAccessible -eq $false) -or ($psitem.Readonly -eq $true -and $skipreadonly -eq $true) -or ($agReplicaRole -eq 'Secondary' -and $skipsecondaries -eq $true)
                    It -Skip:$skip "Database $($psitem.Name) log backups should be less than $maxlog minutes old on $($psitem.Parent.Name)" {
                        $psitem.LastLogBackupDate.ToUniversalTime() | Should -BeGreaterThan $sqlinstancedatetime.AddMinutes( - ($maxlog) + 1) -Because "Taking regular backups is extraordinarily important"
                    }
                }
            }
        }
    }
}

Describe "Log File percent used" -Tags LogfilePercentUsed, Medium, $filename {
    $LogFilePercentage = Get-DbcConfigValue policy.database.logfilepercentused
    if ($NotContactable -contains $psitem) {
        Context "Testing Log File percent used for $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Log File percent used for $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) -and ($Psitem.IsAccessible -eq $true) }.ForEach{
                $LogFiles = Get-DbaDbSpace -SqlInstance $psitem.Parent.Name -Database $psitem.Name | Where-Object { $_.FileType -eq "LOG" }
                $DatabaseName = $psitem.Name
                $CurrentLogFilePercentage = ($LogFiles | Measure-Object -Property PercentUsed -Maximum).Maximum
                It "Database $DatabaseName Should have a percentage used lower than $LogFilePercentage% on $($psitem.Parent.Name)" {
                    $CurrentLogFilePercentage | Should -BeLessThan $LogFilePercentage -Because "Check backup strategy, open transactions, CDC, Replication and HADR solutions "
                }
            }
        }
    }
}

Describe "Log File Size Checks" -Tags LogfileSize, Medium, $filename {
    $LogFileSizePercentage = Get-DbcConfigValue policy.database.logfilesizepercentage
    $LogFileSizeComparison = Get-DbcConfigValue policy.database.logfilesizecomparison
    if ($NotContactable -contains $psitem) {
        Context "Testing Log File size for $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Log File size for $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name }) -and ($Psitem.IsAccessible -eq $true) }.ForEach{
                $Files = Get-DbaDbFile -SqlInstance $psitem.Parent.Name -Database $psitem.Name
                $DatabaseName = $psitem.Name
                $LogFiles = $Files | Where-Object { $_.TypeDescription -eq "LOG" }
                $Splat = @{$LogFileSizeComparison = $true
                    property                      = "size"
                }
                $LogFileSize = ($LogFiles | Measure-Object -Property Size -Maximum).Maximum
                $DataFileSize = ($Files | Where-Object { $_.TypeDescription -eq "ROWS" } | Measure-Object @Splat).$LogFileSizeComparison
                It "Database $DatabaseName Should have no log files larger than $LogFileSizePercentage% of the $LogFileSizeComparison of DataFiles on $($psitem.Parent.Name)" {
                    $LogFileSize | Should -BeLessThan ($DataFileSize * $LogFileSizePercentage) -Because "If your log file is this large you are not maintaining it well enough"
                }
            }
        }
    }
}

Describe "Future File Growth" -Tags FutureFileGrowth, Low, $filename {
    $threshold = Get-DbcConfigValue policy.database.filegrowthfreespacethreshold
    [string[]]$exclude = Get-DbcConfigValue policy.database.filegrowthexcludedb
    $exclude += $ExcludedDatabases
    if ($NotContactable -contains $psitem) {
        Context "Testing for files likely to grow soon on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing for files likely to grow soon on $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $PsItem.Name -notin $exclude }) -and ($psitem.IsAccessible) }.ForEach{
                $Files = Get-DbaDbFile -SqlInstance $psitem.Parent.Name -Database $psitem.Name
                $Files | Add-Member ScriptProperty -Name PercentFree -Value { 100 - [Math]::Round(([int64]$PSItem.UsedSpace.Byte / [int64]$PSItem.Size.Byte) * 100, 3) }
                $Files | ForEach-Object {
                    if (-Not (($PSItem.Growth -eq 0) -and (Get-DbcConfigValue skip.database.filegrowthdisabled))) {
                        It "Database $($PSItem.Database) file $($PSItem.LogicalName) has free space under threshold on $($PSItem.SqlInstance)" {
                            $PSItem.PercentFree | Should -BeGreaterOrEqual $threshold -Because "free space within the file should be lower than threshold of $threshold %"
                        }
                    }
                }
            }
        }
    }
}

Describe "Correctly sized Filegroup members" -Tags FileGroupBalanced, Medium, $filename {
    $Tolerance = Get-DbcConfigValue policy.database.filebalancetolerance
    if ($NotContactable -contains $psitem) {
        Context "Testing for balanced FileGroups on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing for balanced FileGroups on $psitem" {
            @(Connect-DbaInstance -SqlInstance $_).Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name -and ($Psitem.IsAccessible -eq $true) }) }.ForEach{
                $Files = Get-DbaDbFile -SqlInstance $psitem.Parent.Name -Database $psitem.Name
                $FileGroups = $Files | Where-Object { $_.TypeDescription -eq "ROWS" } | Group-Object -Property FileGroupName
                @($FileGroups).ForEach{
                    $Unbalanced = 0
                    $Average = ($psitem.Group.Size | Measure-Object -Average).Average
                    ## files where average size is less than 95% of the average or more than 105% of the average filegroup size (using default 5% config value)
                    $Unbalanced = $psitem | Where-Object { $psitem.group.Size -lt ((1 - ($Tolerance / 100)) * $Average) -or $psitem.group.Size -gt ((1 + ($Tolerance / 100)) * $Average) }
                    It "Database $($psitem.Group[0].Database) File Group $($psitem.Name) should have FileGroup members with sizes within $tolerance % of the average on $($psitem.Group[0].SqlInstance)" {
                        $Unbalanced.count | Should -Be 0 -Because "If your file groups are not balanced the files with the most free space will become allocation hotspots"
                    }
                }
            }
        }
    }
}

Describe "Certificate Expiration" -Tags CertificateExpiration, High, $filename {
    $CertificateWarning = Get-DbcConfigValue policy.certificateexpiration.warningwindow
    [string[]]$exclude = Get-DbcConfigValue policy.certificateexpiration.excludedb
    $exclude += $ExcludedDatabases
    if ($NotContactable -contains $psitem) {
        Context "Checking that encryption certificates have not expired on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Checking that encryption certificates have not expired on $psitem" {
            @(Get-DbaDbEncryption -SqlInstance $psitem -IncludeSystemDBs -Database $Database -ExcludeDatabase $exclude | Where-Object { $_.Encryption -eq "Certificate" -and ($_.Database -notin $exclude) }).ForEach{
                It "Database $($psitem.Database) certificate $($psitem.Name) has not expired on $($psitem.SqlInstance)" {
                    $psitem.ExpirationDate.ToUniversalTime() | Should -BeGreaterThan (Get-Date).ToUniversalTime() -Because "this certificate should not be expired"
                }
                if ($psitem.ExpirationDate.ToUniversalTime() -lt (Get-Date).ToUniversalTime()) {
                    $skip = $true
                } else {
                    $skip = $false
                }
                It "Database $($psitem.Database) certificate $($psitem.Name) does not expire for more than $CertificateWarning months on $($psitem.SqlInstance)" -Skip:$skip {
                    $psitem.ExpirationDate.ToUniversalTime() | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddMonths($CertificateWarning) -Because "expires inside the warning window of $CertificateWarning months"
                }
            }
        }
    }
}

Describe "Datafile Auto Growth Configuration" -Tags DatafileAutoGrowthType, Low, $filename {
    $datafilegrowthtype = Get-DbcConfigValue policy.database.filegrowthtype
    $datafilegrowthvalue = Get-DbcConfigValue policy.database.filegrowthvalue
    $exclude = Get-DbcConfigValue policy.database.filegrowthexcludedb
    $exclude += $ExcludedDatabases
    if ($NotContactable -contains $psitem) {
        Context "Testing datafile growth type on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing datafile growth type on $psitem" {
            $InstanceSMO.Databases.Where{ $(if ($Database) { $PsItem.Name -in $Database }else { $exclude -notcontains $PsItem.Name }) -and ($Psitem.IsAccessible -eq $true) }.ForEach{
                $Files = Get-DbaDbFile -SqlInstance $InstanceSMO -Database $psitem.Name
                @($Files).ForEach{
                    if (-Not (($psitem.Growth -eq 0) -and (Get-DbcConfigValue skip.database.filegrowthdisabled))) {
                        It "Database $($psitem.Database) datafile $($psitem.LogicalName) on filegroup $($psitem.FileGroupName) should have GrowthType set to $datafilegrowthtype on $($psitem.SqlInstance)" {
                            $psitem.GrowthType | Should -Be $datafilegrowthtype -Because "We expect a certain file growth type"
                        }
                        if ($datafilegrowthtype -eq "kb") {
                            It "Database $($psitem.Database) datafile $($psitem.LogicalName) on filegroup $($psitem.FileGroupName) should have Growth set equal or higher than $datafilegrowthvalue on $($psitem.SqlInstance)" {
                                $psitem.Growth * 8 | Should -BeGreaterOrEqual $datafilegrowthvalue -Because "We expect a certain file growth value"
                            }
                        } else {
                            It "Database $($psitem.Database) datafile $($psitem.LogicalName) on filegroup $($psitem.FileGroupName) should have Growth set equal or higher than $datafilegrowthvalue on $($psitem.SqlInstance)" {
                                $psitem.Growth | Should -BeGreaterOrEqual $datafilegrowthvalue -Because "We expect a certain fFile growth value"
                            }
                        }
                    }
                }
            }
        }
    }
}

Describe "Database Orphaned User" -Tags OrphanedUser, CIS, Medium, $filename {
    if ($NotContactable -contains $psitem) {
        Context "Testing database orphaned user event on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing database orphaned user event on $psitem" {
            $instance = $psitem
            @($InstanceSMO.Databases.Where{ ($(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name })) }).ForEach{
                It "Database $($psitem.Name) should return 0 orphaned user on $($psitem.Parent.Name)" {
                    @(Get-DbaDbOrphanUser -SqlInstance $instance -ExcludeDatabase $ExcludedDatabases -Database $psitem.Name).Count | Should -Be 0 -Because "We dont want orphaned users"
                }
            }
        }
    }
}

Describe "Foreign keys and check constraints not trusted" -Tags FKCKTrusted, Low, $filename {
    if ($NotContactable -contains $psitem) {
        Context "Testing Foreign Keys and Check Constraints are not trusted $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Foreign Keys and Check Constraints are not trusted $psitem" {
            @(Get-DbaDbForeignKey -SqlInstance $psitem -ExcludeDatabase $ExcludedDatabases -Database $Database).Where{ $_.NotForReplication -eq $false }.ForEach{
                It "Database $($psitem.Database) Foreign Key $($psitem.Name) on table $($psitem.Parent) should be trusted on $($psitem.SqlInstance)" {
                    $psitem.IsChecked | Should -Be $true -Because "This can have a huge performance impact on queries. SQL Server won't use untrusted constraints to build better execution plans. It will also avoid data violation"
                }
            }

            @(Get-DbaDbCheckConstraint -SqlInstance $psitem -ExcludeDatabase $ExcludedDatabases -Database $Database).Where{ $_.NotForReplication -eq $false -and $_.IsEnabled -eq $true }.ForEach{
                It "Database $($psitem.Database) Check Constraint $($psitem.Name) on table $($psitem.Parent) should be trusted on $($psitem.SqlInstance)" {
                    $psitem.IsChecked | Should -Be $true -Because "This can have a huge performance impact on queries. SQL Server won't use untrusted constraints to build better execution plans. It will also avoid data violation"
                }
            }
        }
    }
}

Describe "Database MaxDop" -Tags MaxDopDatabase, MaxDop, Low, $filename {
    $MaxDopValue = Get-DbcConfigValue policy.database.maxdop
    [string[]]$exclude = Get-DbcConfigValue policy.database.maxdopexcludedb
    $exclude += $ExcludedDatabases
    if ($exclude) { Write-Warning "Excluded $exclude from testing" }
    if ($NotContactable -contains $psitem) {
        Context "Database MaxDop setting is correct on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Database MaxDop setting is correct on $psitem" {
            @(Test-DbaMaxDop -SqlInstance $psitem).Where{ $_.Database -ne 'N/A' -and $(if ($database) { $PsItem.Database -in $Database } else { $_.Database -notin $exclude }) }.ForEach{
                It "Database $($psitem.Database) should have the correct MaxDop setting on $($psitem.SqlInstance)" {
                    Assert-DatabaseMaxDop -MaxDop $PsItem -MaxDopValue $MaxDopValue
                }
            }
        }
    }
}

Describe "Database Exists" -Tags DatabaseExists, $filename {
    $expected = Get-DbcConfigValue database.exists
    if ($Database) { $expected += $Database }
    $expected = $expected.where{ $psitem -notin $ExcludedDatabases }
    if ($NotContactable -contains $psitem) {
        Context "Database exists on $psitem" {
            It "Can't Connect to $Psitem" {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        $instance = $psitem
        Context "Database exists on $psitem" {
            $expected.ForEach{
                It "Database $psitem should exist on $($psitem.Parent.Name)" {
                    Assert-DatabaseExists -Instance $instance -Expecteddb $psitem
                }
            }
        }
    }
}

Describe "CLR Assemblies SAFE_ACCESS" -Tags CLRAssembliesSafe, CIS, $filename {
    $skip = Get-DbcConfigValue skip.security.clrassembliessafe
    [string[]]$exclude = Get-DbcConfigValue policy.database.clrassembliessafeexcludedb
    $ExcludedDatabases += $exclude
    if ($NotContactable -contains $psitem) {
        Context "Testing that all user-defined CLR assemblies are set to SAFE_ACCESS on $psitem" {
            It "Can't Connect to $Psitem" -Skip:$skip {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing that all user-defined CLR assemblies are set to SAFE_ACCESS on $psitem" {
            $instance = $psitem
            @($InstanceSMO.Databases.Where{ ($(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name })) }).ForEach{
                It "Database $($psitem.Name) user-defined CLR assemblies are set to SAFE_ACCESS on $($psitem.Parent.Name)" {
                    Assert-CLRAssembliesSafe -Instance $instance -Database $psitem.Name
                }
            }
        }
    }
}

Describe "SymmetricKeyEncryptionLevel" -Tags SymmetricKeyEncryptionLevel, CIS, $filename {
    $skip = Get-DbcConfigValue skip.security.symmetrickeyencryptionlevel
    $ExcludedDatabases = $ExcludedDatabases + "master", "tempdb", "msdb"
    if ($NotContactable -contains $psitem) {
        Context "Testing Symmetric Key Encryption Level at least AES_128 or higher on $psitem" {
            It "Can't Connect to $Psitem" -Skip:$skip {
                $true | Should -BeFalse -Because "The instance should be available to be connected to!"
            }
        }
    } else {
        Context "Testing Symmetric Key Encryption Level at least AES_128 or higher on $psitem" {
            @($InstanceSMO.Databases.Where{ ($(if ($Database) { $PsItem.Name -in $Database }else { $ExcludedDatabases -notcontains $PsItem.Name })) }).ForEach{
                It "Database $($psitem.Name) Symmetric Key Encryption Level should have AES_128 or higher on $($psitem.Parent.Name)" -Skip:$skip {
                    Assert-SymmetricKeyEncryptionLevel -Instance $instance -Database $psitem
                }
            }
        }
    }
}
