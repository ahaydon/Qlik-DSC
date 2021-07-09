function Get-DscProperty {
    param (
        [type]
        $Type
    )

    $ResourceProperties = $type.GetProperties() |
        Where-Object {
            $_.CustomAttributes.AttributeType.Name -eq 'DscPropertyAttribute' -and
            $_.CustomAttributes.NamedArguments.MemberName -ne 'Key'
        }

    $properties = @{}
    foreach ($property in $ResourceProperties) {
        $value = switch ($property.PropertyType) {
            'bool' { $true }
            'hashtable' { @{ Foo = 'Bar' }}
            'int' {
                $range = $property.CustomAttributes |
                    Where-Object { $_.AttributeType.Name -eq 'ValidateRangeAttribute' }
                if ($range -and $range.ConstructorArguments) {
                    Get-Random `
                        -Minimum $range.ConstructorArguments.value[0] `
                        -Maximum $range.ConstructorArguments.Value[1]
                }
                else {
                    1
                }
            }
            'string' { 'Test' }
            'string[]' { @('Foo', 'Bar') }
            default { Write-Warning "No value for $($property.PropertyType)"}
        }
        $properties.Add($property.Name, $value)
    }

    return $properties
}
