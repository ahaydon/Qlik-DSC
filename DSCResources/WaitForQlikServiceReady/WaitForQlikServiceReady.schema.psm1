Configuration WaitForQlikServiceReady {
    Param (
        [string] $Hostname,
        [int] $Retries = 40,
        [int] $RetryDelay = 15
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    WaitForQlikResource $Hostname {
        Name         = "ServiceReady-$Hostname"
        ResourceType = 'ServiceStatus'
        Condition    = "serverNodeConfiguration.hostname eq '$Hostname' and (serviceState eq Running or serviceState eq Disabled)"
        Count        = 5
        Retries      = $Retries
        RetryDelay   = $RetryDelay
    }
}
