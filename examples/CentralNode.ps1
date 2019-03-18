$configData = @{
    AllNodes = @(@{
        NodeName = 'localhost'
        PSDscAllowPlainTextPassword = $true
    })
}

$password = ConvertTo-SecureString -String 'Qlik1234!' -AsPlainText -Force
$SenseService = New-Object System.Management.Automation.PSCredential("$env:computername\qservice", $password)
$QlikAdmin = New-Object System.Management.Automation.PSCredential("$env:computername\qlik", $password)

Configuration QlikConfig
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration, QlikResources

    Node localhost
    {
        User QlikAdmin
        {
            UserName               = $QlikAdmin.GetNetworkCredential().UserName
            Password               = $QlikAdmin
            FullName               = 'Qlik User'
            PasswordChangeRequired = $false
            PasswordNeverExpires   = $true
            Ensure                 = 'Present'
            DependsOn              = "[Windows]local"
        }

        User SenseService
        {
            UserName                 = $SenseService.GetNetworkCredential().UserName
            Password                 = $SenseService
            FullName                 = 'Qlik Sense Service Account'
            PasswordChangeNotAllowed = $true
            PasswordChangeRequired   = $false
            PasswordNeverExpires     = $true
            Ensure                   = 'Present'
            DependsOn                = "[Windows]local"
        }

        Group Administrators
        {
            GroupName        = 'Administrators'
            MembersToInclude = $QlikAdmin.GetNetworkCredential().UserName, $SenseService.GetNetworkCredential().UserName
            DependsOn        = "[User]QlikAdmin", "[User]SenseService"
        }

        QlikCentral CentralNode
        {
            SenseService         = $SenseService
            QlikAdmin            = $QlikAdmin
            ProductName          = 'Qlik Sense June 2018'
            SetupPath            = 'C:\Install\Qlik_Sense_setup.exe'
            License              = @{
              Serial       = '1234567890'
              Control      = '12345'
              Name         = 'User'
              Organization = 'Organization'
            }
            PSDscRunasCredential = $QlikAdmin
            DependsOn            = "[Group]Administrators"
        }

        QlikVirtualProxy SAML
        {
          Prefix = "saml"
          Description = "SAML"
          SessionCookieHeaderName = "X-Qlik-Session-SAML"
          LoadBalancingServerNodes = "name eq 'Central'"
          AuthenticationMethod = "saml"
          SamlMetadataIdp = (Get-Content -raw c:\install\idp-metadata.xml)
          SamlHostUri = "https://$($env:computername)"
          SamlEntityId = "https://$($env:computername)/saml"
          SamlAttributeUserId = "uid"
          SamlAttributeUserDirectory = "[SAML]"
          SamlAttributeMapMandatory = @{
            mail = 'email'
          }
          samlSlo = $true
          SamlMetadataExportPath = "c:\install\saml_metadata_sp.xml"
          Proxy = $env:computername
          PSDscRunasCredential = $QlikAdmin
          Ensure = "Present"
        }
    }
}

QlikConfig -ConfigurationData $configData
Start-DscConfiguration -Path .\QlikConfig -Wait -Verbose -Force
