Describe 'Administrator group members' {
    BeforeAll {
        $Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname
    }

    it 'Should include the Qlik admin user' {
        (Get-LocalGroupMember -Name Administrators).Name | Should -Contain "$Hostname\vagrant"
    }
    it 'Should not include the Qlik service user' {
        (Get-LocalGroupMember -Name Administrators).Name | Should -Not -Contain "$Hostname\qservice"
    }
}

Describe 'Qlik Sense installation' {
    it 'Should have the correct release and patch' {
        $products = (Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*').DisplayName

        $products | Should -Contain 'Qlik Sense May 2021'
        $products | Should -Contain 'Qlik Sense May 2021 Patch 3'
    }
}

Describe 'Qlik node' {
    BeforeAll {
        $Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname
        $Node = Get-QlikNode -filter "hostname eq '$Hostname'" -full
    }

    it 'Should have the engine service enabled' {
        $Node.engineEnabled | Should -BeTrue
    }
    it 'Should have the proxy service enabled' {
        $Node.proxyEnabled | Should -BeTrue
    }
    it 'Should have the printing service enabled' {
        $Node.printingEnabled | Should -BeTrue
    }
    it 'Should have the scheduler service enabled' {
        $Node.schedulerEnabled | Should -BeTrue
    }
}

Describe 'Qlik service status' {
    BeforeAll {
        $Hostname = ([System.Net.Dns]::GetHostEntry('localhost')).hostname
        $Status = Get-QlikServiceStatus -filter "serverNodeConfiguration.hostname eq '$Hostname' and serviceState eq Running"
    }

    it 'Should have all services running' {
        $Status | Should -HaveCount 5
    }
}

Describe 'Desired state configuration' {
    it 'Should be idempotent' {
        (Test-DscConfiguration -Detailed).InDesiredState | Should -BeTrue
    }
}
