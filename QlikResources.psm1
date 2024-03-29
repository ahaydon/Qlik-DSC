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

enum authenticationMethod {
    Ticket = 0
    Static = 1
    Dynamic = 2
    SAML = 3
    JWT = 4
}

[DscResource()]
class QlikApp{

  [DscProperty()]
  [string]$Id

  [DscProperty(Key)]
  [string]$Name

  [DscProperty()]
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
        $item = $item | ? {$_.stream.name -eq $this.Stream}
    }
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        Write-Verbose "App not found but should be present"
        Write-Verbose -Message "Importing app from $($this.Source)"
        $item = Import-QlikApp -file $this.Source -name $this.Name -upload
        $this.configure($item)
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
          $result = Wait-QlikExecution -taskId $task.id
          if ($result.status -ne 'FinishedSuccess')
          {
            Write-Error "Reload of app $($replace.id) failed with status $($result.status)"
            return
          }
        }
        Switch-QlikApp -id $replace.id -appId $item.id
        $this.configure($item)
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
      $item = $item | ? {$_.stream.name -eq $this.Stream}
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
      $item = $item | ? {$_.stream.name -eq $this.Stream}
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
class QlikContentLibrary {
  [DscProperty(Key)]
  [string] $Name

  [DscProperty()]
  [hashtable] $CustomProperties

  [DscProperty()]
  [string[]] $Tags

  [DscProperty(Mandatory)]
  [Ensure] $Ensure

  [void] Set()
  {
    $item = Get-QlikContentLibrary -raw -full -filter "name eq '$($this.Name)'"
    $present = $item -ne $null

    if ($this.Ensure -eq [Ensure]::Present)
    {
      $prop = ConfigurePropertiesAndTags($this)
      if (-Not $present)
      {
        Write-Verbose "Creating Content Library '$($this.Name)'"
        New-QlikContentLibrary -Name $this.Name @prop
      }
      else
      {
        Write-Verbose "Updating Content Library '$($item.id)'"
        #Update-QlikContentLibrary -id $this.id @prop
      }
    }
    else
    {
      if ($present)
      {
        Write-Verbose "Deleting Content Library '$($item.id)'"
        Remove-QlikContentLibrary -id $this.id
      }
    }
  }

  [bool] Test()
  {
    $item = Get-QlikContentLibrary -raw -full -filter "name eq '$($this.Name)'"
    $present = $item -ne $null

    if ($this.Ensure -eq [Ensure]::Present)
    {
      if (-Not $present)
      {
        Write-Verbose "Content Library '$($this.Name)' not found but should be present"
        return $false
      }
      else
      {
        return $this.hasProperties($item)
      }
    }
    else
    {
      if ($present)
      {
        Write-Verbose "Content Library '$($item.id)' should be absent"
        return $false
      }
    }
    return $true
  }

  [QlikContentLibrary] Get()
  {
    $item = Get-QlikContentLibrary -raw -full -filter "name eq '$($this.Name)'"
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
  [int]$MaxRetries = 30

  [DscProperty()]
  [int]$RetryDelay = 10

  [void] Set()
  {
    $cert = $null
    if( $this.Certificate -And ($this.Certificate.SubString(0, 5) -eq 'cert:' )) {
      $cert = Get-ChildItem $this.Certificate
    } elseif( $this.Certificate ) {
      $cert = Get-PfxCertificate $this.Certificate
    }
    if( !$cert ) {
      $cert = Get-ChildItem Cert:\CurrentUser\My\ | Where-Object Subject -eq CN=QlikClient
    }
    $params = @{}
    if( $cert ) {
      $params.Username = $this.Username
      $params.Certificate = $cert
    }
    if( $this.Computername ) { $params.Add( "Computername", $this.Computername ) }
    if( $this.TrustAllCerts ) { $params.Add( "TrustAllCerts", $true ) }
    $err = $null
    for ($i = 1; $i -le $this.MaxRetries; $i++) {
      Write-Progress "Connecting to Qlik, attempt $i"
      try {
        if (Connect-Qlik -ErrorAction Ignore -ErrorVariable err @params) {
          break
        }
      } catch {
        Write-Warning $_.Exception.Message
        $err = $_
        Start-Sleep $this.RetryDelay
      }
    }
    if ($err) {
      throw $err
    }
  }

  [bool] Test()
  {
    $cert = $null
    if( $this.Certificate -And ($this.Certificate.SubString(0, 5) -eq 'cert:' )) {
      $cert = gci $this.Certificate
    } elseif( $this.Certificate ) {
      $cert = Get-PfxCertificate $this.Certificate
    }
    if( !$cert ) {
      $cert = Get-ChildItem Cert:\CurrentUser\My\ | Where-Object Subject -eq CN=QlikClient
    }
    $params = @{}
    if( $cert ) {
      $params.Username = $this.Username
      $params.Certificate = $cert
    }
    if( $this.Computername ) { $params.Add( "Computername", $this.Computername ) }
    if( $this.TrustAllCerts ) { $params.Add( "TrustAllCerts", $true ) }

    $err = $null
    try {
      if (Connect-Qlik -ErrorAction Ignore -ErrorVariable err @params) {
        # Data returned from connect command so return true
        return $true
      }
    } catch {
      # An error was thrown when connecting so return false
      return $false
    }
    if ($err) {
      # The err variable contains an error so return false
      return $false
    }
    # No errors so return true
    return $true
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
  [string]$UserID

  [DscProperty()]
  [string]$Password

  [DscProperty()]
  [string[]]$Tags

  [DscProperty(Mandatory)]
  [string]$Type

  [void] Set()
  {
    $item = Get-QlikDataConnection -raw -full -filter "name eq '$($this.name)'"
    $present = $item -ne $null
    if($this.ensure -eq [Ensure]::Present)
    {
      if(!$present)
      {
          $item = New-QlikDataConnection -Name $this.Name -ConnectionString $this.ConnectionString -Type $this.Type
      }
      $prop = ConfigurePropertiesAndTags($this)
      Update-QlikDataConnection -id $item.id -ConnectionString $this.ConnectionString @prop
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
    $item = Get-QlikDataConnection -raw -full -filter "name eq '$($this.name)'"
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
    $present = $(Get-QlikDataConnection -raw -full -filter "name eq '$($this.name)'") -ne $null

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
  [string]$KeyProperty = "serverNodeConfiguration.name"

  [DscProperty()]
  [string]$SchedulerServiceType

  [DscProperty()]
  [Int]$MaxConcurrentEngines

  [DscProperty()]
  [Int]$EngineTimeout

  [void] Set()
  {
    $item = Get-QlikScheduler -raw -full -filter "$($this.KeyProperty) eq '$($this.Node)'"

    $params = @{ "id" = $item.id }
    if($this.SchedulerServiceType) { $params.Add("SchedulerServiceType", $this.SchedulerServiceType) }
    if($this.MaxConcurrentEngines) { $params.Add("maxConcurrentEngines", $this.MaxConcurrentEngines) }
    if($this.EngineTimeout -gt 0) { $params.Add("engineTimeout", $this.EngineTimeout) }

    Update-QlikScheduler @params
  }

  [bool] Test()
  {
    $item = Get-QlikScheduler -raw -full -filter "$($this.KeyProperty) eq '$($this.Node)'"

    if($this.hasProperties($item))
    {
      return $true
    } else {
      return $false
    }
  }

  [QlikScheduler] Get()
  {
    $item = Get-QlikScheduler -raw -full -filter "$($this.KeyProperty) eq '$($this.Node)'"
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
    }
    if($item.settings.maxConcurrentEngines -ne $this.MaxConcurrentEngines) {
      Write-Verbose "Test-HasProperties: MaxConcurrentEngines property value - $($item.settings.maxConcurrentEngines) does not match desired state - $($this.MaxConcurrentEngines)"
      return $false
    }
    if($this.EngineTimeout -gt 0 -and $item.settings.EngineTimeout -ne $this.EngineTimeout) {
      Write-Verbose "Test-HasProperties: EngineTimeout property value - $($item.settings.EngineTimeout) does not match desired state - $($this.EngineTimeout)"
      return $false
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

  [DscProperty(Key)]
  [string]$Stream

  [DscProperty()]
  [hashtable]$Schedule

  [DscProperty()]
  [string[]]$OnSuccess

  [DscProperty()]
  [ReloadOn]$StartOn

  [DscProperty()]
  [bool]$WaitUntilFinished

  [DscProperty()]
  [string[]]$Tags

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
        $item = New-QlikTask -name $this.Name -appId (Get-QlikApp -filter $appfilter).id -tags $this.Tags
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
        Update-QlikReloadTask -id $item.id -tags $this.Tags
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
      elseif ($this.OnSuccess)
      {
        $trigger_tasks = $this.ResolveTriggerTaskIDs()
        foreach ($taskID in $trigger_tasks)
        {
          if (($taskID) -And (-Not (Invoke-QlikGet "/qrs/compositeevent?filter=compositeRules.reloadTask.id eq $taskID and reloadTask.id eq $($item.id)")))
          {
            Write-Verbose "Trigger for OnSuccess event of task $taskID does not exist"
            Add-QlikTrigger -taskId $item.id -OnSuccess $trigger_tasks
          }
          else
          {
            Write-Warning "Can't add trigger for non-existent task"
          }
        }
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

    #if ($this.OnSuccess -And (-Not (Invoke-QlikGet "/qrs/compositeevent?filter=compositeRules.reloadTask.id eq $($this.OnSuccess) and reloadTask.id eq $($item.id)")))
    if ($this.OnSuccess)
    {
      $trigger_tasks = $this.ResolveTriggerTaskIDs()
      foreach ($taskID in $trigger_tasks)
      {
        if (($taskID) -And (-Not (Invoke-QlikGet "/qrs/compositeevent?filter=compositeRules.reloadTask.id eq $taskID and reloadTask.id eq $($item.id)")))
        {
          Write-Verbose "Trigger for OnSuccess event of task $taskID does not exist"
          $result = $false
        }
      }
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

  [string[]] ResolveTriggerTaskIDs()
  {
    $trigger_tasks = @()
    foreach ($value in $this.OnSuccess)
    {
      if ($value -Match "^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$")
      {
        Write-Verbose "Adding $value to OnSuccess for task trigger"
        $trigger_tasks += $value
      }
      elseif ($value.SubString(0, 1) -eq '{')
      {
        Write-Verbose "Executing script block to resolve OnSuccess task trigger"
        $trigger_tasks += [scriptblock]::Create($value).InvokeReturnAsIs().id
      }
      else
      {
        Write-Verbose "Adding tasks matching ""$value"" to OnSuccess task trigger"
        $trigger_tasks += (Get-QlikTask -filter $value -raw).id
      }
    }
    return $trigger_tasks
  }
}

[DscResource()]
class QlikVirtualProxy{

  [DscProperty(Mandatory)]
  [string]$Prefix

  [DscProperty(Key)]
  [string]$Description

  [DscProperty(Mandatory)]
  [string]$SessionCookieHeaderName

  [DscProperty(Mandatory=$false)]
  [string]$authenticationModuleRedirectUri

  [DscProperty(Mandatory=$false)]
  [string]$loadBalancingServerNodes

  [DscProperty(Mandatory=$false)]
  [string[]]$websocketCrossOriginWhiteList

  [DscProperty()]
  [string]$additionalResponseHeaders

  [DscProperty(Mandatory=$false)]
  [string[]]$proxy

  [DscProperty(Mandatory=$false)]
  [ValidateSet("Ticket","static","dynamic","SAML","JWT", IgnoreCase=$false)]
  [string]$authenticationMethod

  [DscProperty()]
  [string]$WindowsAuthenticationEnabledDevicePattern

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
  [hashtable]$samlAttributeMapMandatory

  [DscProperty(Mandatory=$false)]
  [hashtable]$samlAttributeMapOptional

  [DscProperty(Mandatory=$false)]
  [bool]$samlSlo

  [DscProperty(Mandatory=$false)]
  [string]$samlMetadataExportPath

  [DscProperty(Mandatory=$false)]
  [Int]$sessionInactivityTimeout

  [DscProperty(Mandatory)]
  [Ensure]$Ensure

  [void] Set()
  {
    $item = $(Get-QlikVirtualProxy -full -filter "Description eq '$($this.Description)'")
    $present = $item -ne $null

    if($this.ensure -eq [Ensure]::Present)
    {
      $engines = Get-QlikNode -raw -filter $this.loadBalancingServerNodes | foreach { $_.id } | ? { $_ }
      $params = @{
        Description = $this.Description
        SessionCookieHeaderName = $this.SessionCookieHeaderName
      }
      If( $this.Prefix.Trim('/') ) { $params.Add("prefix", $this.Prefix.Trim('/')) }
      If( @($engines).Count -ne $item.loadBalancingServerNodes.Count ) { $params.Add("loadBalancingServerNodes", $engines) }
      If( $this.websocketCrossOriginWhiteList ) { $params.Add("websocketCrossOriginWhiteList", $this.websocketCrossOriginWhiteList) }
      If( $this.additionalResponseHeaders ) { $params.Add("additionalResponseHeaders", $this.additionalResponseHeaders) }
      If( $this.authenticationModuleRedirectUri ) { $params.Add("authenticationModuleRedirectUri", $this.authenticationModuleRedirectUri) }
      If( $this.authenticationMethod ) { $params.Add("authenticationMethod", $this.authenticationMethod) }
      If( $this.WindowsAuthenticationEnabledDevicePattern ) { $params.Add("windowsAuthenticationEnabledDevicePattern", $this.WindowsAuthenticationEnabledDevicePattern) }
      If( $this.samlMetadataIdP ) { $params.Add("samlMetadataIdP", $this.samlMetadataIdP) }
      If( $this.samlHostUri ) { $params.Add("samlHostUri", $this.samlHostUri) }
      If( $this.samlEntityId ) { $params.Add("samlEntityId", $this.samlEntityId) }
      If( $this.samlAttributeUserId ) { $params.Add("samlAttributeUserId", $this.samlAttributeUserId) }
      If( $this.samlAttributeUserDirectory ) { $params.Add("samlAttributeUserDirectory", $this.samlAttributeUserDirectory) }
      If( $this.samlAttributeMapMandatory -Or $this.samlAttributeMapOptional ) {
        $attributes = @()
        foreach ($attr in $this.samlAttributeMapOptional.keys) {
          $attributes += @{
            samlAttribute = $attr
            senseAttribute = $this.samlAttributeMapOptional.$attr
          }
        }
        foreach ($attr in $this.samlAttributeMapMandatory.keys) {
          $attributes += @{
            samlAttribute = $attr
            senseAttribute = $this.samlAttributeMapMandatory.$attr
            isMandatory = $true
          }
        }
        $params.Add("samlAttributeMap", $attributes)
      }
      if( $this.samlSlo -ne $item.samlSlo ) { $params.Add("samlSlo", $this.samlSlo) }
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
          $qp = Get-QlikProxy -raw -full -filter "serverNodeConfiguration.hostName eq '$_'"
          $existing = $qp.settings.virtualProxies.id -join ', '
          Write-Verbose "Existing linked virtual proxies for $_`: $existing"
          Write-Verbose "Virtual proxy ID: $($item.id)"
          if( $qp.settings.virtualProxies.id -notcontains $item.id ) {
            Add-QlikProxy $qp.id $item.id
          }
        }
        if( $this.samlMetadataExportPath )
        {
          $err = $null
          for ($i = 0; $i -lt 5; $i++) {
            Try {
              Export-QlikMetadata -id $item.id -filename $this.samlMetadataExportPath -ErrorAction Ignore -ErrorVariable err
              break
            } Catch {
              if ($_.exception.response.statuscode -eq 'NotFound') {
                Start-Sleep -Seconds 10
              } else {
                Write-Verbose "Status: $($_.innerexception.response.statuscode)"
                Throw $_
              }
            }
          }
          if ($err) {
            Throw $err
          }
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
    $item = Get-QlikVirtualProxy -full -filter "Description eq '$($this.Description)'"
    $present = $item -ne $null

    if($this.Ensure -eq [Ensure]::Present)
    {
      if($present) {
        if($this.hasProperties($item))
        {
          if((! $this.samlMetadataExportPath) -Or (Test-Path $this.samlMetadataExportPath)) {
            return $true
          } else {
            Write-Verbose "File not found at $($this.samlMetadataExportPath)"
            return $false
          }
        } else {
          return $false
        }
      } else {
        Write-Verbose -Message "VirtualProxy should be present but was not found"
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
    $item = $(Get-QlikVirtualProxy -full -filter "Description eq '$($this.Description)'")
    $present = $item -ne $null
    if ($present)
    {
      $this.Description = $item.Description
      $this.SessionCookieHeaderName = $item.SessionCookieHeaderName
      $this.authenticationModuleRedirectUri = $item.authenticationModuleRedirectUri
      $this.loadBalancingServerNodes = $item.loadBalancingServerNodes
      $this.websocketCrossOriginWhiteList = $item.websocketCrossOriginWhiteList
      $this.additionalResponseHeaders = $item.additionalResponseHeaders
      $this.authenticationMethod = $item.authenticationMethod
      $this.samlMetadataIdP = $item.samlMetadataIdP
      $this.samlHostUri = $item.samlHostUri
      $this.samlEntityId = $item.samlEntityId
      $this.samlAttributeUserId = $item.samlAttributeUserId
      $this.samlAttributeUserDirectory = $item.samlAttributeUserDirectory
      $this.samlAttributeMapMandatory = @{}
      $item.samlAttributeMap.Where{$_.isMandatory}.ForEach{$this.samlAttributeMapMandatory[$_.samlAttribute]=$_.senseAttribute}
      $this.samlAttributeMapOptional = @{}
      $item.samlAttributeMap.Where{!$_.isMandatory}.ForEach{$this.samlAttributeMapOptional[$_.samlAttribute]=$_.senseAttribute}
      $this.samlSlo = $item.samlSlo
      $this.sessionInactivityTimeout = $item.sessionInactivityTimeout
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
    if( !(CompareProperties $this $item @( 'SessionCookieHeaderName', 'authenticationModuleRedirectUri',
        'samlMetadataIdP', 'samlHostUri', 'samlEntityId', 'samlAttributeUserId', 'samlAttributeUserDirectory', 'samlSlo',
        'sessionInactivityTimeout', 'WindowsAuthenticationEnabledDevicePattern', 'additionalResponseHeaders' ) ) )
    {
      return $false
    }

    if($this.Prefix -And ($this.Prefix.Trim('/') -ne $item.prefix)) {
        Write-Verbose "Test-HasProperties: prefix - $($item.prefix) does not match desired state - $($this.Prefix.Trim('/'))"
        return $false
    }

    if($this.authenticationMethod) {
        If([authenticationMethod]$this.authenticationMethod -ne [authenticationMethod]$item.authenticationMethod) {
            Write-Verbose "Test-HasProperties: authenticationMethod - $($item.authenticationMethod) does not match desired state - $($this.authenticationMethod)"
            return $false
        }
    }

    if($this.loadBalancingServerNodes) {
        $nodes = Get-QlikNode -filter $this.loadBalancingServerNodes | foreach { $_.id } | ? { $_ }
        $configured = [pscustomobject[]]$item.loadBalancingServerNodes
        if ($nodes.Count -ne $configured.Count) {
            Write-Verbose "Test-HasProperties: loadBalancingServerNodes property count - $($configured.Count) does not match desired state - $(@($nodes).Count)"
            return $false
        }
        if ($nodes.Count -ne 0 -and $configured.Count -ne 0) {
            if (($diffs = Compare-Object $nodes $configured.id).Length -ne 0) {
                Write-Verbose "Test-HasProperties: loadBalancingServerNodes has $($diffs.Length) differences"
                return $false
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

    if($this.samlAttributeMapMandatory -Or $this.samlAttributeMapOptional) {
        foreach ($attr in $this.samlAttributeMapMandatory.Keys) {
            $found = $false
            foreach($existing in $item.samlAttributeMap) {
                if (($attr -eq $existing.samlAttribute) -And
                    (($this.samlAttributeMapMandatory.$attr -eq $existing.senseAttribute) -And
                    ($existing.isMandatory -eq $true))) {
                    $found = $true
                }
            }
            if (! $found) {
                Write-Verbose "Test-HasProperties: No match found for mandatory SAML attribute $($attr.samlAttribute)"
                return $false
            }
        }
        foreach ($attr in $this.samlAttributeMapOptional.Keys) {
            $found = $false
            foreach($existing in $item.samlAttributeMap) {
                if (($attr -eq $existing.samlAttribute) -And
                    (($this.samlAttributeMapOptional.$attr -eq $existing.senseAttribute) -And
                    ($existing.isMandatory -eq $false))) {
                    $found = $true
                }
            }
            if (! $found) {
                Write-Verbose "Test-HasProperties: No match found for optional SAML attribute $($attr.samlAttribute)"
                return $false
            }
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
    [ValidateRange(0,256)]
    [Int]$CoresToAllocate

    [DscProperty()]
    [Bool]$AllowDataLineage

    [DscProperty()]
    [Bool]$StandardReload

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$auditActivityLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$auditSecurityLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$systemLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$externalServicesLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$qixPerformanceLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$serviceLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$httpTrafficLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$auditLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$trafficLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$sessionLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$performanceLogVerbosity

    [DscProperty()]
    [ValidateRange(0, 5)]
    [int]$sseLogVerbosity

    [Void] Set () {
        Write-Verbose "Get Qlik Engine: $($this.Node)"
        $item = Get-QlikEngine -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item.id) {
            $engparams = @{
                "id" = $item.id
                auditActivityLogVerbosity = $this.auditActivityLogVerbosity
                auditSecurityLogVerbosity = $this.auditSecurityLogVerbosity
                systemLogVerbosity = $this.systemLogVerbosity
                externalServicesLogVerbosity = $this.externalServicesLogVerbosity
                qixPerformanceLogVerbosity = $this.qixPerformanceLogVerbosity
                serviceLogVerbosity = $this.serviceLogVerbosity
                httpTrafficLogVerbosity = $this.httpTrafficLogVerbosity
                auditLogVerbosity = $this.auditLogVerbosity
                trafficLogVerbosity = $this.trafficLogVerbosity
                sessionLogVerbosity = $this.sessionLogVerbosity
                performanceLogVerbosity = $this.performanceLogVerbosity
                sseLogVerbosity = $this.sseLogVerbosity
            }
            if($this.DocumentDirectory) { $engparams.Add("documentDirectory", $this.DocumentDirectory) }
            if($this.DocumentTimeout) { $engparams.Add("documentTimeout", $this.DocumentTimeout) }
            if($this.MinMemUsage) { $engparams.Add("workingSetSizeLoPct", $this.MinMemUsage) }
            if($this.MaxMemUsage) { $engparams.Add("workingSetSizeHiPct", $this.MaxMemUsage) }
            if($this.MemUsageMode) { $engparams.Add("workingSetSizeMode", $this.MemUsageMode) }
            if($this.CpuThrottle) { $engparams.Add("cpuThrottlePercentage", $this.CpuThrottle) }
            if($this.CoresToAllocate) { $engparams.Add("coresToAllocate", $this.CoresToAllocate) }
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
        if($PSBoundParameters.ContainsKey('AllowDataLineage') -And ($item.settings.allowDataLineage -ne $this.AllowDataLineage)) {
            Write-Verbose "Test-HasProperties: Allow data lineage property value - $($item.settings.allowDataLineage) does not match desired state - $($this.AllowDataLineage)"
            $desiredState = $false
        }
        if($PSBoundParameters.ContainsKey('StandardReload') -And ($item.settings.standardReload -ne $this.StandardReload)) {
            Write-Verbose "Test-HasProperties: Standard reload property value - $($item.settings.standardReload) does not match desired state - $($this.StandardReload)"
            $desiredState = $false
        }
        $logLevels = @(
            'auditActivityLogVerbosity',
            'auditSecurityLogVerbosity',
            'systemLogVerbosity',
            'externalServicesLogVerbosity',
            'qixPerformanceLogVerbosity',
            'serviceLogVerbosity',
            'httpTrafficLogVerbosity',
            'auditLogVerbosity',
            'trafficLogVerbosity',
            'sessionLogVerbosity',
            'performanceLogVerbosity',
            'sseLogVerbosity'
        )
        if (-Not (CompareProperties $this $item.settings $logLevels))
        {
          return $false
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

  [DscProperty()]
  [string] $EncryptionKeyThumbprint

  [DscProperty()]
  [bool] $EnableEncryptQvf

  [DscProperty()]
  [bool] $EnableEncryptQvd

  [void] Set()
  {
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw -full
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
        if ($this.EncryptionKeyThumbprint) { $params.Add("encryptionKeyThumbprint", $this.EncryptionKeyThumbprint) }
        $params.Add("enableEncryptQvf", $this.EnableEncryptQvf)
        $params.Add("enableEncryptQvd", $this.EnableEncryptQvd)

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
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw -full
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
    $item = Get-QlikServiceCluster -filter "name eq '$($this.Name)'" -raw -full
    if ($item -ne $null)
    {
      $this.Ensure = [Ensure]::Present
      $this.PersistenceType = $item.settings.PersistenceType
      $this.PersistenceMode = $item.settings.PersistenceMode
      $this.RootFolder = $item.settings.RootFolder
      $this.AppFolder = $item.settings.AppFolder
      $this.StaticContentRootFolder = $item.settings.StaticContentRootFolder
      $this.Connector32RootFolder = $item.settings.Connector32RootFolder
      $this.Connector64RootFolder = $item.settings.Connector64RootFolder
      $this.ArchivedLogsRootFolder = $item.settings.ArchivedLogsRootFolder
      $this.EncryptionKeyThumbprint = $item.settings.encryption.EncryptionKeyThumbprint
      $this.EnableEncryptQvf = $item.settings.encryption.EnableEncryptQvf
      $this.EnableEncryptQvd = $item.settings.encryption.EnableEncryptQvd
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
    if (-Not (CompareProperties $this $item.settings.encryption @('encryptionKeyThumbprint', 'enableEncryptQvf', 'enableEncryptQvd')))
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
    $item = Get-QlikStream -full -raw -filter "name eq '$($this.Name)'"
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
    $item = Get-QlikStream -full -raw -filter "name eq '$($this.Name)'"
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
    $item = Get-QlikStream -full -raw -filter "name eq '$($this.Name)'"
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
