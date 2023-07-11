./build.ps1 -Tasks build

Import-Module dbachecks -Force

$password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password
$show = 'All'

$checks = 'ContainedDBSQLAuth','ContainedDBAutoClose'

#$sqlinstances = 'dbachecks1', 'dbachecks2', 'dbachecks3'

$sqlinstances = 'localhost,7401', 'localhost,7402', 'localhost,7403'

$v4code = Invoke-DbcCheck -SqlInstance $Sqlinstances -SqlCredential $cred -Check $Checks -legacy $true -Show $show -PassThru
# Run v5 checks
$v5code = Invoke-DbcCheck -SqlInstance $Sqlinstances -SqlCredential $cred -Check $Checks -legacy $false -Show $show -PassThru -Verbose

# these both look fine to me!
$v4code | Convert-DbcResult
$v5code | Convert-DbcResult

Invoke-PerfAndValidateCheck -SQLInstances $sqlinstances -Checks $Checks
Invoke-PerfAndValidateCheck -SQLInstances $sqlinstances -Checks $Checks -PerfDetail
Invoke-PerfAndValidateCheck -SQLInstances $sqlinstances -Checks $Checks -showTestResults
