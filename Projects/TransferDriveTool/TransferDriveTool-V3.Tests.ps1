Describe 'Get-DriveDatedFolders' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DriveDatedFolders')
    }

    It 'returns dated subfolders sorted chronologically' {
        $root = Join-Path $TestDrive 'Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260806') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805', '20260806', '20260807')
    }

    It 'excludes non-dated folders like Archive' {
        $root = Join-Path $TestDrive 'Ben'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'Archive') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805')
    }

    It 'returns an empty array when the root exists but has no dated subfolders' {
        $root = Join-Path $TestDrive 'Corey'
        New-Item -ItemType Directory -Path (Join-Path $root 'Archive') -Force | Out-Null

        $result = @(Get-DriveDatedFolders -DriveUserRoot $root)

        $result.Count | Should -Be 0
    }

    It 'returns an empty array when the root does not exist' {
        $result = @(Get-DriveDatedFolders -DriveUserRoot (Join-Path $TestDrive 'DoesNotExist'))

        $result.Count | Should -Be 0
    }
}

Describe 'Get-CompletedFileHashes' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-CompletedFileHashes')
    }

    It 'returns a hash per relative path for completed files' {
        $folder = Join-Path $TestDrive 'completed'
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'a.txt') -Value 'alpha' -NoNewline
        Set-Content -Path (Join-Path $folder 'sub\b.txt') -Value 'beta' -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Sort-Object | Should -Be @('a.txt', 'sub\b.txt')
        $result['a.txt'] | Should -Be (Get-FileHash -LiteralPath (Join-Path $folder 'a.txt') -Algorithm SHA256).Hash
    }

    It 'excludes .partial and .partial.meta files' {
        $folder = Join-Path $TestDrive 'withpartial'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'done.txt') -Value 'finished' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial') -Value 'half' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial.meta') -Value "4`n0" -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Should -Be @('done.txt')
    }

    It 'returns an empty hashtable when the folder does not exist' {
        $result = Get-CompletedFileHashes -FolderPath (Join-Path $TestDrive 'missing')

        $result.Count | Should -Be 0
    }
}

Describe 'Get-DateFolderCandidates' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates')
    }

    It 'finds the unsuffixed and numbered folders for a date, sorted by suffix' {
        $root = Join-Path $TestDrive 'mpn\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-2') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260808') -Force | Out-Null

        $result = Get-DateFolderCandidates -DestUserRoot $root -Date '20260807'

        $result.Name | Should -Be @('20260807', '20260807-1', '20260807-2')
    }

    It 'returns an empty array when the destination root does not exist' {
        $result = @(Get-DateFolderCandidates -DestUserRoot (Join-Path $TestDrive 'nope') -Date '20260807')

        $result.Count | Should -Be 0
    }

    It 'returns an empty array when the root exists but has no matching date folder' {
        $root = Join-Path $TestDrive 'Ben2'
        New-Item -ItemType Directory -Path (Join-Path $root '20260808') -Force | Out-Null

        $result = Get-DateFolderCandidates -DestUserRoot $root -Date '20260807'

        $result.Count | Should -Be 0
    }
}

Describe 'Get-NextAvailableDateSuffix' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates', 'Get-NextAvailableDateSuffix')
    }

    It 'returns the plain date when no folder exists yet' {
        $root = Join-Path $TestDrive 'mpn2\Kevin'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807'
    }

    It 'increments to the next unused suffix' {
        $root = Join-Path $TestDrive 'mpn3\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807-2'
    }

    It 'throws once MaxSuffix is exhausted' {
        $root = Join-Path $TestDrive 'mpn4\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        { Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' -MaxSuffix 1 } | Should -Throw
    }
}

Describe 'Get-NewFilesForDate' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-CompletedFileHashes', 'Get-NewFilesForDate')
    }

    It 'returns all source files when no destination folders exist yet' {
        $source = Join-Path $TestDrive 'src1\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @())

        $result.RelativePath | Should -Be @('a.txt')
    }

    It 'excludes a file whose content already matches an existing destination folder' {
        $source = Join-Path $TestDrive 'src2\20260807'
        $dest   = Join-Path $TestDrive 'dest2\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha' -NoNewline
        Set-Content -Path (Join-Path $dest 'a.txt') -Value 'alpha' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @(Get-Item -LiteralPath $dest))

        $result.Count | Should -Be 0
    }

    It 'includes a file whose content differs from the same-named file at the destination' {
        $source = Join-Path $TestDrive 'src3\20260807'
        $dest   = Join-Path $TestDrive 'dest3\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha-v2' -NoNewline
        Set-Content -Path (Join-Path $dest 'a.txt') -Value 'alpha-v1' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @(Get-Item -LiteralPath $dest))

        $result.RelativePath | Should -Be @('a.txt')
    }
}

Describe 'Resolve-DriveToMpnCopyPlan' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @(
            'Get-DriveDatedFolders',
            'Get-CompletedFileHashes',
            'Get-DateFolderCandidates',
            'Get-NextAvailableDateSuffix',
            'Get-NewFilesForDate',
            'Resolve-DriveToMpnCopyPlan'
        )
    }

    It 'marks a brand-new dated folder for copy when nothing exists at the destination yet' {
        $driveRoot = Join-Path $TestDrive 'drive\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot)

        $plan.Count | Should -Be 1
        $plan[0].Date | Should -Be '20260807'
        $plan[0].Action | Should -Be 'Copy'
        $plan[0].TargetFolder | Should -Be (Join-Path $destRoot '20260807')
        $plan[0].Files.RelativePath | Should -Be @('report.txt')
    }

    It 'reports AlreadyDelivered when the destination already has an identical file' {
        $driveRoot = Join-Path $TestDrive 'drive2\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn2\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $destRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $destRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'AlreadyDelivered'
    }

    It 'allocates a -1 suffix folder for a changed file on a same-day re-run, leaving the original folder untouched' {
        $driveRoot = Join-Path $TestDrive 'drive3\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn3\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline
        Set-Content -Path (Join-Path $driveRoot '20260807\new_file.txt') -Value 'brand new' -NoNewline

        New-Item -ItemType Directory -Path (Join-Path $destRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $destRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'Copy'
        $plan[0].TargetFolder | Should -Be (Join-Path $destRoot '20260807-1')
        $plan[0].Files.RelativePath | Should -Be @('new_file.txt')

        (Get-Content -LiteralPath (Join-Path $destRoot '20260807\report.txt') -Raw) | Should -Be 'v1'
    }

    It 'returns an empty plan when there are no dated folders on the drive' {
        $driveRoot = Join-Path $TestDrive 'drive4\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn4\Kevin'
        New-Item -ItemType Directory -Path $driveRoot -Force | Out-Null

        $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot)

        $plan.Count | Should -Be 0
    }
}

Describe 'Invoke-DriveToMpnDeliveryPlan' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @(
            'Copy-FileResumable',
            'Add-CsvLogEntry',
            'Invoke-DriveToMpnDeliveryPlan'
        )
    }

    BeforeEach {
        $script:CsvLogPath = Join-Path $TestDrive "log_$([guid]::NewGuid().ToString('N')).csv"
        $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
        Set-Content -Path $script:CsvLogPath -Value $headers

        $script:LogSnapshot = [PSCustomObject]@{
            DtaName = 'Kevin'; Manager = 'Jane Doe'; SourceSystem = 'E:\DTA\Kevin'
            DestSystem = '\\mpn\Kevin'; Classification = 'Confidential'
            MediaUsed = 'USB_DRIVE'; Justification = 'Test'; ScanVerify = 'Yes'
        }
    }

    It 'copies delta files into the target folder and logs a CSV row with the resolved folder name' {
        $sourceFile = Join-Path $TestDrive 'source_report.txt'
        Set-Content -Path $sourceFile -Value 'hello world' -NoNewline
        $fileInfo = Get-Item -LiteralPath $sourceFile

        $targetFolder = Join-Path $TestDrive 'dest\20260807-1'
        $plan = @(
            [PSCustomObject]@{
                Date = '20260807'
                Action = 'Copy'
                TargetFolder = $targetFolder
                Files = @([PSCustomObject]@{ FileInfo = $fileInfo; RelativePath = 'report.txt' })
                Error = $null
            }
        )

        $statusMessages = [System.Collections.Generic.List[string]]::new()

        $result = Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 1 `
            -OnStatus { param($msg) $statusMessages.Add($msg) }

        $result.FilesCopied | Should -Be 1
        $result.FilesSkipped | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $targetFolder 'report.txt') -Raw) | Should -Be 'hello world'

        $csvRows = @(Import-Csv -LiteralPath $script:CsvLogPath)
        $csvRows.Count | Should -Be 1
        $csvRows[0].FileName | Should -Be '20260807-1\report.txt'
    }

    It 'logs a status message and copies nothing for an AlreadyDelivered entry' {
        $plan = @(
            [PSCustomObject]@{ Date = '20260805'; Action = 'AlreadyDelivered'; TargetFolder = $null; Files = @(); Error = $null }
        )
        $statusMessages = [System.Collections.Generic.List[string]]::new()

        $result = Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 0 `
            -OnStatus { param($msg) $statusMessages.Add($msg) }

        $result.FilesCopied | Should -Be 0
        $statusMessages | Should -Contain 'Already fully delivered for 20260805, nothing to copy.'
    }

    It 'logs an error status for an Error entry without throwing' {
        $plan = @(
            [PSCustomObject]@{ Date = '20260806'; Action = 'Error'; TargetFolder = $null; Files = @(); Error = 'boom' }
        )
        $statusMessages = [System.Collections.Generic.List[string]]::new()

        { Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 0 `
            -OnStatus { param($msg) $statusMessages.Add($msg) } } | Should -Not -Throw

        ($statusMessages | Where-Object { $_ -like '*boom*' }) | Should -Not -BeNullOrEmpty
    }
}
