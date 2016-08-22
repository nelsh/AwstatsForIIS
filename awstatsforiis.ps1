param(
    [Parameter(Mandatory=$True)]
    [ValidateSet("setup", "addcheck", "build", "logrotate", "logdelete")]
    [string[]]$tasks,
   
    $srcPath, $trgPath
)

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
    $commonconf = Join-Path $ini["AWSTATSCONF"] "common.conf"
    # create common config
    Copy-Item (Join-Path $ini["AWSTATSPATH"] "wwwroot\cgi-bin\awstats.model.conf") $commonconf -Force
    
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

    # patch awstats.pl
    $awstatspl = Join-Path $ini["AWSTATSPATH"] "wwwroot\cgi-bin\awstats.pl"
    Copy-Item $awstatspl ($awstatspl + ".bak")
    $tmp = (Get-Content $awstatspl) -join "`n"
    $tmp | ForEach-Object { $_  -replace `
        "my @PossibleConfigDir = \(", `
        ("my @PossibleConfigDir = ( `"" + $ini["AWSTATSCONF"].Replace("\", "/") + "`"") } `
        | Set-Content $awstatspl 

}

# run once from function Task-Setup
function Task-Setup {
    Task-Setup-IIS
    Task-Setup-Awstats
}

# help function
function Send-Mail ($subj, $body) {
    $msg = New-Object Net.Mail.MailMessage($ini["MAILADDRESS"], $ini["MAILADDRESS"])
    $msg.Subject = $subj
    $msg.Body = $body
    $smtp = New-Object Net.Mail.SmtpClient("")
    if ($ini["MAILSERVER"].Contains(":")) {
        $mailserver = $ini["MAILSERVER"].Split(":")
        $smtp.Host = $mailserver[0]
        $smtp.Port = $mailserver[1]
    }
    else {
        $smtp.Host = $ini["MAILSERVER"]
    }
    #$smtp.EnableSsl = $true 
    if ($ini.ContainsKey("MAILUSER") -and $ini.ContainsKey("MAILPASSWORD"))  {
        $smtp.Credentials = New-Object System.Net.NetworkCredential($ini["MAILUSER"], $ini["MAILPASSWORD"]); 
    }
    $smtp.Send($msg)
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
    $skippedSitesCount = 0
    $skippedBinding = ""
    $skippedBindingCount = 0
    $incorrectContent = ""
    $incorrectContentCount = 0
    $totalNames = 0
    $totalChecked = 0
    $totalWrited = 0
    $idn = New-Object System.Globalization.IdnMapping

    foreach ($site in Get-ChildItem -Path IIS:\Sites) {
    if ($ExcludeSites.Contains($site.ID.ToString()) -or $site.Name.StartsWith("_") -or $site.Name.ToLower().Contains("test")) {
            $skippedSitesCount++
            $skippedSites += ("`t#" + $site.ID + " " + $site.Name + "`n")
        } else {
            ("#" + $site.ID + " " + $site.Name)
            foreach ($binding in $site.Bindings.collection) {
            $dnsname = $idn.GetAscii($binding.bindingInformation.split(":")[2])
            if ($ExcludeBinding.Contains($dnsname) -or $binding.bindingInformation.Contains("https") -or $dnsname.ToLower().Contains("test")) {
                    $skippedBindingCount++
                    $skippedBinding += ("`t#" + $site.ID + " " + $site.Name + " " + $dnsname + "`n")
                } else {
                    $totalNames++
                    $currentConf = Join-Path $ini["AWSTATSCONF"] ("awstats." +$dnsname + ".conf")
                    $correctContent = ($ini["AWSTATSTMPL"] -f (Get-Item env:\Computername).Value.ToLower(), $site.ID, $dnsname) -replace "!", "`n"
                    if (Test-Path $currentConf) {
                        "`tCheck $currentConf"
                        $totalChecked++
                        if (((Get-Content $currentConf) -join "`n") -eq $correctContent) {
                            continue
                        } else {
                            $incorrectContentCount++
                            $incorrectContent  += ("`t#" + $site.ID + " " + $site.Name + "`n")
                        }
                    }
                    "`tWrite $currentConf"
                    $totalWrited++
                    Set-Content $currentConf $correctContent 
                }
            }
        }
    }
    $infomsg = "`nincorrectContent:`n$incorrectContent`nskippedSites:`n$skippedSites`nskippedBinding:`n$skippedBinding"
    $infomsg

    if ($ini.ContainsKey("MAILADDRESS") -and $ini.ContainsKey("MAILSERVER"))  {
        $subj = ('Awstats {0}. Total/Checked/Writed: {1}/{2}/{3}. Incorrect/SkipSites/SkipNames: {4}/{5}/{6}' `
            -f (Get-Item env:\Computername).Value, 
                $totalNames, $totalChecked, $totalWrited,
                $incorrectContentCount,$skippedSitesCount, $skippedBindingCount)
        Send-Mail $subj $infomsg
    }
}

function Task-LogRotate {
    # Use Info-Zip
    $zipLogFile = "rotate.log"
    $t = Get-Date (Get-Date).AddDays(-7) -uformat "%Y-%m-%d"
    $tt = Get-Date -uformat "%Y-%m-%d"
    $zipExe = "./zip.exe -m -r -li -lf " + $zipLogFile + " -t " + $t  + " -tt " + $tt
    echo $zipExe
    # Zip Archive Name = trgPath + iislog + year + number of week
    $zipFile = Join-Path $trgPath ("iislog" + (get-date -uformat "%y") + "w" + (get-date -uformat "%W"))

    invoke-expression ($zipExe + " " + $zipFile + " " +  $srcPath)
    if ($LastExitCode -eq 0) { 
	    $subj = "IIS log rotate: SUCCESS. " 
    }
    else {
	    $subj = "IIS log rotate: ERROR. "
    }

    $zipLog = Get-Content $zipLogFile
    $subj += ($zipLog | Select-String 'total' -SimpleMatch) -join ". "
    if ($ini.ContainsKey("MAILADDRESS") -and $ini.ContainsKey("MAILSERVER"))  {
        Send-Mail $subj ($zipLog -join "`n")
    }
}

function Task-LogDelete {
    $targetpath = (Get-WebConfiguration system.applicationHost/sites/siteDefaults/logFile/@directory).Value
    foreach ( $f in get-childitem $targetpath -include *.log -recurse | where-object {$_.LastWriteTime -lt (Get-Date).AddDays(-8)} )  { remove-item $f.fullname }
}

function Task-Build-Data {
    "Build/Update Site Statistic Database"
    foreach ($config in (Get-ChildItem (Join-Path $ini["AWSTATSCONF"] "awstats.*.conf"))) { 
        $currentConfig = $config.Name.Replace("awstats.", "").Replace(".conf","")
        "$currentConfig - analyze last log file"
        $awstatspl = Join-Path $ini["AWSTATSPATH"] "wwwroot\cgi-bin\awstats.pl"
        & $ini["PERLEXE"] $awstatspl ("-configdir=" + $ini["AWSTATSCONF"]) ("-config=" + $currentConfig)
    }
}

function Task-Build-Index {
    $dataList = @{}
    $dataDates = @{}
    foreach ($config in (Get-ChildItem (Join-Path $ini["AWSTATSCONF"] "awstats.*.conf"))) { 
        $currentConfig = $config.Name.Replace("awstats.", "").Replace(".conf","")
        $currentConfig
        $currentDates = @{}
        foreach ($data in (Get-ChildItem (Join-Path $ini["DirData"].Replace("`"", '') "awstats*.$currentConfig.txt"))) { 
            $d = $data.Name.Replace("awstats", "").Replace(".$currentConfig.txt", "")
            $d = $d.Substring(2) + $d.Substring(0,2)
            $totalUnique = Get-Content $data.FullName -TotalCount 70 | Select-String '>TotalUnique<' -SimpleMatch -List
            $totalUnique = $totalUnique.ToString().Replace("<tr><td>TotalUnique</td><td>", "").Replace("</td></tr>", "").Trim()
            $currentDates.Add($d, $totalUnique)
            if (!$dataDates.ContainsKey($d)) {
                $dataDates.Add($d, "")
            }
            "`t$d`t$totalUnique"
        }
        $dataList.Add($currentConfig, $currentDates)
    }

    $indexfile = Join-Path $ini["AWSTATSPATH"] "wwwroot\index.html"
    $currentDate = (Get-Date).ToString('dd.MM.yyyy')
    Set-Content $indexfile ("<html>
    <head>
    <title>AWStats Sites Links - " + $currentDate + "</title>
    <style>
    body {font-family:Verdana;font-size:0.7em;}
    table {font-family:Verdana;font-size:1em;}
    th {text-align:left;border: solid 1px #666;}
    td {text-align:right;border: solid 1px #ccc;}
    td.col01 {border-right: solid 1px #666;}
    td.col12 {border-left: solid 1px #666;}
    td.col07 {border-right: solid 1px #999;}
    td.col06 {border-left: solid 1px #999;}
    thead th {text-align:center;}
    a {display:block;padding:3px;text-decoration:none;}
    a:hover {background:#ff6;color:#f0f;}
    </style>
    </head>
    <body>
    <p>Last Updated: " + $currentDate + "</p>
    <table border='1'>
    <thead><tr><th>Site</th>");

    foreach ($data in $dataDates.GetEnumerator() | sort name -Descending) {
        Add-Content $indexfile (`
            "<th align=center><small>" `
             + $data.Name.Substring(0,4) `
             + "</small><br><large>" `
             + $data.Name.Substring(4) `
             + "</large></th>");
    }
    Add-Content $indexfile "</tr></thead>"

    foreach ($config in $dataList.GetEnumerator() | sort name) {
        Add-Content $indexfile ("<tr><th>" + $config.Name + "</th>")
        foreach ($data in $dataDates.GetEnumerator() | sort name -Descending) {
            $y = $data.Name.Substring(0,4)
            $m = $data.Name.Substring(4)
            if ($dataList[$config.Name].ContainsKey($data.Name)) {
                Add-Content $indexfile (`
                    "<td class=col" + $m + ">"`
				    + "<a href='/awstats/cgi-bin/?config=" + $config.Name` + "&month=" + $m` + "&year=" + $y + "'>"`
                    + $dataList[$config.Name][$data.Name] + "</a>"`
                    + "</td>");

            } else {
                Add-Content $indexfile ("<td class=col" + $data.Name.Substring(4) + ">&nbsp;</td>")
            }
        }
        Add-Content $indexfile "</tr>"
    }
    Add-Content $indexfile "</table></body></html>"
}

function Task-Build {
    Task-Build-Data
    Task-Build-Index
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

# Run Tasks

foreach ($task in $tasks) {
    switch ($task) {
        "setup"        { Task-Setup }
        "addcheck"     { Task-AddCheck }
        "build"        { Task-Build }
        "logrotate"    { Task-LogRotate }
        "logdelete"    { Task-LogDelete }
    }
}

