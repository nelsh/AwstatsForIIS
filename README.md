# AwstatsForIIS README #

## Задача ##

Установить [AWStats](http://www.awstats.org/) для анализа журналов MS IIS и предоставить доступ к динамическим отчетам.

---

Решение проверено на Windows Server 2012 R2 с .NET Framework 4.5.2. 

***Внимание:*** *Все действия по установке и настройке выполняются в консоли PowerShell в режиме администратора*

## Установка ##

Нам потребуется интерпретатор Perl. Мы будем использовать [Strawberry Perl](http://strawberryperl.com/), установленный по умолчанию в каталог `C:\Strawberry\`. Для получения и установки версии за апрель 2014 запустите

    Invoke-WebRequest -Uri http://strawberryperl.com/download/5.18.2.2/strawberry-perl-5.18.2.2-64bit.msi -OutFile strawberry-perl-5.18.2.2-64bit.msi
    .\strawberry-perl-5.18.2.2-64bit.msi /passive

AWStats установим в каталог `c:\awstats`. Там же разместим конфигурационные файлы, данные и AwstatsForIIS. Но можно выбрать любое другое место - достаточно внести необходимые изменения в конфигурационный файл.

* Для получения AWStats 7.3 (стабильной версии на момент написания инструкции) с SourceForge нам потребуется [Wget](https://eternallybored.org/misc/wget/). Полученный архив мы распакуем в `C:\Awstats`.

        Invoke-WebRequest -Uri https://eternallybored.org/misc/wget/wget64.exe -OutFile wget.exe
        .\wget.exe http://prdownloads.sourceforge.net/awstats/awstats-7.3.zip
        Add-Type -Assembly "System.IO.Compression.FileSystem"
        [System.IO.Compression.ZipFile]::ExtractToDirectory("awstats-7.3.zip", "c:\")
        Rename-Item c:\awstats-7.3 c:\awstats

* Создадим каталоги для конфигурационных файлов и данных AWStats, а также для скрипта `awstatsforiis.ps1`

        New-Item c:\awstats\config -type directory
        New-Item c:\awstats\data -type directory
        New-Item c:\awstats\script -type directory

* Сохранить в каталог скриптов `awstatsforiis.ps1` и пример конфигурационного файла

        Invoke-WebRequest -Uri https://raw.githubusercontent.com/nelsh/AwstatsForIIS/master/awstatsforiis.ps1 -OutFile c:\awstats\script\awstatsforiis.ps1
        Invoke-WebRequest -Uri https://raw.githubusercontent.com/nelsh/AwstatsForIIS/master/awstatsforiis.ini -OutFile c:\awstats\script\awstatsforiis.ini


## Параметры конфигурационного файла ##

**Важно!** В конфигурационном файле приведен пример настроек для следующей конфигурации журналов IIS (может меняться только "Directory")

    ![IIS-LogSettings.png](https://bitbucket.org/repo/6d7yBg/images/3430954973-IIS-LogSettings.png)

Создадим/отредактируем конфигурационный файл `c:\awstats\config\awstatsforiis.ini`

* Укажем пути, выбранные при установке (каталог для данных чуть ниже - в параметрах для common.conf)

        PERLEXE         = C:\\Strawberry\\perl\\bin\\perl.exe
        AWSTATSPATH     = C:\\awstats
        AWSTATSCONF     = C:\\awstats\\config

* Шаблон конфигурационного файла для сайта (символ "!" заменяется на символ перевода строки)

        AWSTATSTMPL     = Include "common.conf"!LogFile="{0}\\W3SVC{1}\\u_ex%YY-24%MM-24%DD-24.log"!SiteDomain="{2}"!HostAliases="{2}"

* Сайт, к которому будет подключено виртуальное приложение Awstats

        SITEFORAWSTATS  = Default Web Site

* Список полей для журнала IIS (параметр в конфигурации IIS)

        ;logExtFileFlags=list fields in IIS configuration
        logExtFileFlags = Date, Time, ClientIP, UserName, SiteName, ComputerName, ServerIP, Method, UriStem, UriQuery, HttpStatus, Win32Status, BytesSent, BytesRecv, TimeTaken, ServerPort, UserAgent, Cookie, Referer, ProtocolVersion, Host, HttpSubStatus

* Исключаемые сайты по ID и по dns-имени

        ExcludeSites    = 1,...
        ExcludeBinding  = ww1.example.com,ww2.example.com

* Почтовый адрес и сервер для уведомлений о выполнении задачи "Добавление/Проверка конфигурационных файлов для сайтов". Для отключение - удалить.

        MAILADDRESS     = AWSTATS <sysadmin@example.com>
        MAILSERVER      = mx.example.com

* Укажите параметры для Awstats по умолчанию (будут записаны в `c:\awstats\config\common`)

        ;parameters = in awstats common.conf
        AWSTATSCHANGEPARS= LogFormat,HostAliases,DNSLookup,DirData,DirIcons,AllowFullYearView,BuildHistoryFormat

        LogFormat="date time s-sitename s-computername s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs-version cs(User-Agent) cs(Cookie) cs(Referer) cs-host sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken"
        HostAliases=""
        DNSLookup=0
        DirData="C:/awstats/data"
        DirIcons="../icon"
        AllowFullYearView=3
        BuildHistoryFormat=xml
        ;LoadPlugins = enable plugins
        LoadPlugins = tooltips,decodeutfkeys

## Запуск настройки ##

    .\awstatsforiis.ps1 -task setup

Во время этой задачи выполняются следующие операции

* Регистрация Perl в IIS. 
* Подключение виртуального приложения `c:\awstats\wwwroot` к сайту, на котором будут доступны отчеты. Например к *Default Web Site*
* Разрешение на запуск скриптов perl в этом виртуальном приложении и добавление `awstats.pl` в коллекцию defaultDocument.
* Настройка параметров журнала IIS
* Создание общего файла конфигурации `c:\awstats\config\common.conf` и настройка параметров, указанных в поле конфигурации AWSTATSCHANGEPARS
* Поправка в исходный код `awstats.pl` - добавление выбранного нами каталога конфигурационных файлов в список допустимых

## Регулярные задачи ##

### Добавление, проверка конфигураций для сайтов ###

    .\awstatsforiis.ps1 -task addcheck

По списку всех доменных имен, существующих в конфигурации IIS - за исключением сайтов с идентификаторами, указанными в параметре "ExcludeSites", и исключая доменные имена, указанные в "ExcludeBinding" - выполняются операции

* С помощью шаблона из параметра "AWSTATSTMPL" создается *идеальный* конфигурационный файл для сайта с данным доменным именем
* Если такого конфигурационного файла нет - он записывается в каталог конфигурационных файлов
* Если есть - сравнивается с существующим: если не совпадает - выводится предупреждение.

Суммарный отчет об этой задаче можно получить по e-mail.

Задачу рекомендуется добавить в Task Scheduler

````
schtasks.exe /create /tn AwstastCheck /tr "powershell -ExecutionPolicy Bypass -Command C:\awstats\script\awstatsforiis.ps1 -task addcheck" /sc WEEKLY /d MON /rl HIGHEST /ru SYSTEM /rp /st 08:05:00
````

### Ежедневный запуск по сбору статистики ###

    .\awstatsforiis.ps1 -task build

Для всех обнаруженных конфигурационных файлов сайтов запускается `awstats.pl` для сбора статистики.

Задачу рекомендуется добавить в Task Scheduler

````
schtasks.exe /create /tn AwstastCheck /tr "powershell -ExecutionPolicy Bypass -Command C:\awstats\script\awstatsforiis.ps1 -task build" /sc DAILY /rl HIGHEST /ru SYSTEM /rp /st 10:05:00
````
