Configuration SharedPersist
{
  param (
    [string] $SharedRoot,
    [string] $SenseInstallPath = "$($env:ProgramFiles)\Qlik\Sense",
    [string] $DBHost,
    [int] $DBPort = 4432,
    [PSCredential] $DBPassword
  )
  Import-DSCResource -ModuleName xNetworking,xSmbShare

  if ($IsCentral)
  {
    if (Test-Path "$($env:ProgramData)\Qlik\Sense\Apps") {
      File SharedApps
      {
        Ensure = "Present"
        Type = "Directory"
        SourcePath = "$($env:ProgramData)\Qlik\Sense\SharedPersistence\Apps"
        DestinationPath = "$SharedRoot\Apps"
        Recurse = $true
      }
    }

    #File CustomData
    #{
    #  Ensure = "Present"
    #  Type = "Directory"
    #  SourcePath = "$($env:ProgramData)\Qlik\Sense\Custom Data"
    #  DestinationPath = "$SharedRoot\Custom Data"
    #}

    File Connectors
    {
      Ensure = "Present"
      Type = "Directory"
      SourcePath = "$($env:ProgramFiles)\Common Files\Qlik\Custom Data"
      DestinationPath = "$SharedRoot\Custom Data"
      Recurse = $true
    }

    if (Test-Path "$($env:ProgramData)\Qlik\Sense\Repository\AppContent") {
      File AppContent
      {
        Ensure = "Present"
        Type = "Directory"
        SourcePath = "$($env:ProgramData)\Qlik\Sense\Repository\AppContent"
        DestinationPath = "$SharedRoot\StaticContent\AppContent"
        Recurse = $true
      }
    }

    if (Test-Path "$($env:ProgramData)\Qlik\Sense\Repository\Content") {
      File Content
      {
        Ensure = "Present"
        Type = "Directory"
        SourcePath = "$($env:ProgramData)\Qlik\Sense\Repository\Content"
        DestinationPath = "$SharedRoot\StaticContent\Content"
        Recurse = $true
      }
    }

    File DefaultContent
    {
      Ensure = "Present"
      Type = "Directory"
      SourcePath = "$($env:ProgramData)\Qlik\Sense\Repository\DefaultContent"
      DestinationPath = "$SharedRoot\StaticContent\DefaultContent"
      Recurse = $true
    }

    if (Test-Path "$($env:ProgramData)\Qlik\Sense\Repository\Extensions") {
      File Extensions
      {
        Ensure = "Present"
        Type = "Directory"
        SourcePath = "$($env:ProgramData)\Qlik\Sense\Repository\Extensions"
        DestinationPath = "$SharedRoot\StaticContent\Extensions"
        Recurse = $true
      }
    }

    if (Test-Path "$($env:ProgramData)\Qlik\Sense\Repository\Archived Logs") {
      File ArchivedLogs
      {
        Ensure = "Present"
        Type = "Directory"
        SourcePath = "$($env:ProgramData)\Qlik\Sense\Repository\Archived Logs"
        DestinationPath = "$SharedRoot\ArchivedLogs"
        Recurse = $true
      }
    }
  }

  ConfigFile repository
  {
    Ensure = "Present"
    configPath = "$SenseInstallPath\Repository\Repository.exe.config"
    appSettings = @{
      SharedPersistence = 'true'
    }
  }

  EncryptConfig repository
  {
    exePath = "$SenseInstallPath\Repository\Repository.exe"
    configSection = "connectionStrings"
    connectionString = "User ID=postgres;Host=$DBHost;Password=$($DBPassword.GetNetworkCredential().Password);Port=$DBPort;Database=QSR;Pooling=true;Min Pool Size=0;Max Pool Size=90;Connection Lifetime=3600;Unicode=true;"
    Ensure = "Present"
  }
}
