Configuration WaitForQlikServiceReady {
    Param (
        [string] $Hostname,
        [int] $Retries = 40,
        [int] $RetryDelay = 15
    )

    WaitForQlikResource $Hostname {
        Name         = "ServiceReady-$Hostname"
        ResourceType = 'ServiceStatus'
        Condition    = "serverNodeConfiguration.hostname eq '$Hostname' and (serviceState eq Running or serviceState eq Disabled)"
        Count        = 5
        Retries      = $Retries
        RetryDelay   = $RetryDelay
    }
}
