$password = ConvertTo-SecureString -String 'Qlik1234' -AsPlainText -Force
$SenseService = New-Object System.Management.Automation.PSCredential("sense-cn\qservice", $password)
$DbCredential = New-Object System.Management.Automation.PSCredential("qliksenserepository", $password)
$password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
$QlikAdmin = New-Object System.Management.Automation.PSCredential("sense-cn\vagrant", $password)
$CachePath = 'C:\kitchen-cache'
$SenseRelease = 'February 2021'
$SensePatch = 1
$SetupPath = "$CachePath\Qlik Sense $SenseRelease\Qlik_Sense_setup.exe"
$UpdatePath = "$CachePath\Qlik Sense $SenseRelease Patch $SensePatch\Qlik_Sense_update.exe"
$Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname

Configuration Default {
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.1.0
    Import-DscResource -ModuleName xSmbShare -ModuleVersion 2.2.0.0
    Import-DscResource -ModuleName xNetworking -ModuleVersion 5.7.0.0
    Import-DscResource -ModuleName QlikResources

    Node $AllNodes.NodeName {
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
            MembersToInclude = $QlikAdmin.GetNetworkCredential().UserName, $SenseService.GetNetworkCredential().UserName
            DependsOn        = "[User]QlikAdmin", "[User]SenseService"
        }

        File Cache {
            Type            = 'Directory'
            DestinationPath = $CachePath
            Ensure          = 'Present'
        }

        xRemoteFile SenseSetup {
            DestinationPath = $SetupPath
            Uri             = 'https://da3hntz84uekx.cloudfront.net/QlikSense/14.5/0/_MSI/Qlik_Sense_setup.exe'
            ChecksumType    = 'SHA256'
            Checksum        = '2362399C6152E47EED72A2F7B84E8AF4E21E760299BBE6F139A25930A615EECD'
            MatchSource     = $false
            DependsOn       = '[File]Cache'
        }
    
        if ($SensePatch -gt 0) {
            xRemoteFile SenseUpdate {
                DestinationPath = $UpdatePath
                Uri             = 'https://da3hntz84uekx.cloudfront.net/QlikSense/14.5/1/_MSI/Qlik_Sense_update.exe'
                ChecksumType    = 'SHA256'
                Checksum        = '299C679C2750B3E360CF291CC9E3A9A3AD70D57E9F742E6CEC547E80EC65DB94'
                MatchSource     = $false
                DependsOn       = '[File]Cache'
            }
        }

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
            Hostname             = $Hostname
            ConfigureLogging     = $false
            QLogsWriterPassword  = $DbCredential
            QLogsReaderPassword  = $DbCredential
            AcceptEula           = $true
            Ensure               = 'Present'
            PSDscRunasCredential = $QlikAdmin
            DependsOn            = '[xSmbShare]QlikClusterShare', '[Group]Administrators', '[xRemoteFile]SenseSetup'
        }

        $services = @("QlikSenseRepositoryDatabase", "QlikSenseRepositoryService", "QlikSenseServiceDispatcher",
            "QlikSensePrintingService", "QlikSenseSchedulerService", "QlikSenseEngineService", "QlikSenseProxyService")
        foreach ($svc in $services) {
            xService $svc {
                Name      = $svc
                State     = "Running"
                DependsOn = "[QlikPackage]Sense"
            }
        }

        QlikConnect Central {
            Computername         = $Hostname
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

        QlikProxy Central {
            Node                                = 'sense-cn'
            ListenPort                          = 443
            AllowHttp                           = $true
            UnencryptedListenPort               = 8000
            AuthenticationListenPort            = 4245
            KerberosAuthentication              = $true
            UnencryptedAuthenticationListenPort = 4246
            SslBrowserCertificateThumbprint     = 'foobar'
            KeepAliveTimeoutSeconds             = 20
            MaxHeaderSizeBytes                  = 65534
            MaxHeaderLines                      = 200
            RestListenPort                      = 4234
            CustomProperties                    = @{
                Foo = 'Foobar'
            }
            PSDscRunasCredential                = $QlikAdmin
            DependsOn                           = '[QlikLicense]Sense'
        }

        xFirewall QRS {
            Name                 = "QRS"
            DisplayName          = "Qlik Sense Repository Service"
            Group                = "Qlik Sense"
            Ensure               = "Present"
            Action               = "Allow"
            Enabled              = "True"
            Profile              = ("Domain", "Private", "Public")
            Direction            = "InBound"
            LocalPort            = ("4242")
            Protocol             = "TCP"
            DependsOn            = "[QlikPackage]Sense"
        }
    
        xFirewall QPS {
            Name                 = "QPS"
            DisplayName          = "Qlik Sense Proxy HTTPS"
            Group                = "Qlik Sense"
            Ensure               = "Present"
            Action               = "Allow"
            Enabled              = "True"
            Profile              = ("Domain", "Private", "Public")
            Direction            = "InBound"
            LocalPort            = ("443")
            Protocol             = "TCP"
            DependsOn            = "[QlikPackage]Sense"
        }
    }
}
