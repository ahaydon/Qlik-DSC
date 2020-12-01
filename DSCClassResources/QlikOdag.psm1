[DscResource()]
class QlikOdag {
    [DscProperty(Key)]
    [string] $Name

    [DscProperty(Mandatory)]
    [bool] $Enabled

    [DscProperty()]
    [bool] $DynamicViewEnabled

    [DscProperty()]
    [int] $MaxConcurrentRequests

    [DscProperty()]
    [ValidateRange(0, 6)]
    [int] $LogLevel

    [DscProperty()]
    [int] $PurgeOlderThan

    [DscProperty()]
    [int] $AnonymousAppCleanup
    
    # Gets the resource's current state.
    [QlikOdag] Get() {
        $item = Invoke-QlikGet "/qrs/odagservice/full"

        $this.Enabled = $item.enabled
        $this.DynamicViewEnabled = $item.DynamicViewEnabled
        $this.MaxConcurrentRequests = $item.MaxConcurrentRequests
        $this.LogLevel = $item.LogLevel
        $this.PurgeOlderThan = $item.PurgeOlderThan
        $this.AnonymousAppCleanup = $item.AnonymousAppCleanup

        return $this
    }
    
    # Sets the desired state of the resource.
    [void] Set() {
        $params = @{
            Enabled = $this.Enabled
            DynamicViewEnabled = $this.DynamicViewEnabled
            MaxConcurrentRequests = $this.MaxConcurrentRequests
            LogLevel = $this.LogLevel
            PurgeOlderThan = $this.PurgeOlderThan
            AnonymousAppCleanup = $this.AnonymousAppCleanup
        }

        Update-QlikOdag @params
    }
    
    # Tests if the resource is in the desired state.
    [bool] Test() {
        $item = Invoke-QlikGet "/qrs/odagservice/full"

        if ($this.AnonymousAppCleanup -ne $item.AnonymousAppCleanup) { return $false }
        if ($this.DynamicViewEnabled -ne $item.DynamicViewEnabled) { return $false }
        if ($this.Enabled -ne $item.Enabled) { return $false }
        if ($this.LogLevel -ne $item.LogLevel) { return $false }
        if ($this.MaxConcurrentRequests -ne $item.MaxConcurrentRequests) { return $false }
        if ($this.PurgeOlderThan -ne $item.PurgeOlderThan) { return $false }

        return $true
    }
}
