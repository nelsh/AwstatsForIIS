param($task)

function ExitWithMsg($msg) {
    Write-Host "Error: $msg`n" -foregroundcolor "red"
    $scriptname=$MyInvocation.ScriptName
    "Usage:`n"
    "`t$scriptname -task <taskname>`n"
    "`twhere 'taskname' is one from: setup, checkcfg, build, summary`n" 
    exit(1)
}

function Task-Setup-IIS {
    "Run IIS Setup task"
    $perlexewithpar = $ini["PERLEXE"] + " `"%s`" %s"
    
    # Register Perl in IIS
    Add-WebConfiguration system.webServer/security/isapiCgiRestriction `
        -Value @{
            path="$perlexewithpar";
            allowed="true";
            description="Perl CGI"}

    # Add virtual application "Awstats" to site SITEFORAWSTATS
    New-Item ('IIS:\Sites\' + $ini["SITEFORAWSTATS"] + '\Awstats') `
         -physicalPath (Join-Path $ini["AWSTATSPATH"] "wwwroot") -type Application

    # Allow execute *.pl scripts in virtual application "Awstats"
    $pspath = ("MACHINE/WEBROOT/APPHOST/" + $ini["SITEFORAWSTATS"] + "/awstats/")
    Add-WebConfigurationProperty -pspath $pspath -Filter system.webServer/handlers -Name . `
        -Value @{
            name="Perl CGI for .pl";
            path="*.pl";
            verb="GET,HEAD,POST";
            modules="CgiModule";
            scriptProcessor="$perlexewithpar";
            resourceType="File";}
    # Add "awstats.pl" to defaultDocument collection in virtual application "Awstats"
    Add-WebConfigurationProperty -pspath $pspath -Filter system.webServer/defaultDocument/files -Name . `
        -Value @{value="awstats.pl";}

    # Set list logfields
    Set-WebConfiguration system.applicationHost/sites/siteDefaults/logFile/@logExtFileFlags `
        -Value $ini["logExtFileFlags"]
}

function Task-Setup-Awstats {
    "Run Awstats Setup task"
    $commonconf="C:\awstats\config\common.conf"
    # create common config
    Copy-Item C:\awstats\wwwroot\cgi-bin\awstats.model.conf $commonconf -Force
    
    # set common parameters
    $commonconftxt = (Get-Content $commonconf)  -join "`n"
    $pars = $ini["AWSTATSCHANGEPARS"].split(",")
    foreach ($p in $pars) {
        $commonconftxt = [regex]::Replace($commonconftxt, ($p + "=" + ".+"), $p + "=" + $ini[$p]);
    }
    Set-Content $commonconf $commonconftxt

    # enable plugins
    $plugins = $ini["LoadPlugins"].split(",")
    foreach ($p in $plugins) {
        Add-Content $commonconf ("LoadPlugin=`"$p`"")
    }

}

function Task-Setup {
    Task-Setup-IIS
    Task-Setup-Awstats
}

function Task-AddCheck {
    "Add or Check awstats.*.conf file for every site"
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
    "addcheck" { Task-AddCheck }
    default { ExitWithMsg("Task {0} not found" -f $task ) }
}
