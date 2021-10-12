$ProjectRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ProjectRoot -ChildPath 'Private' | Join-Path -ChildPath 'Common.psm1') -Force
Import-Module (Join-Path $ProjectRoot -ChildPath 'Private' | Join-Path -ChildPath 'Bootstrap.psm1') -Force

enum Ensure {
    Absent
    Present
}

[DscResource()]
class QlikNode{

    [DscProperty(Key)]
    [string]
    $HostName

    [DscProperty()]
    [string]
    $Name

    [DscProperty()]
    [string]
    $NodePurpose

    [DscProperty()]
    [hashtable]
    $CustomProperties

    [DscProperty()]
    [string[]]
    $Tags

    [DscProperty()]
    [Nullable[bool]]
    $Engine

    [DscProperty()]
    [Nullable[bool]]
    $Proxy

    [DscProperty()]
    [Nullable[bool]]
    $Scheduler

    [DscProperty()]
    [Nullable[bool]]
    $Printing

    [DscProperty()]
    [Nullable[bool]]
    $Failover

    [DscProperty(Mandatory)]
    [Ensure]
    $Ensure

    [void] Set() {
        $item = Get-QlikNode -full -filter "hostName eq '$($this.HostName)'"
        $present = $null -ne $item
        $Bootstrap = $null

        if ($this.ensure -eq [Ensure]::Present) {
            $params = @{
                engineEnabled = $this.Engine
                proxyEnabled = $this.Proxy
                schedulerEnabled = $this.Scheduler
                printingEnabled = $this.Printing
                Failover = $this.Failover
            }
            if ($this.Name) { $params.Add("Name", $this.Name) }
            if ($this.NodePurpose) { $params.Add("NodePurpose", $this.NodePurpose) }

            $props = ConfigurePropertiesAndTags($this)
            if ($props.CustomProperties) { $params.Add("CustomProperties", $props.CustomProperties)}
            if ($props.Tags) { $params.Add("Tags", $props.Tags)}

            if ($present) {
                if (-not $this.hasProperties($item)) {
                    Update-QlikNode -id $item.id @params
                }

                if ((Get-Service QlikSenseRepositoryService).Status -ne 'Running') {
                    $Bootstrap = Start-SenseBootstrap -Service Repository
                }
                else {
                    $counter = 0
                    while (Get-QlikServiceStatus -full -filter "serverNodeConfiguration.id eq $($item.id) and serviceType eq Repository and serviceState eq NoCommunication") {
                        $counter++
                        if ($counter -gt 20) { throw "Repository service status is NoCommunication" }
                        Start-Sleep -Seconds 15
                    }
                }

                if ($state = Get-QlikServiceStatus -full -filter "serverNodeConfiguration.id eq $($item.id) and serviceType eq Repository and serviceState ne Running") {
                    Write-Verbose "Repository service status is $($state.serviceState)"
                    $password = Invoke-QlikGet "/qrs/servernoderegistration/start/$($item.id)"
                    if ($password) {
                        Write-Verbose "Unlocking certificates on node"
                        $postParams = @{__pwd = "$password" }
                        Invoke-WebRequest -Uri "http://localhost:4570/certificateSetup" -Method Post -Body $postParams -UseBasicParsing > $null
                    }

                    if ($Bootstrap) {
                        $Bootstrap.WaitForExit()
                        if ($Bootstrap.ExitCode -ne 0) {
                            throw "Bootstrap exited with status $($Bootstrap.ExitCode)"
                        }
                    }
                }
            }
            else {
                if ((Get-Service QlikSenseRepositoryService).Status -ne 'Running') {
                    $Bootstrap = Start-SenseBootstrap -Service Repository
                }
                Register-QlikNode -hostName $this.HostName @params
                if ($Bootstrap) {
                    $Bootstrap.WaitForExit()
                    if ($Bootstrap.ExitCode -ne 0) {
                        throw "Bootstrap exited with status $($Bootstrap.ExitCode)"
                    }
                }
            }
        }
        else {
            Remove-QlikNode $item.id
        }
    }

    [bool] Test() {
        $item = Get-QlikNode -full -filter "hostName eq '$($this.HostName)'"
        $present = $null -ne $item

        if ($this.ensure -eq [Ensure]::Present) {
            if ($present) {
                if ($this.hasProperties($item)) {
                    if ($state = Get-QlikServiceStatus -full -filter "serverNodeConfiguration.id eq $($item.id) and serviceType eq Repository and serviceState ne Running") {
                        Write-Verbose "Repository service status is $($state.serviceState)"
                        return $false
                    }

                    Write-Verbose "Node with hostname of '$($this.HostName)' is present and correct"
                    return $true
                } else {
                    return $false
                }
            } else {
                Write-Verbose "Node not found with hostname of '$($this.HostName)', but should be present"
                return $false
            }
        } else {
            if ($present) {
                Write-Verbose "Node found with hostname of '$($this.HostName)', but should be absent"
                return $false
            }
            else {
                Write-Verbose "Node with hostname of '$($this.HostName)' is in desired state of absent"
                return $true
            }
        }
    }

    [QlikNode] Get() {
        $item = Get-QlikNode -raw -full -filter "hostName eq '$($this.HostName)'"
        $present = $null -ne $item

        if ($present) {
            $this.NodePurpose = $item.NodePurpose
            $this.CustomProperties = $item.CustomProperties
            $this.Tags = $item.Tags
            $this.Engine = $item.EngineEnabled
            $this.Proxy = $item.ProxyEnabled
            $this.Scheduler = $item.SchedulerEnabled
            $this.Printing = $item.PrintingEnabled
            $this.Failover = $item.FailoverCandidate
        }

        return $this
    }

    [bool] hasProperties($item) {
        if (! (CompareProperties $this $item @( 'NodePurpose', 'Tags', 'Name' ))) {
            return $false
        }

        if ($this.CustomProperties) {
            foreach ($defined in $this.CustomProperties) {
                $val = $defined.Split("=")
                $found = $false
                foreach ($exists in $item.customProperties) {
                    if ($exists.definition.name -eq $val[0]) {
                        if ($val[1] -eq "null" -Or $val[1] -ne $exists.value) {
                            Write-Verbose "Test-HasProperties: Custom property value - $($val[0])=$($exists.value) does not match desired state - $($val[1])"
                            return $false
                        }
                        else {
                            $found = $true
                        }
                    }
                }

                if (-not $found) {
                    return $false
                }
            }
        }

        if ($null -ne $this.Engine -and $item.EngineEnabled -ne $this.Engine) {
            Write-Verbose "Test-HasProperties: Engine property value - $($item.EngineEnabled) does not match desired state - $($this.Engine)"
            return $false
        }

        if ($null -ne $this.Proxy -and $item.ProxyEnabled -ne $this.Proxy) {
            Write-Verbose "Test-HasProperties: Proxy property value - $($item.ProxyEnabled) does not match desired state - $($this.Proxy)"
            return $false
        }

        if ($null -ne $this.Scheduler -and $item.SchedulerEnabled -ne $this.Scheduler) {
            Write-Verbose "Test-HasProperties: Scheduler property value - $($item.SchedulerEnabled) does not match desired state - $($this.Scheduler)"
            return $false
        }

        if ($null -ne $this.Printing -and $item.PrintingEnabled -ne $this.Printing) {
            Write-Verbose "Test-HasProperties: Printing property value - $($item.PrintingEnabled) does not match desired state - $($this.Printing)"
            return $false
        }

        if ($null -ne $this.Failover -and $item.failover -ne $this.Failover) {
            Write-Verbose "Test-HasProperties: Failover property value - $($item.Failover) does not match desired state - $($this.Failover)"
            return $false
        }

        return $true
    }
}
