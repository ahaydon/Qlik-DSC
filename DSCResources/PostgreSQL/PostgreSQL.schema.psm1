Configuration PostgreSQL
{
  param (
    [int] $Port = 4432,
    [string] $ServiceName = "QlikSenseRepositoryDatabase",
    [string] $Path = "$($env:ProgramData)\Qlik\Sense\Repository\PostgreSQL\9.3",
    [string[]] $HostAccess,
    [string] $ListenAddresses
  )
  Import-DSCResource -ModuleName xPSDesiredStateConfiguration,xNetworking

  xFirewall QRD-postgresql
  {
    Name                  = "QRD-Postgresql"
    DisplayName           = "Qlik Sense Repository Database"
    Group                 = "Qlik Sense"
    Ensure                = "Present"
    Action                = "Allow"
    Enabled               = "True"
    Profile               = ("Domain", "Private", "Public")
    Direction             = "InBound"
    LocalPort             = ($Port)
    Protocol              = "TCP"
  }

  foreach ($address in $HostAccess)
  {
    LineInFile "pg_hba_$address"
    {
      Ensure = "Present"
      Path   = "$Path\pg_hba.conf"
      Line   = "host    all             all             $address              md5"
    }
  }

  if ($ListenAddresses)
  {
    LineInFile postgresql
    {
      Ensure       = "Present"
      Path         = "$Path\postgresql.conf"
      Line         = "listen_addresses = '$ListenAddresses'"
      InsertBefore = "#listen_addresses = 'localhost'"
    }
  }

  xService QRD
  {
    Name  = $ServiceName
    State = "Running"
  }
}
