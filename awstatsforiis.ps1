param($task)


#
# SETUP TASKS
#

# run once from function Task-Setup
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

# run once from function Task-Setup
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

# run once from function Task-Setup
function Task-Setup {
    Task-Setup-IIS
    Task-Setup-Awstats
}

#
# REGULAR TASKS
#

# run regular from scheduler (weekly or monthly)
function Task-AddCheck {
    "Add or Check awstats.*.conf file for every site"
    if ($ini.ContainsKey("ExcludeSites")) { 
        $ExcludeSites = $ini["ExcludeSites"].split(",")
    }
    if ($ini.ContainsKey("ExcludeBinding")) { 
        $ExcludeBinding = $ini["ExcludeBinding"].split(",")
    }
    $iislogpath = (Get-WebConfiguration system.applicationHost/sites/siteDefaults/logFile/@directory).Value
    $skippedSites = ""
    $skippedBinding = ""
    $incorrectContent = ""
    $totalNames = 0
    $totalChecked = 0
    $totalWrited = 0
    foreach ($site in Get-ChildItem -Path IIS:\Sites) {
        if ($ExcludeSites -contains $site.ID) {
            $skippedSites += ("`t#" + $site.ID + " " + $site.Name + "`n")
        } else {
            ("#" + $site.ID + " " + $site.Name)
            foreach ($binding in $site.Bindings.collection) {
                $dnsname = $binding.bindingInformation.split(":")[2]
                if ($ExcludeBinding -contains $dnsname) {
                    $skippedBinding += ("`t#" + $site.ID + " " + $site.Name + " " + $dnsname + "`n")
                } else {
                    $currentConf = Join-Path $ini["AWSTATSCONF"] ($ini["AWSTATSCONFIGFILENAME"] -f $dnsname)
                    $correctContent = ($ini["AWSTATSCONFIGTEMPLATE"] -f $iislogpath, $site.ID, $dnsname) -replace "!", "`n"
                    if (Test-Path $currentConf) {
                        "`tCheck $currentConf"
                        if (((Get-Content $currentConf) -join "`n") -ne $correctContent) {
                            $incorrectContent  += ("`t#" + $site.ID + " " + $site.Name + "`n")
                        }
                    } else {
                        "`tWrite $currentConf"
                        Set-Content $currentConf $correctContent 
                    }

                }
            }
        }
    }
    "`nincorrectContent:`n$incorrectContent"
    "`nskippedSites:`n$skippedSites" 
    "`nskippedBinding:`n$skippedBinding"

    if ($ini.ContainsKey("MAILADDRESS") -and $ini.ContainsKey("MAILSERVER"))  {
        $msg = New-Object Net.Mail.MailMessage($ini["MAILADDRESS"], $ini["MAILADDRESS"])
        $msg.Subject = ('Awstats {0}. Total/Checked/Writed: {1}/{2}/{3}' `
            -f (Get-Item env:\Computername).Value, $totalNames, $totalChecked, $totalWrited)
        $msg.Body = "`nincorrectContent:`n$incorrectContent"
             + "`nskippedSites:`n$skippedSites"
             + "`nskippedBinding:`n$skippedBinding"
        $smtp = New-Object Net.Mail.SmtpClient($ini["MAILSERVER"])
        $smtp.Send($msg)
    }
}


#
# MAIN PROCEDURE
#

# Read parameters from ini-file
$inifile = Join-Path $PSScriptRoot ( $MyInvocation.MyCommand.Name.Replace("ps1", "ini") )
if (!(Test-Path $inifile)) {
    Write-Host ("INI-file not found '{0}'." -f $inifile) -foregroundcolor "red"
    exit(1)
}
$ini = ConvertFrom-StringData((Get-Content $inifile) -join "`n")

# Run Task
switch ($task) {
    "setup"    { Task-Setup }
    "addcheck" { Task-AddCheck }
    default    { 
        Write-Host "Error: Task not set or not found`n" -foregroundcolor "red"
        $scriptname=$MyInvocation.ScriptName
        "Usage:`n"
        "`t$scriptname -task <taskname>`n"
        "`twhere 'taskname' is one from: setup, checkcfg, build, summary`n" 
        exit(1)
    }
}
