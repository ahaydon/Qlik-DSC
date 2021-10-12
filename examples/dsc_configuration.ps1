$Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname
$password = ConvertTo-SecureString -String 'Qlik1234' -AsPlainText -Force
$SenseService = New-Object System.Management.Automation.PSCredential("$Hostname\qservice", $password)
$DbCredential = New-Object System.Management.Automation.PSCredential("qliksenserepository", $password)
$password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
$QlikAdmin = New-Object System.Management.Automation.PSCredential("$Hostname\vagrant", $password)
$CachePath = 'C:\kitchen-cache'
$SenseRelease = 'May 2021'
$SensePatch = 3
$SetupPath = "$CachePath\Qlik Sense $SenseRelease\Qlik_Sense_setup.exe"
$UpdatePath = "$CachePath\Qlik Sense $SenseRelease Patch $SensePatch\Qlik_Sense_update.exe"

Configuration Default {
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.1.0
    Import-DscResource -ModuleName xSmbShare -ModuleVersion 2.2.0.0
    Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
    Import-DscResource -ModuleName QlikResources

    $CentralNode = $AllNodes.Where{ $_.IsCentral }.NodeName

    Node $AllNodes.Where{ $_.NodeName -eq $Hostname }.NodeName {
        foreach ($Name in @('Domain', 'Private', 'Public')) {
            xFirewallProfile $Name {
                Name = $Name
                Enabled = 'False'
            }
        }

        User QlikAdmin {
            UserName               = $QlikAdmin.GetNetworkCredential().UserName
            Password               = $QlikAdmin
            FullName               = 'Qlik User'
            PasswordChangeRequired = $false
            PasswordNeverExpires   = $true
            Ensure                 = 'Present'
        }

        User SenseService {
            UserName                 = $SenseService.GetNetworkCredential().UserName
            Password                 = $SenseService
            FullName                 = 'Qlik Sense Service Account'
            PasswordChangeNotAllowed = $true
            PasswordChangeRequired   = $false
            PasswordNeverExpires     = $true
            Ensure                   = 'Present'
        }

        Group Administrators {
            GroupName        = 'Administrators'
            MembersToInclude = $QlikAdmin.GetNetworkCredential().UserName
            DependsOn        = "[User]QlikAdmin"
        }

        File Cache {
            Type            = 'Directory'
            DestinationPath = $CachePath
            Ensure          = 'Present'
        }

        xRemoteFile SenseSetup {
            DestinationPath = $SetupPath
            Uri             = 'https://da3hntz84uekx.cloudfront.net/QlikSense/14.20/0/_MSI/Qlik_Sense_setup.exe'
            ChecksumType    = 'SHA256'
            Checksum        = 'c9fc20e2b73aa20557302bb137384a4040bdd6edbad2cbe8cf57f6b66f6dc054'
            MatchSource     = $false
            DependsOn       = '[File]Cache'
        }

        if ($SensePatch -gt 0) {
            xRemoteFile SenseUpdate {
                DestinationPath = $UpdatePath
                Uri             = 'https://da3hntz84uekx.cloudfront.net/QlikSense/14.20/3/_MSI/Qlik_Sense_update.exe'
                ChecksumType    = 'SHA256'
                Checksum        = '8e2a8322f613c320ab675eaa45168dd8a62c9b20a5dfe0ee9e0c50ad816c0630'
                MatchSource     = $false
                DependsOn       = '[File]Cache'
            }
        }

        if ($Node.IsCentral) {
            File QlikClusterRoot {
                Type            = 'Directory'
                DestinationPath = 'C:\QlikShare'
                Ensure          = 'Present'
            }

            xSmbShare QlikClusterShare {
                Path       = 'C:\QlikShare'
                Name       = 'QlikShare'
                FullAccess = $SenseService.UserName
                Ensure     = 'Present'
                DependsOn  = '[File]QlikClusterRoot'
            }

            QlikPackage Sense {
                Name                 = "Qlik Sense $SenseRelease"
                Setup                = $SetupPath
                Patch                = $UpdatePath
                ServiceCredential    = $SenseService
                RootDir              = "\\$Hostname\QlikShare"
                DbSuperUserPassword  = $DbCredential
                DbCredential         = $DbCredential
                CreateCluster        = $true
                InstallLocalDb       = $true
                ConfigureDbListener  = $true
                ListenAddresses      = '*'
                IpRange              = '0.0.0.0/0,::0/0'
                MaxConnections       = 400
                Hostname             = $Hostname
                ConfigureLogging     = $false
                QLogsWriterPassword  = $DbCredential
                QLogsReaderPassword  = $DbCredential
                AcceptEula           = $true
                Ensure               = 'Present'
                PSDscRunasCredential = $QlikAdmin
                DependsOn            = '[xSmbShare]QlikClusterShare', '[Group]Administrators', '[xRemoteFile]SenseSetup'
            }
        }
        else {
            QlikPackage Sense {
                Setup                = $SetupPath
                Patch                = $UpdatePath
                AcceptEula           = $true
                ServiceCredential    = $SenseService
                SkipValidation       = $true
                DbHost               = $CentralNode
                DbPort               = 4432
                DbCredential         = $DbCredential
                ConfigureLogging     = $false
                SkipStartServices    = $true
                Ensure               = 'Present'
                PsDscRunasCredential = $QlikAdmin
                DependsOn            = '[Group]Administrators', '[xRemoteFile]SenseSetup'
            }

            QlikConnect Central {
                Computername         = $CentralNode
                Username             = "$CentralNode\$($QlikAdmin.GetNetworkCredential().UserName)"
                TrustAllCerts        = $true
                PSDscRunasCredential = $QlikAdmin
                DependsOn            = '[QlikPackage]Sense'
            }

            QlikNode Rim {
                Name                 = $Hostname
                Hostname             = $Hostname
                Proxy                = $true
                Engine               = $true
                Printing             = $true
                Scheduler            = $true
                Ensure               = 'Present'
                PsDscRunasCredential = $QlikAdmin
                DependsOn            = '[QlikConnect]Central'
            }
        }

        $serviceDependency = @('[QlikPackage]Sense')
        if (-not $Node.IsCentral) {
            $serviceDependency += '[QlikNode]Rim'
        }
        $services = @("QlikLoggingService", "QlikSenseRepositoryService", "QlikSenseServiceDispatcher",
            "QlikSensePrintingService", "QlikSenseSchedulerService", "QlikSenseEngineService", "QlikSenseProxyService")
        foreach ($svc in $services) {
            xService $svc {
                Name      = $svc
                State     = 'Running'
                DependsOn = $serviceDependency
            }
        }

        if ($Node.IsCentral) {
            QlikConnect Central {
                Computername         = $CentralNode
                Username             = $QlikAdmin.UserName
                PSDscRunasCredential = $QlikAdmin
                DependsOn            = '[xService]QlikSenseProxyService'
            }

            $License = $ConfigurationData.Sense.License
            QlikLicense Sense {
                Serial               = $License.Serial
                Control              = $License.Control
                Name                 = $License.Name
                Organization         = $License.Organization
                Lef                  = $License.Lef
                Ensure               = "Present"
                PSDscRunasCredential = $QlikAdmin
                DependsOn            = "[QlikConnect]Central"
            }
        }
        else {
            QlikProxy Central {
                Node                                = $Hostname
                SslBrowserCertificateThumbprint     = 'foobar'
                KeepAliveTimeoutSeconds             = 20
                MaxHeaderSizeBytes                  = 65534
                MaxHeaderLines                      = 200
                CustomProperties                    = @{
                    Foo = 'Foobar'
                }
                PSDscRunasCredential                = $QlikAdmin
                DependsOn                           = '[xService]QlikSenseProxyService'
            }
        }

        QlikUser Vagrant {
            UserId               = 'vagrant'
            UserDirectory        = $Node.NodeName
            Name                 = 'Vagrant User'
            Roles                = 'RootAdmin'
            Ensure               = 'Present'
            PSDscRunasCredential = $QlikAdmin
            DependsOn            = '[QlikConnect]Central'
        }
    }
}
