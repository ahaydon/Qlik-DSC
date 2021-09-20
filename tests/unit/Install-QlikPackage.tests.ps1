$ProjectRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$modulePath = Join-Path $ProjectRoot -ChildPath 'DSCClassResources' | Join-Path -ChildPath 'QlikPackage.psm1'
Import-Module $modulePath -Force

class DummyProcess {
    [System.Diagnostics.ProcessStartInfo]
    $StartInfo

    [void]
    Start() {}

    [void]
    WaitForExit() {}
}

Describe "Install-QlikPackage" {
    BeforeEach {
        $proc = [DummyProcess]::new()
        Mock New-Object -ModuleName QlikPackage -ParameterFilter { $TypeName -eq 'System.Diagnostics.Process' } { return $proc }.GetNewClosure()
        Mock Test-Path -ModuleName QlikPackage { $true }
    }

    Context 'Install' {
        BeforeAll {
            Mock Get-ItemProperty -ModuleName QlikPackage
            Mock Get-FileInfo -ModuleName QlikPackage { @{OriginalFilename = 'Qlik_Sense_setup.exe'; ProductName = 'Qlik Sense November 2020'} }
        }

        Describe 'When installing a package' {
            It 'Should pass arguments to the setup process' {
                $password = ConvertTo-SecureString -String 'password' -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                Install-QlikPackage `
                    -Path 'Qlik_Sense_setup.exe' `
                    -SharedPersistenceConfig $TestDrive\spc.cfg `
                    -AcceptEula `
                    -ServiceCredential $credential `
                    -DbPassword $credential

                $proc.StartInfo.Arguments | Should -Match '-silent'
                $proc.StartInfo.Arguments | Should -Match 'accepteula=1'
                $proc.StartInfo.Arguments | Should -Match 'userwithdomain=".\\qservice"'
                $proc.StartInfo.Arguments | Should -Match 'userpassword="password"'
                $proc.StartInfo.Arguments | Should -Match 'dbpassword="password"'
                $proc.StartInfo.Arguments | Should -Match "sharedpersistenceconfig=`"$($TestDrive -replace '\\', '\\')\\spc.cfg`""
            }
        }

        Describe 'When using special characters in a password' {
            BeforeAll {
                $install = {
                    $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                    Install-QlikPackage `
                        -Path 'Qlik_Sense_setup.exe' `
                        -SharedPersistenceConfig $TestDrive\spc.cfg `
                        -AcceptEula `
                        -ServiceCredential $credential `
                        -DbPassword $credential
                }
            }

            It 'Should reject quote character in db password' {
                $password = ConvertTo-SecureString -String 'pass"word' -AsPlainText -Force
                $install.GetNewClosure() | Should -Throw
            }

            It 'Should reject apostrophe character in db password' {
                $password = ConvertTo-SecureString -String "pass'word" -AsPlainText -Force
                $install.GetNewClosure() | Should -Throw
            }

            It 'Should reject semicolon character in db password' {
                $password = ConvertTo-SecureString -String 'pass;word' -AsPlainText -Force
                $install.GetNewClosure() | Should -Throw
            }
        }
    }

    Context 'Upgrade' {
        BeforeAll {
            Mock Get-ItemProperty -ModuleName QlikPackage
            Mock Get-FileInfo -ModuleName QlikPackage { @{OriginalFilename = 'Qlik_Sense_setup.exe'; ProductName = 'Qlik Sense November 2020'} }
        }

        Describe 'When installing a package' {
            It 'Should pass arguments to the setup process' {
                $password = ConvertTo-SecureString -String 'password' -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                Install-QlikPackage `
                    -Path 'Qlik_Sense_setup.exe' `
                    -AcceptEula `
                    -ServiceCredential $credential `
                    -DbPassword $credential

                $proc.StartInfo.Arguments | Should -Match '-silent'
                $proc.StartInfo.Arguments | Should -Match 'accepteula=1'
                $proc.StartInfo.Arguments | Should -Match 'userwithdomain=".\\qservice"'
                $proc.StartInfo.Arguments | Should -Match 'userpassword="password"'
                $proc.StartInfo.Arguments | Should -Match 'dbpassword="password"'
            }
        }
    }

    Context 'Patch' {
        Describe 'When installing a patch' {
            BeforeAll {
                Mock Get-FileInfo -ModuleName QlikPackage { @{OriginalFilename = 'Qlik_Sense_update.exe'; ProductName = 'Qlik Sense November 2020 Patch 1'} }
            }

            It 'Should pass arguments to the update process' {
                Install-QlikPackage `
                    -Path 'Qlik_Sense_setup.exe' 

                $proc.StartInfo.Arguments | Should -Be 'install startservices'
            }
        }
    }
}
