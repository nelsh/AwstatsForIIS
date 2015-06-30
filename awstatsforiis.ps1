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
    $perlexewithpar = $ini["PERLEXE"] + " `"%s`" %s"
    Add-WebConfiguration system.webServer/security/isapiCgiRestriction `
        -Value @{
            path="$perlexewithpar";
            allowed="true";
            description="Perl CGI"}

    New-Item ('IIS:\Sites\' + $ini["SITEFORAWSTATS"] + '\Awstats') `
         -physicalPath (Join-Path $ini["AWSTATSPATH"] "wwwroot") -type Application

    $pspath = ("MACHINE/WEBROOT/APPHOST/" + $ini["SITEFORAWSTATS"] + "/awstats/")
    Add-WebConfigurationProperty -pspath $pspath -Filter system.webServer/handlers -Name . `
        -Value @{
            name="Perl CGI for .pl";
            path="*.pl";
            verb="GET,HEAD,POST";
            modules="CgiModule";
            scriptProcessor="$perlexewithpar";
            resourceType="File";}
    Add-WebConfigurationProperty -pspath $pspath -Filter system.webServer/defaultDocument/files -Name . `
        -Value @{value="awstats.pl";}
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
$ini = ConvertFrom-StringData((Get-Content $inifile) -join "`n")

# Run Task
switch ($task) {
    "setup" { Task-Setup }
    default { ExitWithMsg("Task {0} not found" -f $task ) }
}
