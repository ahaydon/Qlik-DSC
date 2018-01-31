Configuration QlikRimNode
{
  param (
    [PSCredential] $SenseService,
    [PSCredential] $QlikAdmin,
    [string] $ProductName,
    [string] $SetupPath,
    [string] $PatchPath,
    [string] $DbHost,
    [PSCredential] $DbCredential,
    [string] $Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname,
    [bool]$ConfigureLogging = $true,
    [PSCredential]$QLogsWriterPassword,
    [PSCredential]$QLogsReaderPassword,
    [string]$QLogsHostname,
    [int]$QLogsPort = 4432,
    [bool] $Engine,
    [bool] $Printing,
    [bool] $Proxy,
    [bool] $Scheduler,
    [bool] $ApplyCommon,
    [string] $CentralNode
  )

  Import-DscResource -ModuleName PSDesiredStateConfiguration, QlikResources, xNetworking, xPSDesiredStateConfiguration

  if (-Not $DbCredential) {
    $DbCredential = New-Object System.Management.Automation.PSCredential('qliksenserepository', $SenseService.GetNetworkCredential().SecurePassword)
  }
  if (-Not $QLogsWriterPassword) {
    $QLogsWriterPassword = $SenseService
  }
  if (-Not $QLogsReaderPassword) {
    $QLogsReaderPassword = $SenseService
  }
  if (-Not $DbHost) {
    $DbHost = $CentralNode
  }
  if (-Not $QLogsHostname) {
    $QLogsHostname = $DbHost
  }
  if (-Not $QlikAdmin) {
    $QlikAdmin = $SenseService
  }

  QlikPackage Sense_Setup
  {
      Name = $ProductName
      Setup = $SetupPath
      Patch = $PatchPath
      #PsDscRunAsCredential = $SenseService
      ServiceCredential = $SenseService
      DbCredential = $DbCredential
      DbHost = $DbHost
      Hostname = $Hostname
      JoinCluster = $true
      ConfigureLogging = $ConfigureLogging
      QLogsWriterPassword = $QLogsWriterPassword
      QLogsReaderPassword = $QLogsReaderPassword
      QLogsHostname = $QLogsHostname
      QLogsPort = $QLogsPort
      Ensure = 'Present'
  }

  xFirewall Qlik-Cert
  {
    Name                  = "Qlik-Cert"
    DisplayName           = "Qlik Sense Certificate Distribution"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("4444")
    Protocol              = "TCP"
  }

  xFirewall QRS
  {
      Name                  = "QRS"
      DisplayName           = "Qlik Sense Repository Service"
      Group                 = "Qlik Sense"
      Ensure                = "Present"
      Action                = "Allow"
      Enabled               = "True"
      Profile               = ("Domain", "Private", "Public")
      Direction             = "InBound"
      LocalPort             = ("4242")
      Protocol              = "TCP"
  }

  xService QRS
  {
    Name = "QlikSenseRepositoryService"
    State = "Running"
    DependsOn = "[QlikPackage]Sense_Setup"
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
    Computername  = $CentralNode
    Username      = $QlikAdmin.UserName
    TrustAllCerts = $true
    DependsOn     = "[xService]QPS"
  }

  QlikNode $(hostname)
  {
    Ensure    = "Present"
    HostName  = $(hostname)
    Engine    = $Engine
    Printing  = $Printing
    Proxy     = $Proxy
    Scheduler = $Scheduler
    DependsOn = "[xFirewall]Qlik-Cert", "[QlikConnect]SenseCentral"
  }
}
