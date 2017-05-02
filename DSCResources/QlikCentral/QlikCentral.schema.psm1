Configuration QlikCentral
{
  param (
    [PSObject]$License,
    [bool]$ApplyCommon = $true
  )
  Import-DSCResource -ModuleName xNetworking,xSmbShare,QlikResources

  if ($ApplyCommon) {
    QlikCommon Common
    {}
  }

  QlikLicense SiteLicense
  {
    Serial       = $License.Serial
    Control      = $License.Control
    Name         = $License.Name
    Organization = $License.Organization
    Lef          = $License.Lef
    Ensure       = "Present"
  }

  #QlikCustomProperty Role
  #{
  #  Name         = "Role"
  #  ChoiceValues = "Proxy", "Engine", "Scheduler"
  #  ObjectTypes  = "ServerNodeConfiguration"
  #  Ensure       = "Present"
  #  DependsOn    = "[QlikLicense]SiteLicense"
  #}

  #if (Connect-Qlik -ErrorAction SilentlyContinue) {
  #  QlikCustomProperty NodeAffinity
  #  {
  #    Name = "NodeAffinity"
  #    ChoiceValues = @(Get-QlikNode -filter "@Role eq 'engine'" | foreach { $_.hostName })
  #    ObjectTypes = ("App", "Stream")
  #    Ensure = "Present"
  #    DependsOn = "[QlikLicense]SiteLicense"
  #  }
  #
  #  if( (Get-QlikNode -filter "schedulerEnabled eq true" -count).value -gt 1 -And (Get-QlikNode -filter "isCentral eq true and @role eq scheduler") -eq $null ) {
  #    QlikScheduler Central
  #    {
  #      Node = "Central"
  #      SchedulerServiceType = "Master"
  #      DependsOn = "[QlikDataConnection]ServerLogFolder", "[QlikDataConnection]ArchivedLogsFolder"
  #    }
  #  } else {
  #    QlikScheduler Central
  #    {
  #      Node = "Central"
  #      SchedulerServiceType = "Both"
  #    }
  #  }
  #}

  #QlikDataConnection ServerLogFolder
  #{
  #  Name = "ServerLogFolder"
  #  ConnectionString = "\\$CentralNode\QlikLog"
  #  Type = "Folder"
  #  Ensure = "Present"
  #  DependsOn = "[xSmbShare]QlikLog", "[QlikLicense]SiteLicense"
  #}
  #
  #QlikDataConnection ArchivedLogsFolder
  #{
  #  Name = "ArchivedLogsFolder"
  #  ConnectionString = "\\$CentralNode\QlikArchiveLog"
  #  Type = "Folder"
  #  Ensure = "Present"
  #  DependsOn = "[xSmbShare]QlikArchiveLog", "[QlikLicense]SiteLicense"
  #}

  #QlikRule ResourcesOnNonCentralNodes
  #{
  #  Name = "ResourcesOnNonCentralNodes"
  #  Disabled = $true
  #  Ensure = "Present"
  #  #DependsOn = "[QlikDataConnection]ServerLogFolder", "[QlikDataConnection]ArchivedLogsFolder"
  #}

  #QlikRule ResourcesOnSchedulers
  #{
  #  Name = "ResourcesOnSchedulers"
  #  Category = "sync"
  #  Rule = '((node.@Role="Scheduler"))'
  #  ResourceFilter = "App_*"
  #  Ensure = "Present"
  #  DependsOn = "[QlikCustomProperty]Role"
  #}

  #QlikRule ResourceNodeAffinity
  #{
  #  Name = "ResourceNodeAffinity"
  #  Category = "sync"
  #  Actions = 1
  #  Rule = '((resource.@NodeAffinity=node.name or resource.stream.@NodeAffinity=node.name) or (resource.@NodeAffinity.Empty() and resource.stream.@NodeAffinity.Empty()))'
  #  ResourceFilter = "App_*"
  #  Ensure = "Present"
  #  DependsOn = "[QlikCustomProperty]NodeAffinity"
  #}

  QlikRule RootAccess
  {
    Name = "License rule to grant RootAdmin access"
    Rule = '((user.roles="RootAdmin"))'
    Category = "license"
    Actions = 1
    Comment = "Rule to setup automatic user access"
    #RuleContext = "hub"
    Ensure = "Present"
    DependsOn = "[QlikLicense]SiteLicense"
  }

  #xSmbShare QlikLog
  #{
  #  Ensure = "Present"
  #  Name   = "QlikLog"
  #  Path = "C:\ProgramData\Qlik\Sense\Log"
  #  FullAccess = "Administrators"
  #  Description = "Qlik Sense Scheduler access to central logs"
  #}
  #
  #xSmbShare QlikArchiveLog
  #{
  #  Ensure = "Present"
  #  Name   = "QlikArchiveLog"
  #  Path = "C:\ProgramData\Qlik\Sense\Repository\Archived Logs"
  #  FullAccess = "Administrators"
  #  Description = "Qlik Sense Scheduler access to archived logs"
  #}

  xFirewall QSS-Master
  {
    Name                  = "QSS-Master"
    DisplayName           = "Qlik Sense Scheduler Master"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ("5050")
    Protocol              = "TCP"
  }
}
