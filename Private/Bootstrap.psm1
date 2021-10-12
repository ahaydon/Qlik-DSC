function Get-ServicePath {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(
            Position = 0,
            ValueFromPipelineByPropertyName = $true
        )]
        [string[]]
        $Name,

        [Parameter()]
        [string]
        $Filter = 'Name like "{0}"'
    )

    begin {
        $Query = $null
        $Names = @()
    }

    process {
        if ($input) {
            $Names += $Name
        }
        elseif ($Name) {
            $Query = $Filter -f ($Name -replace '\*', '%')
            Write-Verbose "WQL = $Query"
        }
    }

    end {
        $Services = @(Get-CimInstance -ClassName Win32_Service -Property PathName -Filter $Query)
        Write-Verbose "Found $($Services.Count) services"
        if ($Names.Count) {
            $Services = @($Services | Where-Object Name -in $Names)
            Write-Verbose "Filtering services, input=$($Names.Count), output=$($Services.Count)"
        }
        foreach ($PathName in $Services.PathName) {
            $PathMatch = ($PathName | Select-String '"([^\"]*)"|[^\s]*').Matches[0]
            if ($PathMatch.Groups[1].Success) {
                $Path = $PathMatch.Groups[1].Value
            }
            else {
                $Path = $PathMatch.Groups[0].Value
            }
            Write-Verbose "Service path resolved to $Path"
            [System.IO.FileInfo]$Path
        }
    }
}

function Start-SenseBootstrap {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('Name')]
        [ValidateSet('Repository', 'Proxy', 'Scheduler')]
        [string]
        $Service,

        [Parameter()]
        [switch]
        $IsCentral,

        [Parameter()]
        [switch]
        $RestoreHostname
    )

    process {
        Write-Verbose "Starting bootstrap of $Service service"
        $Arguments = '-bootstrap -standalone'
        if ($RestoreHostname.IsPresent) {
            $Arguments += '-restorehostname'
        }
        if ($IsCentral.IsPresent) {
            $Arguments += '-iscentral'
        }

        $ServiceName = "QlikSense${Service}Service"
        $ServicePath = Get-ServicePath -Name $ServiceName

        if ((Get-Service $ServiceName).Status -eq 'Running') {
            Write-Verbose "Stopping service $ServiceName"
            Stop-Service -Name $ServiceName -Force
        }
        if ($ServiceName -ne 'QlikSenseRepositoryService') {
            Start-Service -Name QlikSenseRepositoryService
        }
        Write-Verbose 'Starting service QlikSenseServiceDispatcher'
        Start-Service -Name QlikSenseServiceDispatcher

        $process = RunShellCommand -FileName $ServicePath -Arguments $Arguments
        $lineCount = 0

        while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
            if (! $line) {
                continue
            }

            Write-Verbose $line
            if ($line -match 'Waiting for certificates to be installed') {
                return $process
            }

            $lineCount++
        }

        if ($process.ExitCode -ne 0) {
            Write-Error "Bootstrap failed with Exitcode: $($process.ExitCode)"
        }
        Write-Verbose "Bootstrap job completed"
    }
}

function RunShellCommand {
    param (
        $FileName,
        $Arguments
    )

    process {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.UseShellExecute = $false
        $startInfo.FileName = $FileName
        $startInfo.WorkingDirectory = ([System.IO.FileInfo]$FileName).DirectoryName
        $startInfo.CreateNoWindow = $true
        $startInfo.Arguments = $Arguments
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo

        Write-Verbose "Starting `"$($startInfo.FileName)`" with arguments ($($startInfo.Arguments))"
        $process.Start() | Out-Null
        $process
    }
}
