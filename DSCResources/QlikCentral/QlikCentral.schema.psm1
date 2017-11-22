Configuration QlikCentral
{
  Param (
      [PSCredential] $SenseService,
      [PSCredential] $QlikAdmin,
      [string] $ProductName,
      [string] $SetupPath,
      [string] $PatchPath,
      [string] $ClusterPath = 'C:\QlikShare',
      [string] $ClusterShareName = 'QlikShare',
      [string] $ClusterShareHost = $(hostname),
      [PSCredential] $DbSuperUserPassword,
      [PSCredential] $DbCredential,
      [PSObject] $License,
      [string] $Hostname = $(hostname)
  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration, xNetworking, xPSDesiredStateConfiguration, xSmbShare

  if (-Not $DbCredential) {
    $DbCredential = New-Object System.Management.Automation.PSCredential('qliksenserepository', $SenseService.GetNetworkCredential().SecurePassword)
  }

  if (-Not $DbSuperUserPassword) { $DbSuperUserPassword = $SenseService }

  File QlikClusterRoot
  {
      Type = 'Directory'
      DestinationPath = $ClusterPath
      Ensure = 'Present'
  }

  xSmbShare QlikClusterShare
  {
      Path = $ClusterPath
      Name = $ClusterShareName
      FullAccess = $SenseService.GetNetworkCredential().UserName
      Ensure = 'Present'
      DependsOn = '[File]QlikClusterRoot'
  }

  QlikPackage Sense_Setup
  {
      Name = $ProductName
      #ProductId = '{0c721ce8-57a8-4fef-9edb-a301370fad93}'
      Setup = $SetupPath
      Patch = $PatchPath
      PsDscRunAsCredential = $SenseService
      ServiceCredential = $SenseService
      RootDir = "\\$ClusterShareHost\$ClusterShareName"
      DbSuperUserPassword = $DbSuperUserPassword
      DbCredential = $DbCredential
      CreateCluster = $true
      InstallLocalDb = $true
      Hostname = $Hostname
      Ensure = 'Present'
      DependsOn = '[xSmbShare]QlikClusterShare'
  }

  xService QRD
  {
    Name = "QlikSenseRepositoryDatabase"
    State = "Running"
    DependsOn = "[QlikPackage]Sense_Setup"
  }

  xService QRS
  {
    Name = "QlikSenseRepositoryService"
    State = "Running"
    DependsOn = "[xService]QRD"
  }

  xService QPR
  {
    Name = "QlikSensePrintingService"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  xService QSS
  {
    Name = "QlikSenseSchedulerService"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  xService QES
  {
    Name = "QlikSenseEngineService"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  xService QPS
  {
    Name = "QlikSenseProxyService"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  xService QSD
  {
    Name = "QlikSenseServiceDispatcher"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  QlikConnect SenseCentral
  {
    Username      = "$Hostname\vagrant"
    DependsOn     = "[xService]QPS"
  }

  QlikLicense SiteLicense
  {
    Serial       = $License.Serial
    Control      = $License.Control
    Name         = $License.Name
    Organization = $License.Organization
    Lef          = $License.Lef
    Ensure       = "Present"
    DependsOn    = "[QlikConnect]SenseCentral"
  }

  QlikUser RootAdmin
  {
    UserID = $QlikAdmin.GetNetworkCredential().UserName
    UserDirectory = $QlikAdmin.GetNetworkCredential().Domain
    Name = 'Qlik Sense Root Admin'
    Roles = 'RootAdmin'
    Ensure = 'Present'
  }

  xFirewall QPS
  {
    Name                  = "QPS"
    DisplayName           = "Qlik Sense Proxy HTTPS"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("443")
    Protocol              = "TCP"
  }

  xFirewall QPS-Auth
  {
    Name                  = "QPS-Auth"
    DisplayName           = "Qlik Sense Proxy Authentication HTTPS"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("4244")
    Protocol              = "TCP"
  }
}
