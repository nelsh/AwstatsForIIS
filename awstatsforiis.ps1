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

# Main Procedure

if (!$task) {
    ExitWithMsg("Not set task")
}
switch ($task) {
    "setup" { Task-Setup }
    default { ExitWithMsg("Task {0} not found" -f $task ) }
}
