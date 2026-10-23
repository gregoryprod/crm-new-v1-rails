# Реальный запуск merge-duplicates на синтетической выгрузке, без доступа к API.
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('vpc-export-test-' + [guid]::NewGuid())
$repoName = 'repo-й'
$temp = Join-Path $sandbox $repoName
New-Item -ItemType Directory -Path $temp | Out-Null

function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Assert-Rejected($script, $message) {
  $rejected = $false
  try { & $script } catch { $rejected = $true }
  Assert $rejected $message
}

try {
  Copy-Item (Join-Path $repository 'merge-duplicates.ps1') $temp
  New-Item -ItemType Directory -Path (Join-Path $temp 'scripts') | Out-Null
  Copy-Item (Join-Path $repository 'scripts/resolve-export-directory.ps1') (Join-Path $temp 'scripts')
  $raw = Join-Path $temp 'export/full/raw'
  New-Item -ItemType Directory -Path (Join-Path $raw 'clients') | Out-Null

  $client = @{ id = 1; name = 'Synthetic'; surname = 'Fixture'; phone = ''; email = ''
    visits = 1; spent = 0; paid = 0; balance = 0; discount = 0; categories = @()
    custom_fields = @{ 'klichka-pitomtsa' = 'TestPet' }; last_change_date = '2026-01-01' }
  @{ client = $client; comments = @(); files = @() } | ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $raw 'clients/1.json') -Encoding utf8
  @(@{ id = 1; name = 'Synthetic specialist'; information = ''; services_links = @() }) |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $raw 'staff.json') -Encoding utf8
  @(@{ id = 1; client = $client; staff = @{ name = 'Synthetic specialist' }; staff_id = 1
    datetime = '2026-01-01T10:00:00'; length = 3600; attendance = 1; deleted = $false
    services = @(@{ title = 'Synthetic service'; cost = 0 }) }) | ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $raw 'records.json') -Encoding utf8
  '"Группа";"Вывод";"id"' | Set-Content (Join-Path $temp 'export/full/дубли_клиентов.csv') -Encoding utf8

  # Неприватный Dest отклоняется до чтения/создания результата.
  Assert-Rejected { & (Join-Path $temp 'merge-duplicates.ps1') -Dest $temp } 'Root destination was accepted'
  Assert-Rejected { & (Join-Path $temp 'merge-duplicates.ps1') -Dest (Join-Path $temp 'src') } 'Source destination was accepted'
  Assert-Rejected { & (Join-Path $temp 'merge-duplicates.ps1') -Dest (Join-Path $temp 'private/../src') } 'Traversal destination was accepted'

  & (Join-Path $temp 'merge-duplicates.ps1')
  $result = Join-Path $temp 'private/exports/merged'
  foreach ($file in @('клиенты.csv', 'клиенты_состоялись.csv', 'записи.csv', 'записи_состоялись.csv', 'объединённые_дубли.csv', 'сотрудники.csv')) {
    Assert (Test-Path (Join-Path $result $file)) "Missing output: $file"
  }
  Assert (@(Get-ChildItem $temp -Filter '*.csv').Count -eq 0) 'CSV leaked into repository root'
  $rows = @(Import-Csv (Join-Path $result 'клиенты.csv') -Delimiter ';')
  Assert ($rows.Count -eq 1 -and $rows[0].id -eq '1') 'Synthetic client was lost'
  Assert (Test-Path (Join-Path $raw 'clients/1.json')) 'Raw input was removed'

  . (Join-Path $temp 'scripts/resolve-export-directory.ps1')
  $external = Join-Path $sandbox 'outside'
  $outside = Resolve-ExportDirectory -RepositoryRoot $temp -Destination $external
  Assert (Test-Path $outside) 'Explicit external destination failed'
  Remove-Item $outside -Force

  # Внешний системный/пользовательский алиас допустим, но не обход запрета root/src.
  $alias = Join-Path $sandbox 'alias'
  New-Item -ItemType SymbolicLink -Path $alias -Target $sandbox | Out-Null
  $outsideViaAlias = Resolve-ExportDirectory -RepositoryRoot $temp -Destination (Join-Path $alias 'outside-alias')
  Assert (Test-Path $outsideViaAlias) 'External symlink ancestor was rejected'
  Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot $temp -Destination (Join-Path $alias $repoName) } 'Repository root alias was accepted'
  Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot (Join-Path $alias $repoName) -Destination (Join-Path $temp 'src') } 'Source via repository alias was accepted'
  if ($IsMacOS -or $IsWindows) {
    $caseAlias = Join-Path (Join-Path $sandbox $repoName.ToUpperInvariant()) 'src'
    Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot $temp -Destination $caseAlias } 'Case alias destination was accepted'
  }

  if ($IsMacOS) {
    $unicodeAlias = Join-Path $temp.Normalize([Text.NormalizationForm]::FormD) 'src'
    Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot $temp -Destination $unicodeAlias } 'Unicode alias destination was accepted'
  }
  Push-Location $temp
  try {
    & (Join-Path $temp 'merge-duplicates.ps1') -Dest 'private/relative'
    Assert (Test-Path (Join-Path $temp 'private/relative/клиенты.csv')) 'Relative destination ignored PowerShell location'
    Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot $temp -Destination 'src' } 'Relative source destination was accepted'
    $tilde = Get-CanonicalExportPath -Path '~/vpc-synthetic-path-probe'
    $homeProbe = Get-CanonicalExportPath -Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'vpc-synthetic-path-probe')
    Assert ($tilde -eq $homeProbe) 'Home shorthand did not expand'
  } finally { Pop-Location }

  $link = Join-Path $temp 'private/link'
  New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $temp 'scripts') | Out-Null
  Assert-Rejected { Resolve-ExportDirectory -RepositoryRoot $temp -Destination (Join-Path $link 'leak') } 'Symlink destination was accepted'

  Write-Host 'Export safety checks passed (synthetic data only).'
} finally {
  Remove-Item $sandbox -Recurse -Force
}
