Configuration QlikRimNode
{
  param (
      [bool] $Engine = [bool](Get-Service QlikSenseEngineService -ErrorAction Ignore),
      [bool] $Printing = [bool](Get-Service QlikSensePrintingService -ErrorAction Ignore),
      [bool] $Proxy = [bool](Get-Service QlikSenseProxyService -ErrorAction Ignore),
      [bool] $Scheduler = [bool](Get-Service QlikSenseSchedulerService -ErrorAction Ignore),
      [bool]$ApplyCommon
  )
  Import-DSCResource -ModuleName xNetworking

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

  if ($ApplyCommon) {
    QlikCommon Common
    {}
  }

  QlikNode $(hostname)
  {
    Ensure    = "Present"
    HostName  = $(hostname)
    Engine    = $Engine
    Printing  = $Printing
    Proxy     = $Proxy
    Scheduler = $Scheduler
    DependsOn = "[xFirewall]Qlik-Cert"
  }
}
