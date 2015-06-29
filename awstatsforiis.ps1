param($task)

function ExitWithMsg($msg) {
    Write-Host "Error: $msg`n" -foregroundcolor "red"
    $scriptname=$MyInvocation.ScriptName
    "Usage:`n"
    "`t$scriptname -task <taskname>`n"
    "`twhere 'taskname' is one from: setup, checkcfg, build, summary`n" 
    exit(1)
}

function Task-Setup {
    "Run Setup task"
}

#
# MAIN PROCEDURE
#
if (!$task) {
    ExitWithMsg("Not set task")
}
# Read parameters from ini-file
$inifile = Join-Path $PSScriptRoot ( $MyInvocation.MyCommand.Name.Replace("ps1", "ini") )
if (!(Test-Path $inifile)) {
    Write-Host ("INI-file not found '{0}'." -f $inifile) -foregroundcolor "red"
    exit(1)
}

switch ($task) {
    "setup" { Task-Setup }
    default { ExitWithMsg("Task {0} not found" -f $task ) }
}
