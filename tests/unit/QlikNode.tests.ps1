using module ../../DSCClassResources/QlikNode.psm1

Describe 'QlikNode' {
    BeforeEach {
        $Desired = [QlikNode]@{
            Hostname     = 'sense1'
            Ensure       = 'Present'
        }

        InModuleScope QlikNode {
            $Script:Node = [PSCustomObject]@{
                id               = [guid]::NewGuid()
                hostname         = 'sense1'
                name             = 'Central'
                engineEnabled    = $true
                proxyEnabled     = $true
                schedulerEnabled = $true
                printingEnabled  = $true
                failover         = $true
            }

            Mock Get-QlikNode -ParameterFilter { $filter -eq "hostname eq 'sense1'" } {
                return $Node
            }
            Mock Get-QlikNode {
                return $null
            }
        }
    }

    Context 'Test' {
        BeforeAll {
            InModuleScope QlikNode {
                Mock Get-QlikServiceStatus
            }
        }

        Describe 'When only mandatory properties are set' {
            It 'Should return true when the node exists' {
                $Desired.Test() | Should -BeTrue
            }

            It 'Should return false for a non-existent node' {
                $Desired.Hostname = 'sense2'
                $Desired.Test() | Should -BeFalse
            }
        }
    }

    Context 'Set' {
        BeforeAll {
            InModuleScope QlikNode {
                Mock Register-QlikNode
                Mock Update-QlikNode
                if (!(Get-Command -Name Get-Service -ErrorAction Ignore)) {
                    # Workaround for testing on non-Windows platforms
                    function Get-Service {
                    }
                }
                Mock Get-Service {
                    return [PSCustomObject]@{
                        Status = 'Running'
                    }
                }
                Mock Get-ServicePath {
                    'C:\Program Files\Qlik\Sense\Repository\Repository.exe'
                }
            }
        }

        Describe 'When node is absent and should be present' {
            It 'Should register the node' {
                $Desired.Hostname = 'sense2'
                $Desired.Set()

                Assert-MockCalled -CommandName Register-QlikNode -ModuleName QlikNode
            }
        }

        Describe 'When node is present but not correct' {
            BeforeAll {
                InModuleScope QlikNode {
                    Mock Get-QlikServiceStatus
                }
            }

            It 'Should update the node' {
                $Desired.Hostname = 'sense1'
                $Desired.Failover = $false
                $Desired.Set()

                Assert-MockCalled -CommandName Update-QlikNode -ModuleName QlikNode
            }
        }

        Describe 'When certificates are not installed' {
            BeforeAll {
                InModuleScope QlikNode {
                    Mock Get-QlikServiceStatus -ParameterFilter { $filter -match 'serviceState eq NoCommunication' }
                    Mock Get-QlikServiceStatus {
                        @{ serviceState = 'CertificatesNotInstalled' }
                    }
                    Mock Invoke-QlikGet { 'password' }
                    Mock Invoke-WebRequest
                }
            }

            It 'Should redistribute certificates' {
                $Desired.Set()

                Assert-MockCalled `
                    -CommandName Invoke-QlikGet `
                    -ModuleName QlikNode `
                    -ParameterFilter { $path -match '/qrs/servernoderegistration/start/' }
                Assert-MockCalled `
                    -CommandName Invoke-WebRequest `
                    -ModuleName QlikNode `
                    -ParameterFilter {
                        $Uri -eq 'http://localhost:4570/certificateSetup' -and $Method -eq 'POST'
                    }
            }
        }

        Describe 'When the service account is not an admin' {
            BeforeAll {
                InModuleScope QlikNode {
                    Mock Get-QlikServiceStatus -ParameterFilter { $filter -match 'serviceState eq NoCommunication' }
                    Mock Get-QlikServiceStatus {
                        @{ serviceState = 'CertificatesNotInstalled' }
                    }
                    Mock Invoke-QlikGet { 'password' }
                    Mock Invoke-WebRequest
                    Mock Start-SenseBootstrap
                    Mock Get-Service {
                        return [PSCustomObject]@{
                            Name = $Name
                            Status = 'Stopped'
                        }
                    }
                }
            }

            It 'Should bootstrap the repository service' {
                $Desired.Set()

                Assert-MockCalled `
                    -CommandName Start-SenseBootstrap `
                    -ModuleName QlikNode `
                    -ParameterFilter { $Name -eq 'Repository' }
            }
        }
    }
}
