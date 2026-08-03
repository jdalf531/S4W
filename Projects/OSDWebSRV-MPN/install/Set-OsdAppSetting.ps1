<#
.SYNOPSIS
    Replaces a single string value in a JSON config file via targeted regex
    substitution, preserving any `//` comments a full parse/re-serialize
    round-trip would strip.
#>
function Set-OsdAppSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $content = Get-Content -LiteralPath $Path -Raw

    # JSON-escape the value: backslashes first, then double quotes, so an
    # escape backslash inserted by the second replace is never itself
    # re-escaped by a later pass.
    $jsonEscaped = $Value -replace '\\', '\\' -replace '"', '\"'

    # [regex]::Replace treats '$' specially in the replacement string;
    # escape any literal '$' in the value so it passes through unchanged.
    $replacementValue = $jsonEscaped.Replace('$', '$$')

    $pattern     = '("' + [regex]::Escape($Key) + '"\s*:\s*)"(?:[^"\\]|\\.)*"'
    $replacement = '${1}"' + $replacementValue + '"'

    # Use an instance so we get the (input, replacement, count) overload —
    # the static [regex]::Replace(...) has no such overload and PowerShell
    # silently coerces a trailing int into RegexOptions instead, which both
    # replaces every match and makes matching case-insensitive.
    $re = [regex]::new($pattern)

    if (-not $re.IsMatch($content)) {
        throw "Key '$Key' not found in '$Path'."
    }

    $updated = $re.Replace($content, $replacement, 1)

    Set-Content -LiteralPath $Path -Value $updated -NoNewline
}
