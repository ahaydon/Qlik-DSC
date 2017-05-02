Configuration QlikAppTemplate
{
  param (
      [string] $AppFile,
      [string] $ReduceValuesFile,
      [string] $AppName = "$((Get-Item $AppFile).BaseName) - {0}",
      [string] $Stream,
      [string] $DataLoaderAppFile,
      [string] $DataLoaderTaskName,
      [bool]   $CreateTask,
      [string] $TemplatePropertyName = "TemplateName",
      [string] $TemplateHashPropertyName = "TemplateHash",
      [string] $ReduceValuePropertyName = "ReduceValue"
  )
  Import-DSCResource -ModuleName QlikResources

  #QlikCustomProperty "$TemplatePropertyName-$AppName-$Stream"
  #{
  #  Name = $TemplatePropertyName
  #  ObjectTypes = ("App")
  #  Ensure = "Present"
  #}
  #
  #QlikCustomProperty "$TemplateHashPropertyName-$AppName-$Stream"
  #{
  #  Name = $TemplateHashPropertyName
  #  ObjectTypes = ("App")
  #  Ensure = "Present"
  #}
  #
  #QlikCustomProperty "$ReduceValuePropertyName-$AppName-$Stream"
  #{
  #  Name = $ReduceValuePropertyName
  #  ObjectTypes = ("App")
  #  Ensure = "Present"
  #}
  #
  #if ($DataLoaderAppFile)
  #{
  #    $name = (Get-Item $DataLoaderAppFile).BaseName
  #    QlikApp $name
  #    {
  #      Name = $name
  #      Stream = "."
  #      Source = $DataLoaderAppFile
  #      CustomProperties = @{
  #        $TemplatePropertyName = (Get-Item $DataLoaderAppFile).FullName
  #        $TemplateHashPropertyName = (Get-FileHash -Algorithm MD5 $DataLoaderAppFile).Hash
  #      }
  #      Ensure = "Present"
  #    }
  #
  #    QlikTask $name
  #    {
  #      Name = $name
  #      App = $name
  #      StartOn = "Create"
  #      WaitUntilFinished = $true
  #      Ensure = "Present"
  #      DependsOn = "[QlikApp]$name"
  #    }
  #}

  Write-Verbose "Reading values from file $ReduceValuesFile"
  $values = Get-Content $ReduceValuesFile | select -skip 1

  # Remove templated apps with reduce values not listed in the data file
  if (Connect-Qlik -ErrorAction SilentlyContinue) {
    Write-Verbose "name eq $ReduceValuePropertyName"
    $cp = (Get-QlikCustomProperty -filter "name eq '$ReduceValuePropertyName'").id
    Write-Verbose "@$TemplatePropertyName eq '$AppFile'"
    $template = $AppFile -replace '\\', '\\'
    foreach ($app in (Get-QlikApp -filter "@$TemplatePropertyName eq '$template'" -full -verbose))
    {
      if ($values -NotContains ($app.customProperties | where {$_.definition.id -eq $cp}).value) {
        QlikApp $app.id
        {
          Name = $app.name
          Stream = $(if ($app.stream) {$app.stream.name} else {"."})
          Ensure = "Absent"
        }
      }
    }
  }

  foreach ($ReduceValue in $values)
  {
      $streamname = $Stream -f $ReduceValue
      $name = $AppName -f $ReduceValue

      if ($Stream)
      {
          QlikStream "$name$streamname"
          {
            Name = $streamname
            Ensure = "Present"
          }
      }

    QlikApp "$name$streamname"
    {
        Name = $name
        Source = $AppFile
        Stream = $streamname
        ReloadOn = $(if ($CreateTask -Or $DataLoaderTaskName) {"Update"} else {"Create"})
        CustomProperties = @{
          $TemplatePropertyName = $AppFile
          $TemplateHashPropertyName = (Get-FileHash -Algorithm MD5 $AppFile).Hash
          $ReduceValuePropertyName = $ReduceValue
        }
        Ensure = "Present"
    }

    if ($CreateTask -Or $DataLoaderTaskName)
    {
        Write-Verbose "name eq '$DataLoaderTaskName'"
        QlikTask "Reload of $name$streamname"
        {
          Name = "Reload of $name$streamname"
          App = "$name"
          Stream = "$streamname"
          OnSuccess = (Get-QlikTask -filter "name eq '$DataLoaderTaskName'" -raw).id
          StartOn = "Create"
          Ensure = "Present"
          DependsOn = "[QlikApp]$name$streamname"
        }
    }
  }
}
