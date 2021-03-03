$password = ConvertTo-SecureString -String 'Qlik1234' -AsPlainText -Force
$SenseService = New-Object System.Management.Automation.PSCredential("sense-cn\qservice", $password)
$password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
$QlikAdmin = New-Object System.Management.Automation.PSCredential("sense-cn\vagrant", $password)
$CachePath = 'C:\kitchen-cache'
$SenseRelease = 'November 2020'
$SensePatch = 3
$SetupPath = "$CachePath\Qlik Sense $SenseRelease\Qlik_Sense_setup.exe"
$UpdatePath = "$CachePath\Qlik Sense $SenseRelease Patch $SensePatch\Qlik_Sense_update.exe"

Configuration Default {
    Import-DscResource -ModuleName PSDesiredStateConfiguration, QlikResources

    Node $AllNodes.NodeName
    {
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
            Uri = 'https://da3hntz84uekx.cloudfront.net/QlikSense/13.102/0/_MSI/Qlik_Sense_setup.exe'
            ChecksumType = 'SHA256'
            Checksum = 'c861d594db361fbb31150c7597196347b7974fe4102cb11d8b75541082b1345a'
            MatchSource = $false
            DependsOn = '[File]Cache'
        }
    
        if ($SensePatch -gt 0) {
            xRemoteFile SenseUpdate {
                DestinationPath = $UpdatePath
                Uri = 'https://da3hntz84uekx.cloudfront.net/QlikSense/13.102/3/_MSI/Qlik_Sense_update.exe'
                ChecksumType = 'SHA256'
                Checksum = '4805463C9B8B857B5F865C6A65FE51C27F556CEAB8897C9E2CF02BEA5958C2E0'
                MatchSource = $false
                DependsOn = '[File]Cache'
            }
        }
    
        QlikCentral CentralNode {
            SenseService         = $SenseService
            QlikAdmin            = $QlikAdmin
            ProductName          = "Qlik Sense $SenseRelease"
            SetupPath            = $SetupPath
            PatchPath            = $UpdatePath
            License              = $ConfigurationData.NonNodeData.Sense.License
            PSDscRunasCredential = $QlikAdmin
            DependsOn            = "[Group]Administrators"
        }
    }
}
