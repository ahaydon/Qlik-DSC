Configuration FileServer
{
  param (
    [string] $SharedRoot = "C:\QlikShare",
    [string] $ShareName = "QlikShare"
  )
  Import-DSCResource -ModuleName xSmbShare

  File QlikShare
  {
    Ensure = "Present"
    Type = "Directory"
    DestinationPath = $SharedRoot
  }

  xSmbShare QlikShare
  {
    Ensure = "Present"
    Name   = $ShareName
    Path = $SharedRoot
    FullAccess = "Everyone"
    DependsOn = "[File]QlikShare"
  }
}
