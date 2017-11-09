enum Ensure
{
  Absent
  Present
}

enum ReloadOn
{
  None
  Create
  Update
}

[DscResource()]
class QlikApp{

  [DscProperty()]
  [string]$Id

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [string]$Source

  [DscProperty()]
  [hashtable]$CustomProperties

  [DscProperty()]
  [string[]]$Tags

  [DscProperty(Key)]
  [string]$Stream

  [DscProperty()]
  [ReloadOn]$ReloadOn

  [DscProperty()]
  [bool]$Force

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = Get-QlikApp -raw -full -filter "name eq '$($this.name)' and (stream.name eq '$($this.Stream)' or stream eq null)"
    if(@($item).count -gt 1)
    {
        $item = $item | ? stream -eq $this.Stream
    }
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        Write-Verbose "App not found but should be present"
        Write-Verbose -Message "Importing app from $($this.Source)"
        $item = Import-QlikApp -file $this.Source -name $this.Name -upload
        if ($this.ReloadOn -eq [ReloadOn]::Create)
        {
          Write-Verbose "Reloading app since ReloadOn is set to $($this.ReloadOn)"
          Invoke-QlikPost /qrs/app/$($item.id)/reload
        }
      }
      else #if ($this.Force)
      {
        Write-Verbose "Updating app with ID $($item.id)"
        Write-Verbose -Message "Importing app from $($this.Source)"
        $replace = Import-QlikApp -file $this.Source -name $this.Name -upload
        if ($this.ReloadOn -eq [ReloadOn]::Update)
        {
          Write-Verbose "Reloading app since ReloadOn is set to $($this.ReloadOn)"
        #  if (($this.Stream -ne ".") -And ($this.Stream -ne $item.stream.name))
        #  {
        #    Publish-QlikApp -id $replace.id -stream $item.stream.id
        #  }
          $this.configure($replace)
          Invoke-QlikPost /qrs/app/$($replace.id)/reload
          $task = Get-QlikReloadTask -filter "app.id eq $($replace.id)"
          Start-QlikTask -wait $task.id
          Wait-QlikExecution -taskId $task.id
        }
        Switch-QlikApp -id $replace.id -appId $item.id
        Remove-QlikApp -id $replace.id
      }
    #  $props = @()
    #  foreach ($prop in $this.CustomProperties.Keys)
    #  {
    #    $cp = Get-QlikCustomProperty -filter "name eq '$prop'" -raw
    #    if (-Not ($cp.choiceValues -contains $this.CustomProperties.$prop))
    #    {
    #      $cp.choiceValues += $this.CustomProperties.$prop
    #      Write-Verbose -Message "Updating property $prop with new value of $($this.CustomProperties.$prop)"
    #      Update-QlikCustomProperty -id $cp.id -choiceValues $cp.choiceValues
    #    }
    #    $props += "$($prop)=$($this.CustomProperties.$prop)"
    #  }
    #  $appTags = @()
    #  foreach ($tag in $this.Tags)
    #  {
    #    $tagId = (Get-QlikTag -filter "name eq '$tag'").id
    #    if (-Not $tagId)
    #    {
    #      $tagId = (New-QlikTag -name $tag).id
    #      Write-Verbose "Created tag for $tag with id $tagId"
    #    }
    #    $appTags += $tag
    #  }
    #  Update-QlikApp -id $item.id -tags $appTags -customProperties $props
      $this.configure($item)
      if (($this.Stream -ne ".") -And ($this.Stream -ne $item.stream.name))
      {
        $streamId = (Get-QlikStream -filter "name eq '$($this.Stream)'" -raw).id
        Publish-QlikApp -id $item.id -stream $streamId
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting app $($item.name)"
        Remove-QlikApp -id $item.id
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikApp -raw -full -filter "name eq '$($this.name)' and (stream.name eq '$($this.Stream)' or stream eq null)"
    if(@($item).count -gt 1)
    {
      $item = $item | ? stream -eq $this.Stream
    }
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      if($present) {
        Write-Verbose "App exists but should be absent"
        return $false
      }
      else
      {
        Write-Verbose "App should be absent and was not found"
        return $true
      }
    }
  }

  [QlikApp] Get()
  {
    $item = Get-QlikApp -raw -full -filter "name eq '$($this.name)' and (stream.name eq '$($this.Stream)' or stream eq null)"
    if(@($item).count -gt 1)
    {
      $item = $item | ? stream -eq $this.Stream
    }
    $present = $item -ne $null

    if ($present)
    {
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [void] configure($item)
  {
      $props = @()
      foreach ($prop in $this.CustomProperties.Keys)
      {
        $cp = Get-QlikCustomProperty -filter "name eq '$prop'" -raw
        if (-Not ($cp.choiceValues -contains $this.CustomProperties.$prop))
        {
          $cp.choiceValues += $this.CustomProperties.$prop
          Write-Verbose -Message "Updating property $prop with new value of $($this.CustomProperties.$prop)"
          Update-QlikCustomProperty -id $cp.id -choiceValues $cp.choiceValues
        }
        $props += "$($prop)=$($this.CustomProperties.$prop)"
      }
      $appTags = @()
      foreach ($tag in $this.Tags)
      {
        $tagId = (Get-QlikTag -filter "name eq '$tag'").id
        if (-Not $tagId)
        {
          $tagId = (New-QlikTag -name $tag).id
          Write-Verbose "Created tag for $tag with id $tagId"
        }
        $appTags += $tag
      }
      Update-QlikApp -id $item.id -tags $appTags -customProperties $props
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'Name' ) ) )
    {
      return $false
    }

    if ($this.Tags)
    {
      foreach ($tag in $this.Tags)
      {
        if (-Not ($item.tags.name -contains $tag))
        {
          Write-Verbose "Not tagged with $tag"
          return $false
        }
      }
    }

    if ($this.CustomProperties)
    {
      foreach ($prop in $this.CustomProperties.Keys)
      {
        $cp = $item.customProperties | where {$_.definition.name -eq $prop}
        if (-Not (($cp) -And ($cp.value -eq $this.CustomProperties.$prop)))
        {
          Write-Verbose "Property $prop should have value $($this.CustomProperties.$prop) but instead has value $($cp.value)"
          return $false
        }
      }
    }

    if (($this.Stream -ne $item.stream.name) -And ($this.Stream -ne "."))
    {
      return $false
    }

    return $true
  }
}

[DscResource()]
class QlikExtension{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [string]$Source

  [DscProperty()]
  [hashtable]$CustomProperties

  [DscProperty()]
  [string[]]$Tags

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = Get-QlikExtension -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        Write-Verbose "Extension not found but should be present"
        Write-Verbose -Message "Importing extension from $($this.Source)"
        Import-QlikExtension -ExtensionPath "$($this.Source)"
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting extension $($item.name)"
        Remove-QlikExtension -id $item.id
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikExtension -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        Write-Verbose "App is already present"
        return $true
      } else {
        Write-Verbose "App should be present but was not found"
        return $false
      }
    }
    else
    {
      if($present) {
        Write-Verbose "App exists but should be absent"
        return $false
      }
      else
      {
        Write-Verbose "App should be absent and was not found"
        return $true
      }
    }
  }

  [QlikExtension] Get()
  {
    $item = Get-QlikExtension -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }
}

[DscResource()]
class QlikConnect{

  [DscProperty(Key)]
  [string]$Username

  [DscProperty()]
  [string]$Computername

  [DscProperty()]
  [string]$Certificate
  #[System.Security.Cryptography.X509Certificates.X509Certificate]$Certificate

  [DscProperty()]
  [bool]$TrustAllCerts

  [DscProperty()]
  [int]$MaxRetries = 10

  [DscProperty()]
  [int]$RetryDelay = 10

  [void] Set()
  {
    $cert = gci $this.Certificate
    $params = @{ Username=$this.Username }
    if( $this.Computername ) { $params.Add( "Computername", $this.Computername ) }
    if( $this.Certificate ) { $params.Add( "Certificate", $cert ) }
    if( $this.TrustAllCerts ) { $params.Add( "TrustAllCerts", $true ) }
    #Connect-Qlik @params -TrustAllCerts
    $err = $null
    for ($i = 1; $i -lt $this.MaxRetries; $i++) {
      Write-Progress "Connecting to Qlik, attempt $i"
      try {
        if (Connect-Qlik -ErrorAction Ignore -ErrorVariable err @params) {
          break
        }
      } catch {
        Start-Sleep $this.RetryDelay
      }
    }
    if ($err) {
      throw $err
    }
  }

  [bool] Test()
  {
    return $false
  }

  [QlikConnect] Get()
  {
    $this.Username = $env:Username
    $this.Computername = $env:Computername

    return $this
  }
}

[DscResource()]
class QlikCustomProperty{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [DscProperty()]
  [string]$ValueType

  [DscProperty()]
  [string[]]$ChoiceValues

  [DscProperty()]
  [string[]]$ObjectTypes

  [void] Set()
  {
    $item = Get-QlikCustomProperty -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null
    if($this.ensure -eq [Ensure]::Present)
    {
      $params = @{ "Name" = $this.Name }
      if($this.ValueType) { $params.Add("ValueType", $this.ValueType) }
      if($this.ChoiceValues) { $params.Add("ChoiceValues", $this.ChoiceValues) }
      if($this.ObjectTypes) { $params.Add("ObjectTypes", $this.ObjectTypes) }

      if($present)
      {
        if(-not $this.hasProperties($item))
        {
          Update-QlikCustomProperty -id $item.id @params
        }
      } else {
        New-QlikCustomProperty @params
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting the property $($this.name)"
        #Remove-QlikCustomProperty -Name $this.Name
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikCustomProperty -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      return -not $present
    }
  }

  [QlikCustomProperty] Get()
  {
    $item = Get-QlikCustomProperty -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.ValueType = $item.ValueType
      $this.ChoiceValues = $item.ChoiceValues
      $this.ObjectTypes = $item.ObjectTypes
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'ValueType' ) ) )
    {
      return $false
    }

    if($this.ChoiceValues) {
      if(@($this.ChoiceValues).Count -ne @($item.choiceValues).Count) {
        Write-Verbose "Test-HasProperties: ChoiceValues property count - $(@($item.choiceValues).Count) does not match desired state - $(@($this.ChoiceValues).Count)"
        return $false
      } else {
        foreach($value in $item.ChoiceValues) {
          if($this.choiceValues -notcontains $value) {
            Write-Verbose "Test-HasProperties: ChoiceValues property value - $($value) not found in desired state"
            return $false
          }
        }
      }
    }

    if($this.ObjectTypes) {
      if(@($this.ObjectTypes).Count -ne @($item.ObjectTypes).Count) {
        Write-Verbose "Test-HasProperties: ObjectTypes property count - $(@($item.ObjectTypes).Count) does not match desired state - $(@($this.ObjectTypes).Count)"
        return $false
      } else {
        foreach($value in $item.ObjectTypes) {
          if($this.ObjectTypes -notcontains $value) {
            Write-Verbose "Test-HasProperties: ObjectTypes property value - $($value) not found in desired state"
            return $false
          }
        }
      }
    }

    return $true
  }
}

[DscResource()]
class QlikDataConnection{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [DscProperty(Mandatory)]
  [string]$ConnectionString

  [DscProperty()]
  [string]$Tags

  [DscProperty(Mandatory)]
  [string]$Type

  [void] Set()
  {
    $item = Get-QlikDataConnection -raw -filter "name eq '$($this.name)'"
    $present = $item -ne $null
    if($this.ensure -eq [Ensure]::Present)
    {
      if(!$present)
      {
          $item = New-QlikDataConnection -Name $this.Name -ConnectionString $this.ConnectionString -Type $this.Type
      }
      $prop = ConfigurePropertiesAndTags($this)
      Update-QlikDataConnection -id $item.id -ConnectionString $this.ConnectionString -Tags $prop.tags
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting the file $($this.name)"
        #Remove-QlikDataConnection -Name $this.Name
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikDataConnection -raw -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      return -not $present
    }
  }

  [QlikDataConnection] Get()
  {
    $present = $(Get-QlikDataConnection -raw -filter "name eq '$($this.name)'") -ne $null

    if ($present)
    {
      $qdc = Get-QlikDataConnection -raw -filter "name eq '$this.name'"
      $this.ConnectionString = $qdc.ConnectionString
      $this.Type = $qdc.Type
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.CreationTime = $null
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'ConnectionString', 'Type' ) ) )
    {
      return $false
    }

    if ($this.Tags)
    {
      foreach ($tag in $this.Tags)
      {
        if (-Not ($item.tags.name -contains $tag))
        {
          Write-Verbose "Not tagged with $tag"
          return $false
        }
      }
    }

    return $true
  }
}

[DscResource()]
class QlikLicense{

  [DscProperty(Key)]
  [string]$Serial

  [DscProperty(Mandatory)]
  [string]$Control

  [DscProperty(Mandatory)]
  [string]$Name

  [DscProperty(Mandatory)]
  [string]$Organization

  [DscProperty(Mandatory)]
  [string]$Lef

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
      $license = $(Get-QlikLicense)
      if ($license) {
          $present = ($license.serial -eq $this.Serial)
      } else {
          $present = $false
      }
    Write-Debug $present
    if($this.ensure -eq [Ensure]::Present)
    {
      if(-not $present)
      {
          if ($license -ne 'null') {
              Invoke-QlikDelete "/qrs/license/$($license.id)"
          }
        Set-QlikLicense -Serial $this.Serial -Control $this.Control -Name $this.Name -Organization $this.Organization -Lef $this.Lef
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting license $($this.Serial)"
        Invoke-QlikDelete "/qrs/license/$($license.id)"
      }
    }
  }

  [bool] Test()
  {
    $license = $(Get-QlikLicense)
    if ($license) {
        $present = ($license.serial -eq $this.Serial)
    } else {
        $present = $false
    }
    Write-Debug $present
    if($this.Ensure -eq [Ensure]::Present)
    {
      return $present
    }
    else
    {
      return -not $present
    }
  }

  [QlikLicense] Get()
  {
    $present = $(Get-QlikLicense) -ne $null
    if ($present)
    {
      $license = Get-QlikLicense
      $this.Serial = $license.Serial
      $this.Name = $license.Name
      $this.Organization = $license.Organization
      $this.Lef = $license.Lef
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }
}

[DscResource()]
class QlikNode{

  [DscProperty(Key)]
  [string]$HostName

  [DscProperty()]
  [string]$Name

  [DscProperty()]
  [string]$NodePurpose

  [DscProperty()]
  [string[]]$CustomProperties

  [DscProperty()]
  [string[]]$Tags

  [DscProperty()]
  [bool]$Engine

  [DscProperty()]
  [bool]$Proxy

  [DscProperty()]
  [bool]$Scheduler

  [DscProperty()]
  [bool]$Printing

  [DscProperty()]
  [bool]$Failover

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = Get-QlikNode -raw -full -filter "hostName eq '$($this.HostName)'"
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      Write-Verbose "Proxy should be $($this.Proxy)"
      $params = @{}
      if($this.Name) { $params.Add("Name", $this.Name) }
      if($this.NodePurpose) { $params.Add("NodePurpose", $this.NodePurpose) }
      if($this.CustomProperties) { $params.Add("CustomProperties", $this.CustomProperties) }
      if($this.Tags) { $params.Add("Tags", $this.Tags) }
      if($this.Engine) { $params.Add("engineEnabled", $this.Engine) }
      if($this.Proxy) { $params.Add("proxyEnabled", $this.Proxy) }
      if($this.Scheduler) { $params.Add("schedulerEnabled", $this.Scheduler) }
      if($this.Printing) { $params.Add("printingEnabled", $this.Printing) }
      if($this.Failover) { $params.Add("failoverCandidate", $this.Failover) }

      if($present)
      {
        if(-not $this.hasProperties($item))
        {
          Update-QlikNode -id $item.id @params
        }
      }
      else
      {
        Register-QlikNode -hostName $this.HostName @params
      }
    }
    else
    {
      #Remove-QlikNode $this.id
    }
  }

  [bool] Test()
  {
    $item = Get-QlikNode -raw -full -filter "hostName eq '$($this.HostName)'"
    $present = $item -ne $null

    if($present) {
      if($this.hasProperties($item))
      {
        return $true
      } else {
        return $false
      }
    } else {
      return $false
    }
  }

  [QlikNode] Get()
  {
    $item = Get-QlikNode -raw -full -filter "hostName eq '$($this.HostName)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.NodePurpose = $item.NodePurpose
      $this.CustomProperties = $item.CustomProperties
      $this.Tags = $item.Tags
      $this.Engine = $item.EngineEnabled
      $this.Proxy = $item.ProxyEnabled
      $this.Scheduler = $item.SchedulerEnabled
      $this.Printing = $item.PrintingEnabled
      $this.Failover = $item.FailoverCandidate
    }
    else
    {
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'NodePurpose', 'Tags' ) ) )
    {
      return $false
    }

    If($this.CustomProperties) {
      foreach( $defined in $this.CustomProperties) {
        $val = $defined.Split("=")
        $found = $false
        foreach( $exists in $item.customProperties ) {
          if($exists.definition.name -eq $val[0]) {
            if($val[1] -eq "null" -Or $val[1] -ne $exists.value) {
              Write-Verbose "Test-HasProperties: Custom property value - $($val[0])=$($exists.value) does not match desired state - $($val[1])"
              return $false
            } else {
              $found = $true
            }
          }
        }
        if(-not $found) {
          return $false
        }
      }
    }

    If ($this.Engine) {
        If(!$item.EngineEnabled) {
          Write-Verbose "Test-HasProperties: Engine property value - $($item.EngineEnabled) does not match desired state - $($this.Engine)"
          return $false
        }
    }

    If ($this.Proxy) {
        If(!$item.ProxyEnabled) {
          Write-Verbose "Test-HasProperties: Proxy property value - $($item.ProxyEnabled) does not match desired state - $($this.Proxy)"
          return $false
        }
    }

    If ($this.Scheduler) {
        If(!$item.SchedulerEnabled) {
          Write-Verbose "Test-HasProperties: Scheduler property value - $($item.SchedulerEnabled) does not match desired state - $($this.Scheduler)"
          return $false
        }
    }

    If ($this.Printing) {
        If(!$item.PrintingEnabled) {
          Write-Verbose "Test-HasProperties: Printing property value - $($item.PrintingEnabled) does not match desired state - $($this.Printing)"
          return $false
        }
    }

    If ($this.Failover) {
        If(!$item.FailoverCandidate) {
          Write-Verbose "Test-HasProperties: Failover property value - $($item.FailoverCandidate) does not match desired state - $($this.Failover)"
          return $false
        }
    }

    return $true
  }
}

[DscResource()]
class QlikRule{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [DscProperty()]
  [string]$Category

  [DscProperty()]
  [string]$Rule

  [DscProperty()]
  [string]$ResourceFilter

  [DscProperty()]
  [ValidateSet("hub","qmc","both")]
  [string]$RuleContext

  [DscProperty()]
  [int]$Actions

  [DscProperty()]
  [string]$Comment

  [DscProperty()]
  [bool]$Disabled

  [void] Set()
  {
    $item = Get-QlikRule -raw -full -filter "name eq '$($this.Name)'"
    $present = $item -ne $null
    if($this.ensure -eq [Ensure]::Present)
    {
      $params = @{ "Name" = $this.Name }
      if($this.Category) { $params.Add("Category", $this.Category) }
      if($this.Rule) { $params.Add("Rule", $this.Rule) }
      if($this.ResourceFilter) { $params.Add("ResourceFilter", $this.ResourceFilter) }
      if($this.RuleContext) { $params.Add("RuleContext", $this.RuleContext) }
      if($this.Actions) { $params.Add("Actions", $this.Actions) }
      if($this.Comment) { $params.Add("Comment", $this.Comment) }
      if($this.Disabled) { $params.Add("Disabled", $this.Disabled) }

      if($present)
      {
        if(-not $this.hasProperties($item))
        {
          Update-QlikRule -id $item.id @params
        }
      } else {
        Write-Verbose "Rule $($this.Name) should be present but was not found"
        if($this.Category -eq "license" -And (-not $this.ResourceFilter)) {
          $group = New-QlikUserAccessGroup "License rule to grant user access"
          $params.Add("ResourceFilter", "License.UserAccessGroup_$($group.id)")
        }
        New-QlikRule @params
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting the rule $($this.Name)"
        #Remove-QlikRule -Name $this.Name
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikRule -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      return -not $present
    }
  }

  [QlikRule] Get()
  {
    $item = Get-QlikRule -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.Category = $item.Category
      $this.Rule = $item.Rule
      $this.ResourceFilter = $item.ResourceFilter
      $this.RuleContext = $item.RuleContext
      $this.Actions = $item.Actions
      $this.Comment = $item.Comment
      $this.Disabled = $item.Disabled
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'Category', 'Rule', 'ResourceFilter', 'Actions', 'Comment', 'Disabled' ) ) )
    {
      return $false
    }

    if($this.RuleContext) {
      $context = -1
      switch ($this.RuleContext)
      {
        both { $context = 0 }
        hub { $context = 1 }
        qmc { $context = 2 }
      }
      If($item.RuleContext -ne $context) {
        Write-Verbose "Test-HasProperties: RuleContext property value - $($item.RuleContext) does not match desired state - $context"
        return $false
      }
    }

    return $true
  }
}

[DscResource()]
class QlikScheduler{

  [DscProperty(Key)]
  [string]$Node

  [DscProperty()]
  [string]$SchedulerServiceType

  [DscProperty()]
  [Int]$MaxConcurrentEngines

  [DscProperty()]
  [Int]$EngineTimeout

  [void] Set()
  {
    $item = Get-QlikScheduler -raw -full -filter "serverNodeConfiguration.name eq '$($this.Node)'"

    $params = @{ "id" = $item.id }
    if($this.SchedulerServiceType) { $params.Add("SchedulerServiceType", $this.SchedulerServiceType) }
    if($this.MaxConcurrentEngines) { $params.Add("maxConcurrentEngines", $this.MaxConcurrentEngines) }
    if($this.EngineTimeout) { $params.Add("engineTimeout", $this.EngineTimeout) }

    Update-QlikScheduler @params
  }

  [bool] Test()
  {
    $item = Get-QlikScheduler -raw -full -filter "serverNodeConfiguration.name eq '$($this.Node)'"

    if($this.hasProperties($item))
    {
      return $true
    } else {
      return $false
    }
  }

  [QlikScheduler] Get()
  {
    $item = Get-QlikScheduler -raw -full -filter "serverNodeConfiguration.name eq '$($this.Node)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.SchedulerServiceType = $item.settings.SchedulerServiceType
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    If($this.SchedulerServiceType) {
      $sched_type = -1
      switch ($this.schedulerServiceType)
      {
        master { $sched_type = 0 }
        slave { $sched_type = 1 }
        both { $sched_type = 2 }
      }
      if($item.settings.SchedulerServiceType -ne $sched_type) {
        Write-Verbose "Test-HasProperties: SchedulerServiceType property value - $($item.settings.SchedulerServiceType) does not match desired state - $($sched_type)"
        return $false
      }
      if($item.settings.maxConcurrentEngines -ne $sched_type) {
        Write-Verbose "Test-HasProperties: MaxConcurrentEngines property value - $($item.settings.maxConcurrentEngines) does not match desired state - $($this.MaxConcurrentEngines)"
        return $false
      }
      if($item.settings.EngineTimeout -ne $sched_type) {
        Write-Verbose "Test-HasProperties: EngineTimeout property value - $($item.settings.EngineTimeout) does not match desired state - $($this.EngineTimeout)"
        return $false
      }
    }

    return $true
  }
}

[DscResource()]
class QlikTask{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty(Mandatory)]
  [string]$App

  [DscProperty()]
  [string]$Stream

  [DscProperty()]
  [hashtable]$Schedule

  [DscProperty()]
  [string]$OnSuccess

  [DscProperty()]
  [ReloadOn]$StartOn

  [DscProperty()]
  [bool]$WaitUntilFinished

  [DscProperty()]
  [string]$Tags

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = Get-QlikTask -raw -filter "name eq '$($this.name)'" -full
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        Write-Verbose "Task not found but should be present"
        $appfilter = "name eq '$($this.App)'"
        if($this.Stream -ne $null){ $appfilter += " and stream.name eq '$($this.Stream)'"}
        $item = New-QlikTask -name $this.Name -appId (Get-QlikApp -filter $appfilter).id
        Write-Verbose -Message "Created task with id $($item.id)"
        if ($this.StartOn -eq [ReloadOn]::Create)
        {
          Write-Verbose "Starting task since StartOn is set to $($this.StartOn)"
          if ($this.WaitUntilFinished)
          {
            Start-QlikTask -id $item.id -wait | Wait-QlikExecution
          } else {
            Start-QlikTask -id $item.id
          }
        }
      }
      else
      {
        #$appTags = @()
        #foreach ($tag in $this.Tags)
        #{
        #  $tagId = (Get-QlikTag -filter "name eq '$tag'").id
        #  if (-Not $tagId)
        #  {
        #    $tagId = (New-QlikTag -name $tag).id
        #    Write-Verbose "Created tag for $tag with id $tagId"
        #  }
        #  $appTags += $tag
        #}
        $prop = ConfigurePropertiesAndTags($this)
        Update-QlikReloadTask -id $item.id -tags $prop.Tags
        if ($this.StartOn -eq [ReloadOn]::Update)
        {
          Write-Verbose "Starting task since StartOn is set to $($this.StartOn)"
          if ($this.WaitUntilFinished)
          {
            Start-QlikTask -id $item.id -wait | Wait-QlikExecution
          } else {
            Start-QlikTask -id $item.id
          }
        }
      }
      if ($this.Schedule)
      {
        Add-QlikTrigger -taskId $item.id -date $this.Schedule.Date
      }
      elseif ($this.OnSuccess -And (-Not (Invoke-QlikGet "/qrs/compositeevent?filter=compositeRules.reloadTask.id eq $($this.OnSuccess) and reloadTask.id eq $($item.id)")))
      {
        Add-QlikTrigger -taskId $item.id -OnSuccess $this.OnSuccess
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting app $($this.name)"
        Remove-QlikApp -id $this.id
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikTask -raw -filter "name eq '$($this.name)'" -full
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        }
        else
        {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      if($present)
      {
        return $false
      }
      else
      {
        return $true
      }
    }
  }

  [QlikTask] Get()
  {
    $item = Get-QlikApp -raw -filter "name eq '$($this.name)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    $result = $true

    if( !(CompareProperties $this $item @( 'Name' ) ) )
    {
      $result = $false
    }

    if (-Not ($item.app.name -eq $this.App))
    {
      Write-Verbose "Task $($item.id) uses app $($item.app.name) and should use $($this.App)"
      $result = $false
    }

    if ($this.OnSuccess -And (-Not (Invoke-QlikGet "/qrs/compositeevent?filter=compositeRules.reloadTask.id eq $($this.OnSuccess) and reloadTask.id eq $($item.id)")))
    {
      Write-Verbose "Trigger for OnSuccess event of task $($this.OnSuccess) does not exist"
      $result = $false
    }

    if ($this.Tags)
    {
      foreach ($tag in $this.Tags)
      {
        if (-Not ($item.tags.name -contains $tag))
        {
          Write-Verbose "Not tagged with $tag"
          return $false
        }
      }
    }

    return $result
  }
}

[DscResource()]
class QlikVirtualProxy{

  [DscProperty(Key)]
  [string]$Prefix

  [DscProperty(Mandatory)]
  [string]$Description

  [DscProperty(Mandatory)]
  [string]$SessionCookieHeaderName

  [DscProperty(Mandatory=$false)]
  [string]$authenticationModuleRedirectUri

  [DscProperty(Mandatory=$false)]
  [string]$loadBalancingServerNodes

  [DscProperty(Mandatory=$false)]
  [string[]]$websocketCrossOriginWhiteList

  [DscProperty(Mandatory=$false)]
  [string[]]$proxy

  [DscProperty(Mandatory=$false)]
  [string]$proxyFilter

  [DscProperty(Mandatory=$false)]
  [ValidateSet("ticket","static","dynamic","saml","jwt", IgnoreCase=$false)]
  [string]$authenticationMethod

  [DscProperty(Mandatory=$false)]
  [string]$samlMetadataIdP

  [DscProperty(Mandatory=$false)]
  [string]$samlHostUri

  [DscProperty(Mandatory=$false)]
  [string]$samlEntityId

  [DscProperty(Mandatory=$false)]
  [string]$samlAttributeUserId

  [DscProperty(Mandatory=$false)]
  [string]$samlAttributeUserDirectory

  [DscProperty(Mandatory=$false)]
  [Int]$sessionInactivityTimeout

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = $(Get-QlikVirtualProxy -raw -filter "Prefix eq '$($this.Prefix)'")
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      $params = @{
        Prefix = $this.Prefix
        Description = $this.Description
        SessionCookieHeaderName = $this.SessionCookieHeaderName
      }
      If( $this.loadBalancingServerNodes ) {
        $engines = Get-QlikNode -raw -filter $this.loadBalancingServerNodes | foreach { $_.id } | ? { $_ }
        $params.Add("loadBalancingServerNodes", $engines)
      }
      If( $this.websocketCrossOriginWhiteList ) { $params.Add("websocketCrossOriginWhiteList", $this.websocketCrossOriginWhiteList) }
      If( $this.authenticationModuleRedirectUri ) { $params.Add("authenticationModuleRedirectUri", $this.authenticationModuleRedirectUri) }
      If( $this.authenticationMethod ) { $params.Add("authenticationMethod", $this.authenticationMethod) }
      If( $this.samlMetadataIdP ) { $params.Add("samlMetadataIdP", $this.samlMetadataIdP) }
      If( $this.samlHostUri ) { $params.Add("samlHostUri", $this.samlHostUri) }
      If( $this.samlEntityId ) { $params.Add("samlEntityId", $this.samlEntityId) }
      If( $this.samlAttributeUserId ) { $params.Add("samlAttributeUserId", $this.samlAttributeUserId) }
      If( $this.samlAttributeUserDirectory ) { $params.Add("samlAttributeUserDirectory", $this.samlAttributeUserDirectory) }
      If( $this.sessionInactivityTimeout ) { $params.Add("sessionInactivityTimeout", $this.sessionInactivityTimeout) }

      if($present)
      {
        if(-not $this.hasProperties($item))
        {
          Update-QlikVirtualProxy -id $item.id @params
        }
      }
      else
      {
        $item = New-QlikVirtualProxy @params
      }

      if( $this.proxy )
      {
        $this.proxy | foreach {
          $qp = Get-QlikProxy -raw -filter "serverNodeConfiguration.hostName eq '$_'"
          Add-QlikProxy $qp.id $item.id
        }
      }
      if( $this.proxyFilter )
      {
        Get-QlikProxy -raw -filter $this.proxyFilter | foreach {
            Add-QlikProxy $_.id $item.id
        }
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting virtual proxy $($this.Prefix)"
        #Get-QlikVirtualProxy -filter "Prefix eq $($this.Prefix) | Remove-QlikVirtualProxy
      }
    }
  }

  [bool] Test()
  {
    $item = $(Get-QlikVirtualProxy -raw -filter "Prefix eq '$($this.Prefix)'")
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      return -not $present
    }
  }

  [QlikVirtualProxy] Get()
  {
    $present = $(Get-QlikVirtualProxy -raw -filter "Prefix eq '$($this.Prefix)'") -ne $null
    if ($present)
    {
      $qvp = Get-QlikVirtualProxy -raw -filter "Prefix eq '$($this.Prefix)'"
      $this.Description = $qvp.Description
      $this.SessionCookieHeaderName = $qvp.SessionCookieHeaderName
      $this.authenticationModuleRedirectUri = $qvp.authenticationModuleRedirectUri
      $this.loadBalancingServerNodes = $qvp.loadBalancingServerNodes
      $this.websocketCrossOriginWhiteList = $qvp.websocketCrossOriginWhiteList
      $this.authenticationMethod = $qvp.authenticationMethod
      $this.samlMetadataIdP = $qvp.samlMetadataIdP
      $this.samlHostUri = $qvp.samlHostUri
      $this.samlEntityId = $qvp.samlEntityId
      $this.samlAttributeUserId = $qvp.samlAttributeUserId
      $this.samlAttributeUserDirectory = $qvp.samlAttributeUserDirectory
      $this.sessionInactivityTimeout = $qvp.sessionInactivityTimeout
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'Description', 'SessionCookieHeaderName', 'authenticationModuleRedirectUri',
        'samlMetadataIdP', 'samlHostUri', 'samlEntityId', 'samlAttributeUserId', 'samlAttributeUserDirectory', 'sessionInactivityTimeout' ) ) )
    {
      return $false
    }

    if($this.authenticationMethod) {
        $authenticationMethodCode = switch ($this.authenticationMethod) {
            'ticket'  { 0 }
            'static'  { 1 }
            'dynamic' { 2 }
            'saml'    { 3 }
            'jwt'     { 4 }
        }
        If($authenticationMethodCode -ne $item.authenticationMethod) {
            Write-Verbose "Test-HasProperties: authenticationMethod - $($item.authenticationMethod) does not match desired state - $authenticationMethodCode"
            return $false;
        }
    }

    if($this.loadBalancingServerNodes) {
      $nodes = Get-QlikNode -filter $this.loadBalancingServerNodes | foreach { $_.id } | ? { $_ }
      if(@($nodes).Count -ne @($item.loadBalancingServerNodes).Count) {
        Write-Verbose "Test-HasProperties: loadBalancingServerNodes property count - $(@($item.loadBalancingServerNodes).Count) does not match desired state - $(@($nodes).Count)"
        return $false
      } else {
        foreach($value in $item.loadBalancingServerNodes) {
          if($nodes -notcontains $value.id) {
            Write-Verbose "Test-HasProperties: loadBalancingServerNodes property value - $($value) not found in desired state"
            return $false
          }
        }
      }
    }

    if($this.websocketCrossOriginWhiteList) {
      if(@($this.websocketCrossOriginWhiteList).Count -ne @($item.websocketCrossOriginWhiteList).Count) {
        Write-Verbose "Test-HasProperties: websocketCrossOriginWhiteList property count - $(@($item.websocketCrossOriginWhiteList).Count) does not match desired state - $(@($this.websocketCrossOriginWhiteList).Count)"
        return $false
      } else {
        foreach($value in $item.websocketCrossOriginWhiteList) {
          if($this.websocketCrossOriginWhiteList -notcontains $value) {
            Write-Verbose "Test-HasProperties: websocketCrossOriginWhiteList property value - $($value) not found in desired state"
            return $false
          }
        }
      }
    }

    if( $this.proxy ) {
      $proxies = Get-QlikProxy -raw -full -filter "settings.virtualProxies.id eq $($item.id)" | select -ExpandProperty serverNodeConfiguration | select hostName
      foreach( $proxy in $this.proxy )
      {
        if( -Not ($proxies.hostName -Contains $proxy) )
        {
          Write-Verbose "Test-HasProperties: $proxy not linked"
          return $false
        }
      }
    }

    if ($this.proxyFilter) {
      $globalMatch = $true
      Get-QlikProxy -raw -full -filter $this.proxyFilter | foreach {
        $match  = $false
        $_.settings.virtualProxies | foreach {
            If($_.id -eq $item.id) {
                $match = $true
            }
        }
        If(!$match) {
            Write-Verbose "Test-HasProperties: $_ not linked"
            $globalMatch = $false
        }
      }
      If (!$globalMatch) {
        return $false
      }
    }

    return $true
  }
}

[DscResource()]
class QlikEngine {

    [DscProperty(Key)]
    [string]$Node

    [DscProperty()]
    [string]$DocumentDirectory

    [DscProperty()]
    [Int]$DocumentTimeout

    [DscProperty()]
    [ValidateRange(0,100)]
    [Int]$MinMemUsage

    [DscProperty()]
    [ValidateRange(0,100)]
    [Int]$MaxMemUsage

    [DscProperty()]
    [ValidateSet("IgnoreMaxLimit", "SoftMaxLimit", "HardMaxLimit")]
    [String]$MemUsageMode

    [DscProperty()]
    [ValidateRange(0,100)]
    [Int]$CpuThrottle

    [DscProperty()]
    [Bool]$AllowDataLineage

    [DscProperty()]
    [Bool]$StandardReload

    [Void] Set () {
        Write-Verbose "Get Qlik Engine: $($this.Node)"
        $item = Get-QlikEngine -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item.id) {
            $engparams = @{ "id" = $item.id }
            if($this.DocumentDirectory) { $engparams.Add("documentDirectory", $this.DocumentDirectory) }
            if($this.DocumentTimeout) { $engparams.Add("documentTimeout", $this.DocumentTimeout) }
            if($this.MinMemUsage) { $engparams.Add("workingSetSizeLoPct", $this.MinMemUsage) }
            if($this.MaxMemUsage) { $engparams.Add("workingSetSizeHiPct", $this.MaxMemUsage) }
            if($this.MemUsageMode) { $engparams.Add("workingSetSizeMode", $this.MemUsageMode) }
            if($this.CpuThrottle) { $engparams.Add("cpuThrottlePercentage", $this.CpuThrottle) }
            if($this.AllowDataLineage) { $engparams.Add("allowDataLineage", $this.AllowDataLineage) }
            if($this.StandardReload) { $engparams.Add("standardReload", $this.StandardReload) }
            Write-Verbose "Update Qlik Engine: $($this.Node)"
            Update-QlikEngine @engparams
        } else {
            Write-Verbose "Qlik Engine '$($this.Node)' not found!"
        }
    }

    [Bool] Test () {
        Write-Verbose "Get Qlik Engine: $($this.Node)"
        $item = Get-QlikEngine -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item -ne $null) {
            if($this.hasProperties($item)) {
                Write-Verbose "Qlik Engine '$($this.Node)' is in desired state"
                return $true
            } else {
                Write-Verbose "Qlik Engine '$($this.Node)' is not in desired state"
                return $false
            }
        } else {
            Write-Verbose "Qlik Engine '$($this.Node)' not found!"
            return $false
        }
    }

    [QlikEngine] Get () {
        Write-Verbose "Get Qlik Engine: $($this.Node)"
        $item = Get-QlikEngine -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item -ne $null) {
          $this.DocumentDirectory = $item.settings.documentDirectory
          $this.DocumentTimeout = $item.settings.documentTimeout
          $this.AllowDataLineage = $item.settings.allowDataLineage
          $this.CpuThrottle = $item.settings.cpuThrottlePercentage
          $this.MaxMemUsage = $item.settings.workingSetSizeHiPct
          switch($item.settings.workingSetSizeMode) {
              0 { $this.MemUsageMode = "IgnoreMaxLimit" }
              1 { $this.MemUsageMode = "SoftMaxLimit" }
              2 { $this.MemUsageMode = "HardMaxLimit" }
          }
          $this.MinMemUsage = $this.settings.workingSetSizeLoPct
          $this.StandardReload = $this.settings.standardReload
          $this.Ensure = [Ensure]::Present
        } else {
            $this.Ensure = [Ensure]::Absent
        }
        return $this
    }

    [bool] hasProperties($item) {
        $desiredState = $true
        if($this.MemUsageMode) {
            $sizeMode = -1
            switch ($this.MemUsageMode) {
                IgnoreMaxLimit { $sizeMode = 0 }
                SoftMaxLimit { $sizeMode = 1 }
                HardMaxLimit { $sizeMode = 2 }
            }
            if($item.settings.workingSetSizeMode -ne $sizeMode) {
                Write-Verbose "Test-HasProperties: Memory usage mode property value - $($item.settings.workingSetSizeMode) does not match desired state - $sizeMode"
                $desiredState = $false
            }
        }
        if($this.documentDirectory) {
            if($item.settings.documentDirectory -ne $this.documentDirectory) {
                Write-Verbose "Test-HasProperties: documentDirectory property value - $($item.settings.documentDirectory) does not match desired state - $($this.documentDirectory)"
                $desiredState = $false
            }
        }
        if($this.DocumentTimeout) {
            if($item.settings.documentTimeout -ne $this.DocumentTimeout) {
                Write-Verbose "Test-HasProperties: documentTimeout property value - $($item.settings.documentTimeout) does not match desired state - $($this.DocumentTimeout)"
                $desiredState = $false
            }
        }
        if($this.MinMemUsage) {
            if($item.settings.workingSetSizeLoPct -ne $this.MinMemUsage) {
                Write-Verbose "Test-HasProperties: Min memory use property value - $($item.settings.workingSetSizeLoPct) does not match desired state - $($this.MinMemUsage)"
                $desiredState = $false
            }
        }
        if($this.MaxMemUsage) {
            if($item.settings.workingSetSizeHiPct -ne $this.MaxMemUsage) {
                Write-Verbose "Test-HasProperties: Max memory usage property value - $($item.settings.workingSetSizeHiPct) does not match desired state - $($this.MaxMemUsage)"
                $desiredState = $false
            }
        }
        if($this.CpuThrottle) {
            if($item.settings.cpuThrottlePercentage -ne $this.CpuThrottle) {
                Write-Verbose "Test-HasProperties: CPU throttle property value - $($item.settings.cpuThrottlePercentage) does not match desired state - $($this.CpuThrottle)"
                $desiredState = $false
            }
        }
        if($item.settings.allowDataLineage -ne $this.AllowDataLineage) {
            Write-Verbose "Test-HasProperties: Allow data lineage property value - $($item.settings.allowDataLineage) does not match desired state - $($this.AllowDataLineage)"
            $desiredState = $false
        }
        if($item.settings.standardReload -ne $this.StandardReload) {
            Write-Verbose "Test-HasProperties: Standard reload property value - $($item.settings.standardReload) does not match desired state - $($this.StandardReload)"
            $desiredState = $false
        }
        return $desiredState
    }
}

[DscResource()]
class QlikProxy {

    [DscProperty(Key)]
    [string]$Node

    [DscProperty()]
    [Int]$ListenPort

    [DscProperty()]
    [Bool]$AllowHttp

    [DscProperty()]
    [Int]$UnencryptedListenPort

    [DscProperty()]
    [Int]$AuthenticationListenPort

    [DscProperty()]
    [Bool]$KerberosAuthentication

    [DscProperty()]
    [Int]$UnencryptedAuthenticationListenPort

    [DscProperty()]
    [String]$SslBrowserCertificateThumbprint

    [DscProperty()]
    [String[]]$CustomProperties

    [DscProperty()]
    [String[]]$VirtualProxies

    [Void] Set () {
        Write-Verbose "Get Qlik Proxy: $($this.Node)"
        $item = Get-QlikProxy -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item.id) {
            $engparams = @{ "id" = $item.id }
            if($this.ListenPort) { $engparams.Add("listenPort", $this.ListenPort) }
            if($this.AllowHttp) { $engparams.Add("allowHttp", $this.AllowHttp) }
            if($this.UnencryptedListenPort) { $engparams.Add("unencryptedListenPort", $this.UnencryptedListenPort) }
            if($this.AuthenticationListenPort) { $engparams.Add("authenticationListenPort", $this.AuthenticationListenPort) }
            if($this.KerberosAuthentication) { $engparams.Add("kerberosAuthentication", $this.KerberosAuthentication) }
            if($this.UnencryptedAuthenticationListenPort) { $engparams.Add("unencryptedAuthenticationListenPort", $this.UnencryptedAuthenticationListenPort) }
            if($this.SslBrowserCertificateThumbprint) { $engparams.Add("sslBrowserCertificateThumbprint", $this.SslBrowserCertificateThumbprint) }
            if($this.CustomProperties) { $engparams.Add("customProperties", $this.CustomProperties) }
            if($null -ne $this.VirtualProxies) { $engparams.Add("virtualProxies", $this.VirtualProxies) }
            Write-Verbose "Update Qlik Proxy: $($this.Node)"
            Update-QlikProxy @engparams
        } else {
            Write-Verbose "Qlik Proxy '$($this.Node)' not found!"
        }
    }

    [Bool] Test () {
        Write-Verbose "Get Qlik Proxy: $($this.Node)"
        $item = Get-QlikProxy -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item -ne $null) {
            if($this.hasProperties($item)) {
                Write-Verbose "Qlik Proxy '$($this.Node)' is in desired state"
                return $true
            } else {
                Write-Verbose "Qlik Proxy '$($this.Node)' is not in desired state"
                return $false
            }
        } else {
            Write-Verbose "Qlik Proxy '$($this.Node)' not found!"
            return $false
        }
    }

    [QlikProxy] Get () {
        Write-Verbose "Get Qlik Proxy: $($this.Node)"
        $item = Get-QlikProxy -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item -ne $null) {
          $this.ListenPort = $item.settings.listenPort
          $this.AllowHttp = $item.settings.allowHttp
          $this.UnencryptedListenPort = $item.settings.unencryptedListenPort
          $this.AuthenticationListenPort = $item.settings.authenticationListenPort
          $this.KerberosAuthentication = $item.settings.kerberosAuthentication
          $this.UnencryptedAuthenticationListenPort = $item.settings.unencryptedAuthenticationListenPort
          $this.SslBrowserCertificateThumbprint = $item.settings.sslBrowserCertificateThumbprint
          $this.VirtualProxies = $item.settings.virtualProxies
          $this.Ensure = [Ensure]::Present
        } else {
            $this.Ensure = [Ensure]::Absent
        }
        return $this
    }

    [bool] hasProperties($item) {
        $desiredState = $true
        if($this.ListenPort) {
            if($item.settings.listenPort -ne $this.listenPort) {
                Write-Verbose "Test-HasProperties: listenPort property value - $($item.settings.listenPort) does not match desired state - $($this.listenPort)"
                $desiredState = $false
            }
        }
        if($this.AllowHttp -ne $null) {
            if($item.settings.allowHttp -ne $this.AllowHttp) {
                Write-Verbose "Test-HasProperties: allowHttp property value - $($item.settings.allowHttp) does not match desired state - $($this.AllowHttp)"
                $desiredState = $false
            }
        }
        if($this.UnencryptedListenPort) {
            if($item.settings.unencryptedListenPort -ne $this.UnencryptedListenPort) {
                Write-Verbose "Test-HasProperties: Min memory use property value - $($item.settings.unencryptedListenPort) does not match desired state - $($this.UnencryptedListenPort)"
                $desiredState = $false
            }
        }
        if($this.AuthenticationListenPort) {
            if($item.settings.authenticationListenPort -ne $this.AuthenticationListenPort) {
                Write-Verbose "Test-HasProperties: Max memory usage property value - $($item.settings.authenticationListenPort) does not match desired state - $($this.AuthenticationListenPort)"
                $desiredState = $false
            }
        }
        if($this.KerberosAuthentication) {
            if($item.settings.kerberosAuthentication -ne $this.KerberosAuthentication) {
                Write-Verbose "Test-HasProperties: CPU throttle property value - $($item.settings.kerberosAuthentication) does not match desired state - $($this.KerberosAuthentication)"
                $desiredState = $false
            }
        }
        if($this.UnencryptedAuthenticationListenPort) {
            if($item.settings.unencryptedAuthenticationListenPort -ne $this.UnencryptedAuthenticationListenPort) {
                Write-Verbose "Test-HasProperties: Allow data lineage property value - $($item.settings.unencryptedAuthenticationListenPort) does not match desired state - $($this.UnencryptedAuthenticationListenPort)"
                $desiredState = $false
            }
        }
        if($this.SslBrowserCertificateThumbprint) {
            if($item.settings.sslBrowserCertificateThumbprint -ne $this.SslBrowserCertificateThumbprint) {
                Write-Verbose "Test-HasProperties: Standard reload property value - $($item.settings.sslBrowserCertificateThumbprint) does not match desired state - $($this.SslBrowserCertificateThumbprint)"
                $desiredState = $false
            }
        }
        if($this.CustomProperties) {
            $propList = $item.customProperties | foreach { "$($_.definition.name)=$($_.value)" }
            if(@($propList).Count -ne @($this.CustomProperties).Count) {
                Write-Verbose "Test-HasProperties: custom properties count differ - $(@($propList).Count) does not match desired state - $(@($this.CustomProperties).Count)"
                $desiredState = $false
            } else {
                $propList | foreach {
                    If (!($this.CustomProperties -contains $_)) {
                        Write-Verbose "Test-HasProperties: custom property - '$_' does not match desired state"
                        $desiredState = $false
                    }
                }
            }
        }
        if($null -ne $this.VirtualProxies) {
            $set = New-Object System.Collections.Generic.HashSet[string]
            $vProxList = $item.settings.virtualProxies | foreach {
              If ($_.defaultVirtualProxy) {
                $res = $set.Add($_.id)
              }
              $_.id
            }
            $this.VirtualProxies | foreach {
              If ($_ -ne '') {
                $eid = Get-QlikVirtualProxy -filter "prefix eq '$_'"
                  If( $eid )
                  {
                    $res = $set.Add($eid.id)
                  }
              }
            }
            if(@($vProxList).Count -ne $set.Count) {
                Write-Verbose "Test-HasProperties: custom properties count differ - $(@($vProxList).Count) does not match desired state - $($set.Count)"
                $desiredState = $false
            } else {
                $vProxList | foreach {
                    If (!($set -contains $_)) {
                        Write-Verbose "Test-HasProperties: virtual proxy - '$_' does not match desired state"
                        $desiredState = $false
                    }
                }
            }
        }
        return $desiredState
    }
}

[DscResource()]
class QlikServiceCluster{

  [DscProperty(Key)]
  [string] $Name

  [DscProperty(Mandatory)]
  [Ensure] $Ensure

  [DscProperty()]
  [int] $PersistenceType

  [DscProperty()]
  [int] $PersistenceMode

  [DscProperty()]
  [string] $RootFolder

  [DscProperty()]
  [string] $AppFolder

  [DscProperty()]
  [string] $StaticContentRootFolder

  [DscProperty()]
  [string] $Connector32RootFolder

  [DscProperty()]
  [string] $Connector64RootFolder

  [DscProperty()]
  [string] $ArchivedLogsRootFolder

  [void] Set()
  {
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw
    $present = $item -ne $null

    if ($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        $item = New-QlikServiceCluster -Name $this.Name
        Write-Verbose "Created cluster with ID $($item.ID)"
      }
      elseif (-Not $this.hasProperties($item))
      {
        $params = @{ "id" = $item.id }
        if ($this.PersistenceType) { $params.Add("persistenceType", $this.PersistenceType) }
        if ($this.PersistenceMode) { $params.Add("persistenceMode", $this.PersistenceMode) }
        if ($this.RootFolder) { $params.Add("rootFolder", $this.RootFolder) }
        if ($this.AppFolder) { $params.Add("appFolder", $this.AppFolder) }
        if ($this.StaticContentRootFolder) { $params.Add("staticContentRootFolder", $this.StaticContentRootFolder) }
        if ($this.Connector32RootFolder) { $params.Add("connector32RootFolder", $this.Connector32RootFolder) }
        if ($this.Connector64RootFolder) { $params.Add("connector64RootFolder", $this.Connector64RootFolder) }
        if ($this.ArchivedLogsRootFolder) { $params.Add("archivedLogsRootFolder", $this.ArchivedLogsRootFolder) }
        Update-QlikServiceCluster @params
      }
    }
    else
    {
      if ($present)
      {
        #Write-Verbose "Deleting Service Cluster $($item.ID)"
        #Remove-QlikServiceCluster $item.ID
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw
    $present = $item -ne $null

    if ($this.Ensure -eq [Ensure]::Present)
    {
      if ($present) {
        return $this.hasProperties($item)
      }
      else
      {
        Write-Verbose "Service Cluster $($this.Name) should be present but was not found"
        return $false
      }
    }
    else
    {
      if ($present)
      {
        Write-Verbose "Service Cluster $($this.Name) should not be present but was found"
        return $false
      }
      else
      {
        return $true
      }
    }
  }

  [QlikServiceCluster] Get()
  {
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw
    if ($item -ne $null)
    {
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if (-Not (CompareProperties $this $item.settings @('PersistenceType', 'PersistenceMode')))
    {
      return $false
    }
    if (-Not (CompareProperties $this $item.settings.sharedPersistenceProperties @('rootFolder', 'appFolder', 'staticContentRootFolder', 'connector32RootFolder', 'connector64RootFolder', 'archivedLogsRootFolder')))
    {
      return $false
    }
    return $true
  }
}

[DscResource()]
class QlikStream{

  [DscProperty(Key)]
  [string]$Name

  [DscProperty()]
  [hashtable]$CustomProperties

  [DscProperty()]
  [string[]]$Tags

  [DscProperty(Mandatory)]
  [Ensure] $Ensure

  [void] Set()
  {
    $item = Get-QlikStream -filter "name eq '$($this.Name)'"
    $present = $item -ne $null

    if ($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        $item = New-QlikStream -Name $this.Name
        Write-Verbose "Created stream with ID $($item.ID)"
      }
      $prop = ConfigurePropertiesAndTags($this)
      Update-QlikStream -id $item.id -customProperties $prop.Properties -tags $prop.Tags
    }
    else
    {
      if ($present)
      {
        Write-Verbose "Deleting stream $($item.ID)"
        Remove-QlikStream $item.ID
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikStream -filter "name eq '$($this.Name)'"
    $present = $item -ne $null

    if ($this.Ensure -eq [Ensure]::Present)
    {
      if ($present) {
        if ($this.hasProperties($item))
        {
          return $true
        }
        else
        {
          Write-Verbose "Stream $($this.Name) does not match desired state"
          return $false
        }
      }
      else
      {
        Write-Verbose "Stream $($this.Name) should be present but was not found"
        return $false
      }
    }
    else
    {
      if ($present)
      {
        Write-Verbose "Stream $($this.Name) should not be present but was found"
        return $false
      }
      else
      {
        return $true
      }
    }
  }

  [QlikStream] Get()
  {
    $item = Get-QlikStream -filter "name eq '$($this.Name)'"
    if ($item -ne $null)
    {
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    #if( !(CompareProperties $this $item @( 'Description', 'SessionCookieHeaderName', 'authenticationModuleRedirectUri' ) ) )
    #{
    #  return $false
    #}
    if ($this.Tags)
    {
      foreach ($tag in $this.Tags)
      {
        if (-Not ($item.tags.name -contains $tag))
        {
          Write-Verbose "Not tagged with $tag"
          return $false
        }
      }
    }

    if ($this.CustomProperties)
    {
      foreach ($prop in $this.CustomProperties.Keys)
      {
        $cp = $item.customProperties | where {$_.definition.name -eq $prop}
        if (-Not (($cp) -And ($cp.value -eq $this.CustomProperties.$prop)))
        {
          Write-Verbose "Property $prop should have value $($this.CustomProperties.$prop) but instead has value $($cp.value)"
          return $false
        }
      }
    }

    return $true
  }
}

[DscResource()]
class QlikPackage {

    [DscProperty(Key)]
    [String]$Name

    [DscProperty(Key)]
    [AllowEmptyString()]
    [string]$ProductId

    [DscProperty(Mandatory)]
    [string]$Setup

    [DscProperty(Mandatory)]
    [Ensure]$Ensure

    [DscProperty()]
    [string]$LogFile

    [DscProperty()]
    [String]$Rimnodetype

    [DscProperty()]
    [Bool]$Rimnode=$false

    [DscProperty()]
    [Bool]$DesktopShortcut=$false

    [DscProperty()]
    [Bool]$SkipStartServices=$false

    [DscProperty()]
    [Bool]$SkipValidation=$false

    [DscProperty()]
    [string]$InstallDir

    [DscProperty()]
    [string]$QlikDataPath

    [DscProperty(Mandatory)]
    [PSCredential]$ServiceCredential

    [DscProperty(Mandatory)]
    [PSCredential]$DbSuperUserPassword

    [DscProperty()]
    [String]$Hostname

    [DscProperty()]
    [PSCredential]$DbCredential

    [DscProperty()]
    [string]$DbHost = "localhost"

    [DscProperty()]
    [int]$DbPort = 4432

    [DscProperty(Mandatory)]
    [string]$RootDir

    [DscProperty()]
    [string]$StaticContentRootDir

    [DscProperty()]
    [string]$CustomDataRootDir

    [DscProperty()]
    [string]$ArchivedLogsDir

    [DscProperty()]
    [string]$AppsDir

    [DscProperty()]
    [bool]$CreateCluster

    [DscProperty()]
    [bool]$InstallLocalDb

    [DscProperty()]
    [bool]$ConfigureDbListener

    [DscProperty()]
    [string]$ListenAddresses = "*"

    [DscProperty()]
    [string]$IpRange = "0.0.0.0/0"

    [DscProperty()]
    [Int]$ExitCode=0

    [void] Set() {
        if($this.Ensure -eq [Ensure]::Present) {
            Write-Verbose "Install $($this.Name) with ProductId '$($this.ProductId)'"
            [String]$parsedSetupParams = "-silent"
            if($this.LogFile) { [String]$parsedSetupParams += " -log `"$($this.LogFile)`"" }
            if($this.SkipStartServices) { [String]$parsedSetupParams += " skipstartservices=1" }
            if($this.InstallDir) { [String]$parsedSetupParams += " installdir=`"$($this.InstallDir)`"" }
            if($this.DesktopShortcut) { [String]$parsedSetupParams += " desktopshortcut=1" }
            if(Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like 'Qlik Sense*' }) {
                if($this.ServiceCredential) {
                    [String]$parsedSetupParams += " userpassword=`"$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ServiceCredential.Password)))`""
                }
                [String]$parsedSetupParams += " dbpassword=`"$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.DbSuperUserPassword.Password)))`""
            } else {
                if($this.Rimnodetype) {
                    [String]$parsedSetupParams += " rimnodetype=$($this.Rimnodetype)"
                    foreach($item in $this.Features) {
                        [String]$parsedSetupParams += " `"$item`""
                    }
                }
                if($this.Rimnode) { [String]$parsedSetupParams += " rimnode=1" }
                [String]$parsedSetupParams += " dbpassword=`"$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.DbSuperUserPassword.Password)))`""
                if($this.Hostname) { [String]$parsedSetupParams += " hostname=`"$($this.Hostname)`"" }
                if($this.ServiceCredential) { [String]$parsedSetupParams += " userwithdomain=`"$($this.ServiceCredential.Username)`" userpassword=`"$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ServiceCredential.Password)))`"" }

                if($this.RootDir) {
                  if(!$this.StaticContentRootDir) { $this.StaticContentRootDir = "$($this.RootDir)\StaticContent" }
                  if(!$this.CustomDataRootDir) { $this.CustomDataRootDir = "$($this.RootDir)\CustomData" }
                  if(!$this.ArchivedLogsDir) { $this.ArchivedLogsDir = "$($this.RootDir)\ArchivedLogs" }
                  if(!$this.AppsDir) { $this.AppsDir = "$($this.RootDir)\Apps" }
                }
                $spc = @"
<?xml version="1.0"?>
<SharedPersistenceConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <DbUserName>$($this.DbCredential.Username)</DbUserName>
  <DbUserPassword>$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.DbCredential.Password)))</DbUserPassword>
  <DbHost>$($this.DbHost)</DbHost>
  <DbPort>$($this.DbPort)</DbPort>
  <RootDir>$($this.RootDir)</RootDir>
  <StaticContentRootDir>$($this.StaticContentRootDir)</StaticContentRootDir>
  <CustomDataRootDir>$($this.CustomDataRootDir)</CustomDataRootDir>
  <ArchivedLogsDir>$($this.ArchivedLogsDir)</ArchivedLogsDir>
  <AppsDir>$($this.AppsDir)</AppsDir>
  <CreateCluster>$("$($this.CreateCluster)".ToLower())</CreateCluster>
  <InstallLocalDb>$("$($this.InstallLocalDb)".ToLower())</InstallLocalDb>
  <ConfigureDbListener>$("$($this.ConfigureDbListener)".ToLower())</ConfigureDbListener>
  <ListenAddresses>$($this.ListenAddresses)</ListenAddresses>
  <IpRange>$($this.IpRange)</IpRange>
</SharedPersistenceConfiguration>
"@
                $spc | Out-File -FilePath "$env:temp\spc.cfg"
                [String]$parsedSetupParams += " spc=`"$env:temp\spc.cfg`""
            }
            Write-Verbose "Starting `"$($this.Setup)`" $parsedSetupParams"
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.UseShellExecute = $false #Necessary for I/O redirection and just generally a good idea
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $startInfo.FileName = $this.Setup
            $startInfo.Arguments = $parsedSetupParams
            $process.Start() | Out-Null
            $process.WaitForExit()
            Write-Verbose "$($this.Name) installation finished with Exitcode: $($process.ExitCode)"
        } else {
            Write-Verbose "Uninstall $($this.Name)  with ProductId '$($this.ProductId)'"
            [String]$parsedSetupParams = "-silent -uninstall"
            if($this.LogFile) { [String]$parsedSetupParams += " -log `"$($this.LogFile)`"" }
            Write-Verbose "Starting `"$($this.Setup)`" $parsedSetupParams"
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.UseShellExecute = $false #Necessary for I/O redirection and just generally a good idea
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $startInfo.FileName = $this.Setup
            $startInfo.Arguments = $parsedSetupParams
            $process.Start() | Out-Null
            $process.WaitForExit()
            Write-Verbose "$($this.Name) uninstallation finished with Exitcode: $($process.ExitCode)"
        }
    }

    [bool] Test() {
        if($env:USERNAME -eq "$env:COMPUTERNAME$") { Write-Error "$($this.Name) can not be installed by 'LOCAL SYSTEM', please use PsDscRunAsCredential property" }
        $regItem = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -eq $this.Name })
        if($this.Ensure -eq [Ensure]::Present) {
            if($regItem) {
                if($this.ProductId.Trim("{}") -eq $regItem.BundleProviderKey.Trim("{}")) {
                    Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Present', in desired state."
                    return $true
                } else {
                    Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Absent', not in desired state."
                    return $false
                }
            } else {
                Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Absent', not in desired state."
                return $false
            }
        } else {
            if($regItem) {
                if($this.ProductId.Trim("{}") -eq $regItem.BundleProviderKey.Trim("{}")) {
                    Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Present', not in desired state."
                    return $false
                } else {
                    Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Absent', in desired state."
                    return $true
                }
            } else {
                Write-Verbose "$($this.Name) installation with ProductId '$($this.ProductId)' is 'Absent', in desired state."
                return $true
            }
        }
    }

    [QlikPackage] Get() {
        $regItem = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -eq "Qlik Sense" })
        if($regItem) {
            #$this.ProductId = $regItem.BundleProviderKey.Trim("{}")
            $this.Ensure = [Ensure]::Present
        } else {
            #$this.ProductId = $null
            $this.Ensure = [Ensure]::Absent
        }
        return @{}
    }

}

[DscResource()]
class QlikUser{

  [DscProperty(Key)]
  [string]$UserID

  [DscProperty(Key)]
  [string]$UserDirectory

  [DscProperty()]
  [string]$Name

  [DscProperty()]
  [string[]]$Roles

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = Get-QlikUser -raw -full -filter "userId eq '$($this.userID)' and userDirectory eq '$($this.userDirectory)'"
    $present = $item -ne $null
    if($this.ensure -eq [Ensure]::Present)
    {
      $params = @{
        userID = $this.userID
        userDirectory = $this.userDirectory
      }
      if($this.Name) { $params.Add("Name", $this.Name) }
      if($this.Roles) { $params.Add("Roles", $this.Roles) }

      if($present)
      {
        if(-not $this.hasProperties($item))
        {
          $params.Remove("UserID")
          $params.Remove("UserDirectory")
          Update-QlikUser -id $item.id @params
        }
      } else {
        New-QlikUser @params
      }
    }
    else
    {
      if($present)
      {
        Write-Verbose -Message "Deleting the property $($this.name)"
        Remove-QlikUser -id $item.id
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikUser -raw -full -filter "userId eq '$($this.userID)' and userDirectory eq '$($this.userDirectory)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          return $true
        } else {
          return $false
        }
      } else {
        return $false
      }
    }
    else
    {
      return -not $present
    }
  }

  [QlikUser] Get()
  {
    $item = Get-QlikUser -raw -full -filter "userId eq '$($this.userID)' and userDirectory eq '$($this.userDirectory)'"
    $present = $item -ne $null

    if ($present)
    {
      $this.Name = $item.Name
      $this.Roles = $item.Roles
      $this.Ensure = [Ensure]::Present
    }
    else
    {
      $this.Ensure = [Ensure]::Absent
    }

    return $this
  }

  [bool] hasProperties($item)
  {
    if( !(CompareProperties $this $item @( 'Name' ) ) )
    {
      return $false
    }

    if($this.Roles) {
      if(@($this.Roles).Count -ne @($item.Roles).Count) {
        Write-Verbose "Test-HasProperties: Role count - $(@($item.Roles).Count) does not match desired state - $(@($this.Roles).Count)"
        return $false
      } else {
        foreach($value in $item.Roles) {
          if($this.Roles -notcontains $value) {
            Write-Verbose "Test-HasProperties: Role - $($value) not found in desired state"
            return $false
          }
        }
      }
    }

    return $true
  }
}

function CompareProperties( $expected, $actual, $prop )
{
  $result = $true

  $prop.foreach({
    If($expected.$_ -And ($actual.$_ -ne $expected.$_)) {
      Write-Verbose "CompareProperties: $_ property value - $($actual.$_) does not match desired state - $($expected.$_)"
      $result = $false
    }
  })

  return $result
}

function ConfigurePropertiesAndTags( $item ) {
    $props = @()
    foreach ($prop in $item.CustomProperties.Keys)
    {
      $cp = Get-QlikCustomProperty -filter "name eq '$prop'" -raw
      if (-Not ($cp.choiceValues -contains $item.CustomProperties.$prop))
      {
        $cp.choiceValues += $item.CustomProperties.$prop
        Write-Verbose -Message "Updating property $prop with new value of $($item.CustomProperties.$prop)"
        Update-QlikCustomProperty -id $cp.id -choiceValues $cp.choiceValues
      }
      $props += "$($prop)=$($item.CustomProperties.$prop)"
    }
    $tags = @()
    foreach ($tag in $item.Tags)
    {
      $tagId = (Get-QlikTag -filter "name eq '$tag'").id
      if (-Not $tagId)
      {
        $tagId = (New-QlikTag -name $tag).id
        Write-Verbose "Created tag for $tag with id $tagId"
      }
      $tags += $tag
    }

    return @{Properties = $props; Tags = $tags}
}

# ---------------- Move to new module when nested modules fixed in WMF -------------------

[DscResource()]
class EncryptConfig{

  [DscProperty(Key)]
  [string] $exePath

  [DscProperty(Mandatory)]
  [string[]] $configSection

  [DscProperty()]
  [string] $connectionString

  [DscProperty()]
  [string] $provName = "DataProtectionConfigurationProvider"

  [DscProperty(Mandatory)]
  [Ensure] $Ensure

  [void] Set()
  {
    $config = [System.Configuration.ConfigurationManager]::OpenExeConfiguration($this.exePath)
    foreach ($sectionName in $this.configSection)
    {
      $section = $config.GetSection($sectionName)
      if ($section.SectionInformation.IsProtected)
      {
        $conn = $section.connectionStrings | where name -eq 'QSR'
        if ($conn.connectionString -ne $this.connectionString)
        {
          $conn.connectionString = $this.connectionString
        }
      }
      else
      {
        Write-Verbose "Encrypting $sectionName"
        $section.SectionInformation.ProtectSection($this.provName)
        $section.SectionInformation.ForceSave = $true
      }
    }
    $config.Save([System.Configuration.ConfigurationSaveMode]::Modified)
  }

  [bool] Test()
  {
    $config = [System.Configuration.ConfigurationManager]::OpenExeConfiguration($this.exePath)
    foreach ($sectionName in $this.configSection)
    {
      $section = $config.GetSection($sectionName)
      if ($section.SectionInformation.IsProtected)
      {
        $conn = $section.connectionStrings | where name -eq 'QSR'
        if ($conn.connectionString -ne $this.connectionString)
        {
          Write-Verbose "Connection string does not match desired state"
          return $false
        }
      }
      else
      {
        Write-Verbose "$sectionName in $($config.FilePath) is not encrypted"
        return $false
      }
    }
    return $true
  }

  [EncryptConfig] Get()
  {
    $this.Ensure = [Ensure]::Present

    return $this
  }
}

[DscResource()]
class ConfigFile{

  [DscProperty(Key)]
  [string] $configPath

  [DscProperty(Mandatory)]
  [hashtable] $appSettings

  [DscProperty(Mandatory)]
  [Ensure] $Ensure

  [void] Set()
  {
    $xml = [xml](Get-Content $this.configPath)
    $this.appSettings.Keys | foreach {
      $setting = $xml.configuration.appSettings.add | where key -eq $_
      if ($setting)
      {
        $setting.value = $this.appSettings.$_
      }
    }
    $xml.save($this.configPath)
  }

  [bool] Test()
  {
    $xml = [xml](Get-Content $this.configPath)
    $result = $true

    $this.appSettings.Keys | foreach {
      $setting = $xml.configuration.appSettings.add | where key -eq $_
      if ($setting.value -ne $this.appSettings.$_)
      {
        Write-Verbose "Config setting for $_ has value $($setting.value) and should be $($this.appSettings.$_)"
        $result = $false
      }
    }

    return $result
  }

  [ConfigFile] Get()
  {
    $xml = [xml](Get-Content $this.configPath)
    $this.appSettings = $xml.configuration.appSettings.add
    $this.Ensure = [Ensure]::Present

    return $this
  }
}

[DscResource()]
class LineInFile
{
  [DscProperty(Key)]
  [string] $Path

  [DscProperty(Key)]
  [string] $Line

  [DscProperty()]
  [string] $InsertBefore

  [DscProperty()]
  [Ensure] $Ensure

  [void] Set()
  {
    $file = Get-Content $this.Path
    $out = ""
    $found = $false

    if ($this.InsertBefore)
    {
      ForEach ($fl in $file)
      {
        if ($fl | Select-String -Pattern $this.InsertBefore)
        {
          $out += $this.Line + "`r`n"
          $found = $true
        }
        $out += $fl + "`r`n"
      }
    }
    else
    {
      $out = $file
    }
    if (-Not $found)
    {
      $out += $this.Line + "`r`n"
    }
    Set-Content -Path $this.Path -Value $out
  }

  [bool] Test()
  {
    $file = Get-Content $this.Path
    ForEach ($fl in $file)
    {
      if ($fl -eq $this.Line)
      {
        Write-Verbose "Line exists in file"
        return $true
      }
    }
    return $false
  }

  [LineInFile] Get()
  {
    $this.Ensure = [Ensure]::Absent

    $file = Get-Content $this.Path
    ForEach ($fl in $file)
    {
      if ($fl | Select-String -Pattern $this.Line)
      {
        $this.Ensure = [Ensure]::Present
        break
      }
    }
    return $this
  }
}
