enum Ensure {
  Absent
  Present
}

[DscResource()]
class QlikPackage {

    [DscProperty()]
    [String]$Name

    [DscProperty(Key)]
    [string]$Setup

    [DscProperty()]
    [string]$Patch

    [DscProperty(Mandatory)]
    [Ensure]$Ensure

    [DscProperty()]
    [string]$Log

    [DscProperty()]
    [Bool]$DesktopShortcut

    [DscProperty()]
    [Bool]$SkipStartServices

    [DscProperty()]
    [Bool]$SkipValidation

    [DscProperty()]
    [string]$InstallDir

    [DscProperty(Mandatory)]
    [PSCredential]$ServiceCredential

    [DscProperty()]
    [PSCredential]$DbSuperUserPassword

    [DscProperty()]
    [String]$Hostname

    [DscProperty()]
    [PSCredential]$DbCredential

    [DscProperty()]
    [string]$DbHost

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [int]$DbPort

    [DscProperty()]
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
    [string]$ListenAddresses

    [DscProperty()]
    [string]$IpRange

    [DscProperty()]
    [bool]$ConfigureLogging

    [DscProperty()]
    [bool]$SetupLocalLoggingDb

    [DscProperty()]
    [PSCredential]$QLogsWriterPassword

    [DscProperty()]
    [PSCredential]$QLogsReaderPassword

    [DscProperty()]
    [string]$QLogsHostname

    [DscProperty()]
    [ValidateRange(1, 65535)]
    [int]$QLogsPort

    [DscProperty()]
    [bool]$JoinCluster

    [DscProperty()]
    [Int]$ExitCode=0

    [DscProperty()]
    [bool]$AcceptEula

    [DscProperty()]
    [ValidateSet('Dashboard', 'Visualization')]
    [string[]]$BundleInstall

    [DscProperty()]
    [string] $SpcFilePath = "$env:temp\spc.cfg"

    [DscProperty(NotConfigurable)]
    [string] $ProductName

    [DscProperty(NotConfigurable)]
    [string] $PatchName

    [void] Set() {
        $currentState = $this.Get()
        if($this.Ensure -eq [Ensure]::Present) {
            Write-Debug "Setup: $($this.Setup)"
            $_productName = (Get-FileInfo $this.Setup).ProductName
            if ($currentState.ProductName -ne $_productName) {
                $installParams = @{
                    Path = $this.Setup
                    SkipStartServices = $this.SkipStartServices
                }
                $this_condensed = $this | Select-Object -Property $this.psobject.properties.Name.Where{ $this.$_ }
                if (! $currentState.ProductName) {
                    Write-Verbose "Installing $_productName"
                    $spc = $this_condensed | New-QlikSharedPersistenceConfiguration -Path $this.SpcFilePath
                    $installParams.SharedPersistenceConfig = $spc.FullName
                }
                else {
                    Write-Verbose "Upgrading from $($currentState.ProductName) to $_productName"
                }
                if ($this.Patch) {
                    Write-Verbose "Appending SkipStartServices to arguments as patch will be applied immediately after"
                    $installParams.SkipStartServices = $true
                }
                $this_condensed.psobject.properties.Name | ForEach-Object { Write-Debug "$_ : $($this_condensed.$_)"}
                $process = $this_condensed | Install-QlikPackage @installParams -ErrorAction Stop
            }
            else {
                Write-Verbose "Skipping install of $_productName as it is already installed"
            }

            if ($this.Patch) {
                $_productName = (Get-FileInfo $this.Patch).ProductName
                if ($currentState.PatchName -ne $_productName) {
                    Write-Verbose "Applying patch $_productName"
                    $process = Install-QlikPackage `
                        -Path $this.Patch `
                        -SkipStartServices:$this.SkipStartServices `
                        -Log $this.Log
                }
            }

            if (! $this.SkipStartServices) {
              Start-Service Qlik* -ErrorAction SilentlyContinue
            }
        } else {
            Write-Verbose "Uninstall $($this.Name)"
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
        if($env:USERNAME -eq "$env:COMPUTERNAME$") {
            Write-Error "$($this.Name) can not be installed by 'LOCAL SYSTEM', please use PsDscRunAsCredential property"
        }
        $packages = $this.Get()
        if($this.Ensure -eq [Ensure]::Present) {
            $product = (Get-FileInfo $this.Setup).ProductName
            Write-Debug "Installed: $($packages.ProductName)"
            Write-Debug "Desired: $product"
            if($packages.ProductName -ne $product -and $packages.PatchName -ne $product) {
                Write-Verbose "Package $product not installed."
                return $false
            }
            else {
                Write-Verbose "Package $product already installed."
            }
            if ($this.Patch) {
                $update = (Get-FileInfo $this.Patch).ProductName
                if($packages.PatchName -ne $update) {
                    Write-Verbose "Patch $update not installed."
                    return $false
                }
                else {
                    Write-Verbose "Patch $update already installed."
                }
            }
        } else {
            if ($packages.ProductName) {
                Write-Verbose "$($this.ProductName) is installed but should be absent."
                return $false
            }
            if ($packages.PatchName) {
                Write-Verbose "$($this.PatchName) is installed but should be absent."
                return $false
            }
        }
        return $true
    }

    [QlikPackage] Get() {
        $package = [QlikPackage]::new()
        $products = Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
            Where-Object { $_.DisplayName -match "^Qlik Sense" }
        if($products) {
            Write-Debug "Found $($products.Count) packages"
            $package.ProductName = $products | Where-Object { $_.DisplayName -notmatch 'Patch' } | Select-Object -ExpandProperty DisplayName
            $package.PatchName = $products | Where-Object { $_.DisplayName -match 'Patch' } | Select-Object -ExpandProperty DisplayName
            $package.Ensure = [Ensure]::Present
        } else {
            Write-Debug 'No packages found'
            $package.Ensure = [Ensure]::Absent
        }
        return $package
    }

}

function Install-QlikPackage {
    [CmdletBinding(DefaultParameterSetName = 'Patch')]
    param (
        # Mandatory parameters
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({Test-Path $_})]
        [System.IO.FileInfo]$Path,

        [Parameter(ParameterSetName = 'Install', Position = 1, ValueFromPipeline = $true)]
        [ValidateScript({Test-Path $_})]
        [Alias('spc')]
        [System.IO.FileInfo]$SharedPersistenceConfig,

        [Parameter(ParameterSetName = 'Install', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [switch]$AcceptEula,

        [Parameter(ParameterSetName = 'Install', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({$_.UserName.IndexOf('\') -gt 0})]
        [pscredential]$ServiceCredential,

        [Parameter(ParameterSetName = 'Install', ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-QlikRepositoryPassword})]
        [Alias('DbSuperUserPassword')]
        [pscredential]$DbPassword,

        # Optional parameters
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [System.IO.FileInfo]$Log,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$DesktopShortcut,
        [Parameter()]
        [switch]$SkipStartServices,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [System.IO.DirectoryInfo]$InstallDir,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$Hostname,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$SendData,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$SkipValidation,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-Path $_})]
        [System.IO.FileInfo]$DatabaseDumpFile,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateSet('Dashboard', 'Visualization')]
        [string[]]$BundleInstall,
        [Parameter()]
        [switch]$CleanUp
    )

    process {
        if ('Qlik_Sense_update.exe' -eq (Get-FileInfo $Path).OriginalFilename) {
            $Arguments = 'install'
            if (! $SkipStartServices.IsPresent) { $Arguments += ' startservices' }
            if ($Log) { $Arguments += " log=`"$Log`""}
        }
        else {
            $products = Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
                Where-Object { $_.DisplayName -match "^Qlik Sense" }
            $Arguments = '-silent'
            $Arguments += " userpassword=`"$($ServiceCredential.GetNetworkCredential().Password)`""
            if (! $products) {
                $Arguments += " userwithdomain=`"$($ServiceCredential.UserName)`""
                if ($SharedPersistenceConfig) { $Arguments += " sharedpersistenceconfig=`"$SharedPersistenceConfig`"" }
                if ($Hostname) { $Arguments += " hostname=`"$Hostname`"" }
                if ($SendData.IsPresent) { $Arguments += ' senddata=1' }
                if ($SkipValidation.IsPresent) { $Arguments += ' skipvalidation=1' }
                if ($DatabaseDumpFile) { $Arguments += " databasedumpfile=`"$DatabaseDumpFile`"" }
            }
            if ($AcceptEula.IsPresent) { $Arguments += ' accepteula=1' }
            if ($DbPassword) {
                $Arguments += (" dbpassword=`"{0}`"" -f ($DbPassword.GetNetworkCredential().Password))
            }
            if ($Log) { $Arguments += " -log `"$Log`""}
            if (!$DesktopShortcut.IsPresent) { $Arguments += ' desktopshortcut=0' }
            if ($SkipStartServices.IsPresent) { $Arguments += ' skipstartservices=1' }
            if ($InstallDir) { $Arguments += " installdir=`"$InstallDir`""}
            if ($BundleInstall) { $Arguments += " bundleinstall={0}" -f ($BundleInstall.ToLower() -join ',')}
            if ($CleanUp.IsPresent) { $Arguments += ' cleanup=1' }
        }

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.UseShellExecute = $false
        $startInfo.FileName = $Path.FullName
        $startInfo.Arguments = $Arguments

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo

        Write-Verbose "Starting `"$($startInfo.FileName)`" $($startInfo.Arguments -replace '(?<=password=")([^"]*)', '****')"
        $process.Start() | Out-Null
        $process.WaitForExit()
        if ($this.ExitCode -ne $process.ExitCode) {
            Write-Error "$($this.Name) installation failed with Exitcode: $($process.ExitCode)"
        }
        else {
            Write-Verbose "$($this.Name) installation finished with Exitcode: $($process.ExitCode)"
        }
        $process
    }
}

function New-QlikSharedPersistenceConfiguration {
    [CmdletBinding(DefaultParameterSetName = 'JoinCluster')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.IO.FileInfo]$Path,

        # Database parameters
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-QlikRepositoryPassword})]
        [pscredential]$DbCredential,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$DbHost,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, 65535)]
        [int]$DbPort,

        # Logging
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]$ConfigureLogging,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-QlikRepositoryPassword})]
        [pscredential]$QLogsWriterPassword,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-QlikRepositoryPassword})]
        [pscredential]$QLogsReaderPassword,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$QLogsHostname,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(1, 65535)]
        [int]$QLogsPort,

        # Share paths
        [Parameter(ParameterSetName = 'CreateCluster', Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$RootDir,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [string]$AppsDir = 'Apps',
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [string]$StaticContentRootDir = 'StaticContent',
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [string]$ArchivedLogsDir = 'Archived Logs',

        # Local DB
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [switch]$InstallLocalDb,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [switch]$ConfigureDbListener,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [string[]]$ListenAddresses,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [string[]]$IpRange,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [int]$MaxConnections,
        [Parameter(ParameterSetName = 'CreateCluster', ValueFromPipelineByPropertyName = $true)]
        [switch]$SetupLocalLoggingDb
    )

    process {
        foreach ($item in @('AppsDir', 'StaticContentRootDir', 'ArchivedLogsDir')) {
            if ($PSCmdlet.ParameterSetName -eq 'CreateCluster') {
                $value = Get-Variable -Name $item -ValueOnly
                if (! [System.IO.Path]::IsPathRooted($value)) {
                    $value = $RootDir.TrimEnd('\') + "\$value"
                    Set-Variable $item $value
                    Write-Verbose "$item path not rooted, resolving to $value"
                }
            }
            else {
                Set-Variable $item $null
            }
        }

        $xmlWriter = New-Object System.XMl.XmlTextWriter($Path.FullName, $Null)
        $xmlWriter.Formatting = [System.Xml.Formatting]::Indented
        $xmlWriter.WriteStartDocument()
        $xmlWriter.WriteStartElement('SharedPersistenceConfiguration')
        $xmlWriter.WriteAttributeString('xmlns', 'xsi', 'http://www.w3.org/2000/xmlns/', 'http://www.w3.org/2001/XMLSchema-instance')
        $xmlWriter.WriteAttributeString('xmlns', 'xsd', 'http://www.w3.org/2000/xmlns/', 'http://www.w3.org/2001/XMLSchema')

        $xmlWriter.WriteElementString($PSCmdlet.ParameterSetName, 'true')

        $ParameterList = $PSCmdlet.MyInvocation.MyCommand.Parameters.Keys |
            Where-Object { $_ -ne 'Path' -and $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters }

        foreach ($parameter in $ParameterList) {
            $value = Get-Variable -Name $parameter -ValueOnly -ErrorAction SilentlyContinue
            if (! $value) { continue }

            Write-Debug "$parameter : $value"
            switch ($value.GetType()) {
                'switch' {
                    $xmlWriter.WriteElementString($parameter, $value.ToString().ToLower())
                }
                'PSCredential' {
                    if ($parameter.SubString($parameter.Length - 10) -eq 'Credential') {
                        $name = $parameter.TrimEnd('Credential')
                        $xmlWriter.WriteElementString($name + 'UserName', $value.UserName)
                        $parameter = $name + 'UserPassword'
                    }
                    $xmlWriter.WriteElementString($parameter, $value.GetNetworkCredential().Password)
                }
                default {
                    $xmlWriter.WriteElementString($parameter, $value)
                }
            }
        }

        $xmlWriter.WriteEndElement()
        $xmlWriter.WriteEndDocument()
        $xmlWriter.Flush()
        $xmlWriter.Close()

        return Get-Item $Path
    }
}

function ConvertTo-PlainText {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [securestring]$SecureString
    )

    process {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        $plainpassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

        return $plainpassword
    }
}

function Get-FileInfo($Path) {
    Write-Debug "Path: $Path"
    [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
}

function Test-QlikRepositoryPassword() {
    if ($_ -is [securestring]) {
        $password = $_ | ConvertTo-PlainText
    }
    else {
        $password = $_.GetNetworkCredential().Password
    }

    if ($password.Length -eq 0) {
        return $false
    }
    if ($password.Contains('"')) {
        return $false
    }
    if ($password.Contains("'")) {
        return $false
    }
    if ($password.Contains(';')) {
        return $false
    }
    return $true
}
