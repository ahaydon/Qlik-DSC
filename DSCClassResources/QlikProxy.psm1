$ProjectRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ProjectRoot -ChildPath 'Private' | Join-Path -ChildPath 'Common.psm1') -Force

[DscResource()]
class QlikProxy {

    [DscProperty(Key)]
    [string]$Node

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [Int]$ListenPort

    [DscProperty()]
    [Bool]$AllowHttp

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [Int]$UnencryptedListenPort

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [Int]$AuthenticationListenPort

    [DscProperty()]
    [Bool]$KerberosAuthentication

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [Int]$UnencryptedAuthenticationListenPort

    [DscProperty()]
    [String]$SslBrowserCertificateThumbprint

    [DscProperty()]
    [ValidateRange(1, 300)]
    [Int]$KeepAliveTimeoutSeconds

    [DscProperty()]
    [ValidateRange(512, 131072)]
    [Int]$MaxHeaderSizeBytes

    [DscProperty()]
    [ValidateRange(20, 1000)]
    [Int]$MaxHeaderLines

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [Int]$RestListenPort

    [DscProperty()]
    [hashtable]$CustomProperties

    hidden [string]
    $SchemaPath = 'ProxyService'

    [Void] Set () {
        Write-Verbose "Get Qlik Proxy: $($this.Node)"
        $item = Get-QlikProxy -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($item.id) {
            $engparams = @{
                id = $item.id
                AllowHTTP = $this.AllowHttp
                KerberosAuthentication = $this.KerberosAuthentication
            }
            if($this.ListenPort) { $engparams.Add("listenPort", $this.ListenPort) }
            if($this.UnencryptedListenPort) { $engparams.Add("unencryptedListenPort", $this.UnencryptedListenPort) }
            if($this.AuthenticationListenPort) { $engparams.Add("authenticationListenPort", $this.AuthenticationListenPort) }
            if($this.UnencryptedAuthenticationListenPort) { $engparams.Add("unencryptedAuthenticationListenPort", $this.UnencryptedAuthenticationListenPort) }
            if($this.SslBrowserCertificateThumbprint) { $engparams.Add("sslBrowserCertificateThumbprint", $this.SslBrowserCertificateThumbprint) }
            if($this.KeepAliveTimeoutSeconds) { $engparams.Add("KeepAliveTimeoutSeconds", $this.KeepAliveTimeoutSeconds) }
            if($this.MaxHeaderSizeBytes) { $engparams.Add("MaxHeaderSizeBytes", $this.MaxHeaderSizeBytes) }
            if($this.MaxHeaderLines) { $engparams.Add("MaxHeaderLines", $this.MaxHeaderLines) }
            if($this.RestListenPort) { $engparams.Add("RestListenPort", $this.RestListenPort) }
            $props = ConfigurePropertiesAndTags($this)
            if ($props.CustomProperties) { $engparams.Add("CustomProperties", $props.CustomProperties)}
            if ($props.Tags) { $engparams.Add("Tags", $props.Tags)}
            Write-Verbose "Update Qlik Proxy: $($this.Node)"
            Update-QlikProxy @engparams
        } else {
            Write-Verbose "Qlik Proxy '$($this.Node)' not found!"
        }
    }

    [Bool] Test () {
        Write-Verbose "Get Qlik Proxy: $($this.Node)"
        $item = Get-QlikProxy -Full -Filter "serverNodeConfiguration.hostName eq '$($this.Node)'"
        if($null -ne $item) {
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
        if($null -ne $item) {
            $this.ListenPort = $item.settings.listenPort
            $this.AllowHttp = $item.settings.allowHttp
            $this.UnencryptedListenPort = $item.settings.unencryptedListenPort
            $this.AuthenticationListenPort = $item.settings.authenticationListenPort
            $this.KerberosAuthentication = $item.settings.kerberosAuthentication
            $this.UnencryptedAuthenticationListenPort = $item.settings.unencryptedAuthenticationListenPort
            $this.SslBrowserCertificateThumbprint = $item.settings.sslBrowserCertificateThumbprint
            $this.KeepAliveTimeoutSeconds = $item.settings.KeepAliveTimeoutSeconds
            $this.MaxHeaderSizeBytes = $item.settings.MaxHeaderSizeBytes
            $this.MaxHeaderLines = $item.settings.MaxHeaderLines
            $this.RestListenPort = $item.settings.RestListenPort
            $cp = @{}
            foreach ($property in $item.customProperties) {
                $cp.Add($property.definition.name, $property.Value)
            }
            $this.CustomProperties = $cp
        }
        return $this
    }

    [bool] hasProperties($item) {
        $props = @(
            'ListenPort',
            'AllowHttp',
            'UnencryptedListenPort',
            'AuthenticationListenPort',
            'KerberosAuthentication',
            'UnencryptedAuthenticationListenPort',
            'SslBrowserCertificateThumbprint',
            'KeepAliveTimeoutSeconds',
            'MaxHeaderSizeBytes',
            'MaxHeaderLines',
            'RestListenPort'
        )
        if( !(CompareProperties $this $item.settings $props ) ) {
            return $false
        }
        if( !(CompareProperties $this $item 'CustomProperties' ) ) {
            return $false
        }
        return $true
    }
}
