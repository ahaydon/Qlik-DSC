enum Ensure {
    Absent
    Present
}

enum RefreshPolicy {
    Always
    Never
    ExpiredOrInvalid
}

[DscResource()]
class QlikLicense{

    [DscProperty(Key)]
    [ValidateLength(16, 16)]
    [string]
    $Serial

    [DscProperty()]
    [ValidateLength(5, 5)]
    [string]
    $Control

    [DscProperty(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name

    [DscProperty(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Organization

    [DscProperty()]
    [string]
    $Lef

    [DscProperty()]
    [string]
    $Key

    [DscProperty()]
    [ValidateNotNullOrEmpty()]
    [RefreshPolicy]
    $RefreshLef = 'ExpiredOrInvalid'

    [DscProperty(Mandatory)]
    [Ensure]
    $Ensure

    [void] Set() {
        $SetLicenseParams = @{
            Name = $this.Name
            Organization = $this.Organization
        }

        if ($this.Ensure -eq [Ensure]::Present) {
            if ($this.Control) {
                $SetLicenseParams.Control = $this.Control
                $SetLicenseParams.Serial = $this.Serial
            }

            if ($this.Lef) {
                $SetLicenseParams.Lef = $this.Lef
            }

            if ($this.Key) {
                $SetLicenseParams.Key = $this.Key
            }

            Set-QlikLicense @SetLicenseParams
        }
        else {
            $license = Get-QlikLicense
            Write-Verbose -Message "Deleting license $($license.Serial)"
            Invoke-QlikDelete "/qrs/license/$($license.id)"
        }
    }

    [bool] Test() {
        $License = Get-QlikLicense
        Write-Verbose "Serial: $($License.Serial)"
        if($this.Ensure -eq [Ensure]::Present) {
            if ((! $License) -or $License -eq 'null') {
                Write-Verbose 'No license found but should be Present'
                return $false
            }

            if ($License.Serial.Length -eq 0 -or $License.Serial.Replace(' ', '') -ne $this.Serial.Replace(' ', '')) {
                Write-Verbose "Serial number does not match. Desired: $($this.Serial), Actual: $($License.serial)"
                return $false
            }

            if ($License.Name -ne $this.Name) {
                Write-Verbose "User name does not match. Desired: $($this.Name), Actual: $($License.name)"
                return $false
            }

            if ($License.Organization -ne $this.Organization) {
                Write-Verbose "Organization does not match. Desired: $($this.Organization), Actual: $($License.Organization)"
                return $false
            }

            if ($this.Key) {
                if ($License.Key -ne $this.Key) {
                    Write-Verbose "Signed license key does not match. Desired: $($this.Key), Actual: $($License.key)"
                    return $false
                }
            }
            elseif (! $this.Control) {
                throw [System.Management.Automation.ValidationMetadataException] 'One of Key or Control must be provided.'
            }

            if ($this.Lef) {
                if ($this.Lef -ne $License.lef) {
                    Write-Verbose "LEF does not match. Desired: $($this.Lef), Actual: $($License.lef)"
                    return $false
                }
            }
            elseif ($this.RefreshLef -eq [RefreshPolicy]::Always -or 
                ($this.RefreshLef -eq [RefreshPolicy]::ExpiredOrInvalid -and ($License.isExpired -or $License.isInvalid))) {

                Write-Verbose 'Checking for updated LEF'
                $query = 'serial={0}&control={1}&user={2}&org={3}' -f
                    $this.Serial,
                    $this.Control,
                    $this.Name,
                    $this.Organization
                $LatestLef = Invoke-QlikGet "/qrs/license/download?$query"

                if ($LatestLef -ne $License.lef) {
                    Write-Verbose "Newer LEF is available. Current: $($License.Lef), Latest: $LatestLef"
                    return $false
                }
            }
        }
        elseif ($License.id) {
            Write-Verbose "License is Present but should be Absent"
            return $false
        }

        Write-Verbose 'License is in desired state'
        return $true
    }

    [QlikLicense] Get() {
        $license = Get-QlikLicense
        if ($license.serial) {
            $this.Serial = $license.serial.Replace(' ', '')
            $this.Ensure = [Ensure]::Present
        }
        else {
            $this.Ensure = [Ensure]::Absent
        }
        $this.Name = $license.name
        $this.Organization = $license.organization
        $this.Lef = $license.lef
        $this.Key = $license.key

        return $this
    }
}
