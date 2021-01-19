[DscResource()]
class WaitForQlikResource {
    [DscProperty(Key)]
    [string] $Name

    [DscProperty(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceType

    [DscProperty()]
    [string] $Condition

    [DscProperty()]
    [int] $Retries = 40

    [DscProperty()]
    [int] $RetryDelay = 15

    [DscProperty()]
    [int] $Count = 0
    
    # Gets the resource's current state.
    [WaitForQlikResource] Get() {
        $this.Count = (Invoke-QlikGet /qrs/$($this.ResourceType)/count -filter $this.Condition).Value
        return $this
    }
    
    # Sets the desired state of the resource.
    [void] Set() {
        $counter = 0
        while (($result = (Invoke-QlikGet "/qrs/$($this.ResourceType)/count" -filter $this.Condition).Value) -ne $this.Count) {
            $counter ++
            Write-Verbose "After $counter attempts there are $result resources matching condition"
            if ($counter -gt $this.Retries) {
                throw "$result resources not in desired state"
            }
            Start-Sleep -Seconds $this.RetryDelay
        }
        Write-Verbose "All $result resources are now matching condition"
    }
    
    # Tests if the resource is in the desired state.
    [bool] Test() {
        $result = (Invoke-QlikGet /qrs/$($this.ResourceType)/count -filter $this.Condition).Value
        return $result -eq $this.Count
    }
}
