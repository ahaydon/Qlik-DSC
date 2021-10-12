Describe 'Cluster root folder' {
    it 'Should exist at C:\QlikShare' {
        Test-Path -Path C:\QlikShare -PathType Container | Should -BeTrue
    }
}

Describe 'Cluster share' {
    it 'Should resolve to C:\QlikShare' {
        (Get-SmbShare -Name QlikShare).Path | Should -Be 'C:\QlikShare'
    }
}

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

Describe 'Qlik Sense license' {
    it 'Should have a serial number' {
        (Get-QlikLicense).serial | Should -Not -BeNullOrEmpty
    }
}

Describe 'Desired state configuration' {
    it 'Should be idempotent' {
        (Test-DscConfiguration -Detailed).InDesiredState | Should -BeTrue
    }
}
