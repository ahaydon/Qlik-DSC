Configuration QlikCommon
{
  param (
  )
  Import-DSCResource -ModuleName xPSDesiredStateConfiguration,xNetworking,QlikResources

  xFirewall QRS-Sync
  {
    Name                  = "QRS-Sync"
    DisplayName           = "Qlik Sense Repository Replication"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("4241")
    Protocol              = "TCP"
  }

  xFirewall QRS-ws
  {
    Name                  = "QRS-WebSocket"
    DisplayName           = "Qlik Sense Repository Service (WebSocket)"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("4239")
    Protocol              = "TCP"
  }

  xFirewall QRS-rest
  {
    Name                  = "QRS"
    DisplayName           = "Qlik Sense Repository Service (REST)"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("4242")
    Protocol              = "TCP"
  }

  xService QRD
  {
    Name = "QlikSenseRepositoryDatabase"
    State = "Running"
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

  xService QSD
  {
    Name = "QlikSenseServiceDispatcher"
    State = "Running"
    DependsOn = "[xService]QRS"
  }

  if (Get-Service QlikSenseSchedulerService -ErrorAction Ignore) {
    xFirewall QSS-Slave
    {
      Name                  = "QSS-Slave"
      DisplayName           = "Qlik Sense Scheduler Slave"
      Group                 = "Qlik Sense"
      Ensure                = "Present"
      Action                = "Allow"
      Enabled               = "True"
      Profile               = ("Domain", "Private", "Public")
      Direction             = "InBound"
      LocalPort             = ("5151")
      Protocol              = "TCP"
    }

    xService QSS
    {
      Name = "QlikSenseSchedulerService"
      State = "Running"
      DependsOn = "[xService]QRS"
    }
  }

  if (Get-Service QlikSenseEngineService -ErrorAction Ignore) {
    xFirewall QES
    {
      Name                  = "QES"
      DisplayName           = "Qlik Sense Engine"
      Group                 = "Qlik Sense"
      Ensure                = "Present"
      Action                = "Allow"
      Enabled               = "True"
      Profile               = ("Domain", "Private", "Public")
      Direction             = "InBound"
      LocalPort             = ("4747")
      Protocol              = "TCP"
    }

    xService QES
    {
      Name = "QlikSenseEngineService"
      State = "Running"
      DependsOn = "[xService]QRS"
    }
  }

  if (Get-Service QlikSenseProxyService -ErrorAction Ignore) {
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

    xFirewall QPS-API
    {
      Name                  = "QPS-API"
      DisplayName           = "Qlik Sense Proxy API"
      Group                 = "Qlik Sense"
      Ensure                = "Present"
      Action                = "Allow"
      Enabled               = "True"
      Profile               = ("Domain", "Private", "Public")
      Direction             = "InBound"
      LocalPort             = ("4243")
      Protocol              = "TCP"
    }

    xService QPS
    {
      Name = "QlikSenseProxyService"
      State = "Running"
      DependsOn = "[xService]QRS"
    }
  }
}
