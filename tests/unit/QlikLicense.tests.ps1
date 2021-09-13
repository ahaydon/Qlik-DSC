using module ../../DSCClassResources/QlikLicense.psm1

Describe "QlikLicense" {
    BeforeAll {
        $ValidationException = ([System.Management.Automation.SetValueInvocationException])
    }

    BeforeEach {
        $Resource = [QlikLicense]@{
            Serial       = '1234567890123456'
            Name         = 'Qlik'
            Organization = 'Qlik'
            Ensure       = 'Present'
        }
    }

    Context 'Init' {
        Describe 'When defining a license resource' {
            It 'Should require a 16 character serial number' {
                { $Resource.Serial = '1234567890' } | Should -Throw -ExceptionType $ValidationException
            }

            It 'Should require a name' {
                { $Resource.Name = '' } | Should -Throw -ExceptionType $ValidationException
            }

            It 'Should require an organization' {
                { $Resource.Organization = '' } | Should -Throw -ExceptionType $ValidationException
            }
        }
    }

    Context 'Test' {
        BeforeEach {
            InModuleScope QlikLicense {
                $Script:License = [PSCustomObject]@{
                    id           = [guid]::NewGuid()
                    serial       = '1234567890123456'
                    name         = 'Qlik'
                    organization = 'Qlik'
                    lef          = ''
                    key          = ''
                    isExpired    = $false
                    isInvalid    = $false
                }
                Mock Get-QlikLicense {
                    return $License
                }
            }
        }

        Describe 'When checking mandatory parameters' {
            BeforeEach {
                $Resource.Control = '12345'
            }

            It 'Should return false if serial number is different' {
                $Resource.Serial = 'aaaaaaaaaaaaaaaa'

                $Resource.Test() | Should -BeFalse
            }

            It 'Should return false if user name is different' {
                $Resource.Name = 'Elliot'

                $Resource.Test() | Should -BeFalse
            }

            It 'Should return false if organization is different' {
                $Resource.Organization = 'E Corp'

                $Resource.Test() | Should -BeFalse
            }
        }

        Describe 'When no license is set' {
            It 'Should handle a response of "null"' {
                InModuleScope QlikLicense {
                    $Script:License = 'null'
                }

                $Resource.Control = '12345'
                $Resource.Test() | Should -BeFalse
            }
        }

        Describe 'When RefreshLef is set to Never' {
            BeforeEach {
                InModuleScope QlikLicense {
                    $Script:License.lef = 'asdfghjkl'
                    $Script:License.isExpired = $true
                    $Script:License.isInvalid = $true
                }

                $Resource.Control = '12345'
                $Resource.RefreshLef = 'Never'

                Mock -ModuleName QlikLicense Invoke-QlikGet
            }

            It 'Should not check for an updated Lef' {
                $Resource.Test() | Should -BeTrue

                Assert-MockCalled -ModuleName QlikLicense -CommandName Invoke-QlikGet -Times 0
            }
        }

        Describe 'When RefreshLef is set to Always' {
            BeforeEach {
                InModuleScope QlikLicense {
                    $Script:License.Lef = 'asdfghjkl'
                    $Script:LatestLef = $License.Lef
                    Mock Invoke-QlikGet -Verifiable {
                        return $LatestLef
                    }
                }

                $Resource.RefreshLef = 'Always'
                $Resource.Control = '12345'
            }

            It 'Should return true if the LEF matches' {
                $Resource.Test() | Should -BeTrue

                Assert-MockCalled -ModuleName QlikLicense -CommandName Invoke-QlikGet -ParameterFilter {
                    Write-Debug "Path: $path"
                    $query = [System.Web.HttpUtility]::ParseQueryString($path.SubString($path.IndexOf('?')))

                    if ($query.Get('serial') -ne $Resource.Serial) {
                        Write-Warning "query: $($query.Get('serial')), resource: $($Resource.Serial)"
                        return $false
                    }

                    if ($query.Get('control') -ne $Resource.Control) {
                        Write-Warning "query: $($query.Get('control')), resource: $($Resource.Control)"
                        return $false
                    }

                    if ($query.Get('user') -ne $Resource.Name) {
                        Write-Warning "query: $($query.Get('user')), resource: $($Resource.Name)"
                        return $false
                    }

                    if ($query.Get('org') -ne $Resource.Organization) {
                        Write-Warning "query: $($query.Get('org')), resource: $($Resource.Organization)"
                        return $false
                    }

                    return $true
                }
            }

            It 'Should return false if there is a newer LEF' {
                InModuleScope QlikLicense {
                    $Script:LatestLef = 'aaaaaaaaaaaaaaaa'
                }

                $Resource.Test() | Should -BeFalse

                Assert-VerifiableMock
            }
        }

        Describe 'When RefreshLef is set to ExpiredOrInvalid' {
            BeforeEach {
                InModuleScope QlikLicense {
                    $Script:License.Lef = 'asdfghjkl'

                    Mock Invoke-QlikGet -Verifiable {
                        return $License.Lef
                    }
                }

                $Resource.RefreshLef = 'ExpiredOrInvalid'
                $Resource.Control = '12345'
            }

            It 'Should not check for an updated LEF if license is not expired or invalid' {
                $Resource.Test() | Should -BeTrue

                Assert-MockCalled -ModuleName QlikLicense -CommandName Invoke-QlikGet -Times 0
            }

            It 'Should check for an updated LEF if license is expired' {
                InModuleScope QlikLicense {
                    $License.isExpired = $true
                }

                $Resource.Test() | Should -BeTrue

                Assert-MockCalled -ModuleName QlikLicense -CommandName Invoke-QlikGet -Times 1
            }

            It 'Should check for an updated LEF if license is invalid' {
                InModuleScope QlikLicense {
                    $License.isInvalid = $true
                }

                $Resource.Test() | Should -BeTrue

                Assert-MockCalled -ModuleName QlikLicense -CommandName Invoke-QlikGet -Times 1
            }
        }

        Describe 'When using a LEF' {
            BeforeEach {
                InModuleScope QlikLicense {
                    $Script:License.lef = 'aaaaaaaaaa'
                }
                $Resource.Lef = 'bbbbbbbbbb'
            }

            It 'should return false if configured and desired states are different' {
                $Resource.Control = '12345'
                $Resource.Test() | Should -BeFalse
            }

            It 'Should require a control number' {
                $Resource.Lef = 'aaaaaaaaaa'
                { $Resource.Test() } | Should -Throw -ExceptionType ([System.Management.Automation.ValidationMetadataException])
            }

            It 'Should require the control number to be 5 characters' {
                { $Resource.Control = '123456' } | Should -Throw -ExceptionType $ValidationException
            }
        }

        Describe 'When using a signed license key' {
            BeforeEach {
                InModuleScope QlikLicense {
                    $Script:License.Key = 'aaaaaaaaaaaaaaaa'
                }
                $Resource.Key = 'bbbbbbbbbbbbbbbb'
            }

            It 'Should return false if configured and desired state are different' {
                $Resource.Test() | Should -BeFalse
            }
        }
    }

    Context 'Set' {
        BeforeAll {
            Mock -ModuleName QlikLicense Set-QlikLicense {
                return $null
            }
        }

        Describe 'When using a serial and control number' {
            It 'Should call Set-QlikLicense with serial, control, name, and org parameters' {
                $Resource.Control = '12345'
                $Resource.Set()

                Assert-MockCalled -ModuleName QlikLicense -CommandName Set-QlikLicense -ParameterFilter {
                    if ($Serial -ne $Resource.Serial) {
                        return $false
                    }

                    if ($Control -ne $Resource.Control) {
                        return $false
                    }

                    if ($Name -ne $Resource.Name) {
                        return $false
                    }

                    if ($Organization -ne $Resource.Organization) {
                        return $false
                    }

                    return $true
                }
            }
        }

        Describe 'When using a signed license key' {
            It 'Should call Set-QlikLicense with serial, key, name, and org parameters' {
                $Resource.Key = '1234567890123456'
                $Resource.Set()

                Assert-MockCalled -ModuleName QlikLicense -CommandName Set-QlikLicense -ParameterFilter {
                    if ($Key -ne $Resource.Key) {
                        return $false
                    }

                    if ($Name -ne $Resource.Name) {
                        return $false
                    }

                    if ($Organization -ne $Resource.Organization) {
                        return $false
                    }

                    return $true
                }
            }
        }
    }

    Context 'Get' {
        BeforeAll {
            Mock -ModuleName QlikLicense Get-QlikLicense -Verifiable {
                return $License
            }
        }

        Describe 'When the Get method is called' {
            It 'Should call Get-QlikLicense' {
                $Configured = $Resource.Get()

                $Configured.Serial | Should -BeExactly $Resource.Serial

                Assert-VerifiableMock
            }
        }
    }
}
