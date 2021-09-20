function CompareProperties( $expected, $actual, $prop ) {
    Write-Verbose "Comparing $($prop.Count) properties"

    foreach ($_ in $prop) {
        if (! $expected.$_) {
            Write-Debug "Skipping $_ as desired state is not set"
            Continue
        }

        Write-Debug "$_`: expected=$($expected.$_), actual=$($actual.$_)"
        if ('Tags' -eq $_) {
            foreach ($tag in $expected.Tags) {
                if (-Not ($actual.tags.name -contains $tag)) {
                    Write-Verbose "Not tagged with $tag"
                    return $false
                }
            }
        }
        elseif ('CustomProperties' -eq $_) {
            foreach ($prop in $expected.CustomProperties.Keys) {
                $cp = $actual.customProperties | Where-Object { $_.definition.name -eq $prop }
                if (-Not (($cp) -And ($cp.value -eq $expected.CustomProperties.$prop))) {
                    Write-Verbose "Property $prop should have value $($expected.CustomProperties.$prop) but instead has value $($cp.value)"
                    return $false
                }
            }
        }
        elseif($expected.PSObject.Properties.Name -contains $_ -And ($actual.$_ -ne $expected.$_)) {
            Write-Verbose "CompareProperties: $_ property value - $($actual.$_) does not match desired state - $($expected.$_)"
            return $false
        }
    }

    return $true
}

function ConfigurePropertiesAndTags( $item ) {
    $return = @{}
    $props = @()
    foreach ($prop in $item.CustomProperties.Keys) {
        $cp = Get-QlikCustomProperty -filter "name eq '$prop'" -raw
        if (! $cp) {
            $cp = New-QlikCustomProperty `
                -name $prop `
                -choiceValues $item.CustomProperties.$prop `
                -objectTypes $item.SchemaPath
        }
        if (-Not ($cp.choiceValues -contains $item.CustomProperties.$prop)) {
            $cp.choiceValues += $item.CustomProperties.$prop
            Write-Verbose -Message "Updating property $prop with new value of $($item.CustomProperties.$prop)"
            Update-QlikCustomProperty -id $cp.id -choiceValues $cp.choiceValues
        }
        $props += "$($prop)=$($item.CustomProperties.$prop)"
    }
    $tags = @()
    foreach ($tag in $item.Tags) {
        $tagId = (Get-QlikTag -filter "name eq '$tag'").id
        if (-Not $tagId) {
            $tagId = (New-QlikTag -name $tag).id
            Write-Verbose "Created tag for $tag with id $tagId"
        }
        $tags += $tag
    }

    if($props) {$return.Add('customProperties', $props)}
    if($tags) {$return.Add('tags', $tags)}
    return $return
}
