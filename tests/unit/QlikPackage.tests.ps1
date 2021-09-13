using module ../../DSCClassResources/QlikPackage.psm1

Describe "QlikPackage" {
    BeforeAll {
        InModuleScope QlikPackage {
            Mock Get-FileInfo -ParameterFilter { $Path -eq 'TestDrive:\Qlik_Sense_setup.exe'} {
                @{OriginalFilename = 'Qlik_Sense_setup.exe'; ProductName = 'Qlik Sense November 2020'}
            }
            Mock Get-FileInfo -ParameterFilter { $Path -eq 'TestDrive:\Qlik_Sense_update.exe'} {
                @{OriginalFilename = 'Qlik_Sense_update.exe'; ProductName = 'Qlik Sense November 2020 Patch 1'}
            }
        }
    }

    Context 'Test' {
        Describe 'When no packages are installed' {
            BeforeAll {
                InModuleScope QlikPackage {
                    Mock Get-ItemProperty -Verifiable
                }
            }

            It 'Should return false' {
                $pkg = [QlikPackage]@{ Setup = 'TestDrive:\Qlik_Sense_setup.exe'; Ensure = 'Present' }
                $pkg.Test() | Should -BeFalse
                Assert-VerifiableMock
            }
        }

        Describe 'When the setup package is already installed' {
            BeforeAll {
                Mock -ModuleName QlikPackage Get-ItemProperty -Verifiable {
                    @(@{ DisplayName = 'Qlik Sense November 2020' })
                }
            }

            It 'Should return true' {
                $pkg = [QlikPackage]@{ Setup = 'TestDrive:\Qlik_Sense_setup.exe'; Ensure = 'Present' }
                $pkg.Test() | Should -BeTrue
                Assert-VerifiableMock
            }
        }

        Describe 'When the update package is not installed' {
            BeforeAll {
                Mock -ModuleName QlikPackage Get-ItemProperty -Verifiable {
                    @(@{ DisplayName = 'Qlik Sense November 2020' })
                }
            }

            It 'Should return false' {
                $pkg = [QlikPackage]@{
                    Setup = 'TestDrive:\Qlik_Sense_setup.exe'
                    Patch = 'TestDrive:\Qlik_Sense_update.exe'
                    Ensure = 'Present'
                }
                $pkg.Test() | Should -BeFalse
                Assert-VerifiableMock
            }
        }

        Describe 'When the setup and patch are installed' {
            BeforeAll {
                Mock -ModuleName QlikPackage Get-ItemProperty -Verifiable { @(
                    @{ DisplayName = 'Qlik Sense November 2020' },
                    @{ DisplayName = 'Qlik Sense November 2020 Patch 1'}
                ) }
            }

            It 'Should return true' {
                $pkg = [QlikPackage]@{
                    Setup = 'TestDrive:\Qlik_Sense_setup.exe'
                    Patch = 'TestDrive:\Qlik_Sense_update.exe'
                    Ensure = 'Present'
                }
                $pkg.Test() | Should -BeTrue
                Assert-VerifiableMock
            }
        }
    }

    Context 'Set' {
        Describe 'When no packages are installed' {
            BeforeAll {
                InModuleScope QlikPackage {
                    Mock -Verifiable Get-ItemProperty
                    Mock -Verifiable Test-Path { $true }
                    Mock -Verifiable New-QlikSharedPersistenceConfiguration { [System.IO.FileInfo]'Test-Drive:\spc.cfg' }
                    Mock -Verifiable Install-QlikPackage
                    Mock Get-FileInfo -ParameterFilter { Write-Debug "MockPath: $Path"; $Path -eq 'TestDrive:\Qlik_Sense_setup.exe'} {
                        @{OriginalFilename = 'Qlik_Sense_setup.exe'; ProductName = 'Qlik Sense November 2020'}
                    }
                    Mock Get-FileInfo -ParameterFilter { $Path -eq 'TestDrive:\Qlik_Sense_update.exe'} {
                        @{OriginalFilename = 'Qlik_Sense_update.exe'; ProductName = 'Qlik Sense November 2020 Patch 1'}
                    }
                }
            }

            BeforeEach {
                $password = ConvertTo-SecureString -String 'password' -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                $pkg = [QlikPackage]@{
                    Setup               = 'TestDrive:\Qlik_Sense_setup.exe'
                    ServiceCredential   = $credential
                    DbSuperUserPassword = $credential
                    DbCredential        = $credential
                    RootDir             = '\\sense-cn\QlikShare'
                    SkipStartServices   = $true
                    AcceptEula          = $true
                    Ensure              = 'Present'
                }
            }

            It 'Should install the setup package' {
                $pkg.Set()

                Assert-VerifiableMock
            }

            It 'Should install the update package' {
                $pkg.Patch = 'TestDrive:\Qlik_Sense_update.exe'
                $pkg.Set()

                Assert-MockCalled -ModuleName QlikPackage Install-QlikPackage -Times 2
                Assert-VerifiableMock
            }

            It 'Should pass all specified parameters to New-QlikSharedPersistenceConfiguration' {
                $pkg.ConfigureDbListener = $false
                $pkg.Set()

                Assert-MockCalled -ModuleName QlikPackage New-QlikSharedPersistenceConfiguration -ParameterFilter {
                    $ConfigureDbListener -eq $false
                }
                Assert-VerifiableMock
            }
        }

        Describe 'When an existing package is installed' {
            BeforeAll {
                InModuleScope QlikPackage {
                    Mock -Verifiable Get-ItemProperty { @(@{ DisplayName = 'Qlik Sense September 2020' }) }
                    Mock -Verifiable Test-Path { $true }
                    Mock -Verifiable Install-QlikPackage
                }
            }

            BeforeEach {
                $password = ConvertTo-SecureString -String 'password' -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                $pkg = [QlikPackage]@{
                    Setup               = 'TestDrive:\Qlik_Sense_setup.exe'
                    ServiceCredential   = $credential
                    DbSuperUserPassword = $credential
                    SkipStartServices   = $true
                    AcceptEula          = $true
                    Ensure              = 'Present'
                }
            }

            It 'Should install with fewer parameters' {
                $pkg.Set()
                Assert-VerifiableMock
            }
        }

        Describe 'When installing a rim node' {
            BeforeAll {
                InModuleScope QlikPackage {
                    Mock -Verifiable Get-ItemProperty
                    Mock -Verifiable Test-Path { $true }
                    Mock -Verifiable New-QlikSharedPersistenceConfiguration { [System.IO.FileInfo]'Test-Drive:\spc.cfg' }
                    Mock -Verifiable Install-QlikPackage
                    Mock Get-FileInfo -ParameterFilter { Write-Debug "MockPath: $Path"; $Path -eq 'TestDrive:\Qlik_Sense_setup.exe'} {
                        @{OriginalFilename = 'Qlik_Sense_setup.exe'; ProductName = 'Qlik Sense November 2020'}
                    }
                    Mock Get-FileInfo -ParameterFilter { $Path -eq 'TestDrive:\Qlik_Sense_update.exe'} {
                        @{OriginalFilename = 'Qlik_Sense_update.exe'; ProductName = 'Qlik Sense November 2020 Patch 1'}
                    }
                }
            }

            BeforeEach {
                $password = ConvertTo-SecureString -String 'password' -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential('.\qservice', $password)
                $pkg = [QlikPackage]@{
                    Setup               = 'TestDrive:\Qlik_Sense_setup.exe'
                    ServiceCredential   = $credential
                    DbCredential        = $credential
                    SkipStartServices   = $true
                    AcceptEula          = $true
                    Ensure              = 'Present'
                }
            }

            It 'Should not require a DbSuperUserPassword' {
                $pkg.Set()
                Assert-VerifiableMock
            }
        }

    }

    Context 'Get' {
        Describe 'When no packages are installed' {
            BeforeAll {
                Mock -ModuleName QlikPackage Get-ItemProperty -Verifiable
            }

            It 'Should not return any packages' {
                $pkg = [QlikPackage]::new().Get()
                $pkg.ProductName | Should -BeNullOrEmpty
                $pkg.PatchName | Should -BeNullOrEmpty
                Assert-VerifiableMock
            }
        }

        Describe 'When packages are installed' {
            BeforeAll {
                Mock -ModuleName QlikPackage Get-ItemProperty -Verifiable { @(
                    @{ DisplayName = 'Qlik Sense November 2020' },
                    @{ DisplayName = 'Qlik Sense November 2020 Patch 1'}
                ) }
            }

            It 'Should return the package and patch names' {
                $pkg = [QlikPackage]::new().Get()
                $pkg.ProductName | Should -Be 'Qlik Sense November 2020'
                $pkg.PatchName | Should -Be 'Qlik Sense November 2020 Patch 1'
                Assert-VerifiableMock
            }
        }
    }
}
