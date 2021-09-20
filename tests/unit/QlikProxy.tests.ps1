$ProjectRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$modulePath = Join-Path $ProjectRoot -ChildPath 'DSCClassResources' | Join-Path -ChildPath 'QlikProxy.psm1'
Import-Module -PassThru $modulePath

InModuleScope QlikProxy {
    Describe "QlikProxy" {
        . (Join-Path $ProjectRoot -ChildPath 'tests' | Join-Path -ChildPath 'helpers' | Join-Path -ChildPath 'dsc_class.ps1')
        $ResourceProperties = Get-DscProperty -Type 'QlikProxy'

        Context 'Test' {
            Describe 'When no properties are set' {
                BeforeAll {
                    Mock Get-QlikProxy {
                        return @{
                            id = [guid]::NewGuid()
                            settings = [QlikProxy]@{Node = 'localhost'}
                        }
                    }
                }

                It 'Should return true' {
                    $proxy = [QlikProxy]@{Node = 'localhost'}
                    $proxy.Test() | Should -BeTrue
                    Assert-VerifiableMock
                }
            }

            Describe 'When setting resource properties' {
                BeforeAll {
                    Mock Get-QlikProxy -Verifiable {
                        return @{
                            id = [guid]::NewGuid()
                            settings = [QlikProxy]@{Node = 'localhost'}
                        }
                    }
                }

                foreach ($property in $ResourceProperties.GetEnumerator()) {
                    It "Should detect changes to the $($property.Key) property" {
                        $proxy = [QlikProxy]@{
                            Node = 'localhost'
                            "$($property.Key)" = $property.Value
                        }
                        $proxy.Test() | Should -BeFalse
                        Assert-VerifiableMock
                    }
                }
            }
        }

        Context 'Set' {
            BeforeAll {
                Mock Update-QlikProxy -Verifiable
                Mock Get-QlikProxy -Verifiable {
                    return @{
                        id = [guid]::NewGuid()
                        settings = [QlikProxy]@{
                            AllowHTTP = $true
                            KerberosAuthentication = $true
                        }
                    }
                }
            }

            Describe 'When setting resource properties' {
                BeforeAll {
                    $proxy = [QlikProxy]@{
                        Node = 'localhost'
                    }
                    foreach ($property in $ResourceProperties.GetEnumerator()) {
                        if ($property.Key -eq 'CustomProperties') { continue }
                        $proxy.($property.Key) = $property.Value
                    }
                    $proxy.Set()
                }

                foreach ($property in $ResourceProperties.GetEnumerator()) {
                    if ($property.Key -eq 'CustomProperties') { continue }
                    It "Should update the $($property.Key) property of the resource" {
                        Assert-MockCalled -CommandName Update-QlikProxy -ParameterFilter {
                            (Get-Variable $property.Key -ValueOnly -ErrorAction SilentlyContinue) -eq $property.Value
                        }
                        Assert-VerifiableMock
                    }
                }
            }

            Describe 'When setting custom properties' {
                BeforeAll {
                    Mock Get-QlikCustomProperty -ModuleName Common -Verifiable {
                        return @{ choiceValues = @('A') }
                    }
                    $proxy = [QlikProxy]@{ Node = 'localhost'; CustomProperties = @{ Group = 'A' } }
                    $proxy.Set()
                }

                It 'Should call Update-QlikProxy with the custom properties' {
                    Assert-MockCalled -CommandName Update-QlikProxy -ParameterFilter { $CustomProperties -contains 'Group=A' }
                    Assert-VerifiableMock
                }
            }
        }

        Context 'Get' {
            BeforeAll {
                Mock Get-QlikProxy -Verifiable {
                    return @{
                        id = [guid]::NewGuid()
                        settings = [QlikProxy]$ResourceProperties
                        customProperties = @{
                            value = 'Bar'
                            definition = @{ name = 'Foo' }
                        }
                    }
                }

                $dsc = [QlikProxy]@{Node = 'localhost'}
                $proxy = $dsc.Get()
            }

            Describe 'When setting resource properties' {
                foreach ($property in $ResourceProperties.GetEnumerator()) {
                    if ($property.Key -eq 'CustomProperties') { continue }
                    It "Should return the value of the $($property.Key) property" {
                        $proxy.($property.Key) | Should -Be $property.Value
                        Assert-VerifiableMock
                    }
                }

                It 'Should return the configured custom properties' {
                    $proxy.CustomProperties.Foo | Should -Be 'Bar'
                    Assert-VerifiableMock
                }
            }
        }
    }
}
