# Не обращается к API и не читает клиентские данные.
function Test-ExportPathInside {
  param([string]$Path, [string]$Root)
  if ($IsMacOS -or $IsWindows) {
    $Path = $Path.Normalize([Text.NormalizationForm]::FormC)
    $Root = $Root.Normalize([Text.NormalizationForm]::FormC)
  }
  # Консервативное сравнение также защищает стандартные нечувствительные APFS.
  $comparison = if ($IsWindows -or $IsMacOS) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $Path.Equals($Root, $comparison) -or $Path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Get-CanonicalExportPath {
  param([string]$Path, [string]$RejectLinksUnderRoot = '')
  $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  $full = [IO.Path]::GetFullPath($providerPath)
  $current = [IO.Path]::GetPathRoot($full)
  $parts = $full.Substring($current.Length).Split([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries)
  foreach ($part in $parts) {
    $next = Join-Path $current $part
    $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
    if ($item) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($RejectLinksUnderRoot -and (Test-ExportPathInside -Path $current -Root $RejectLinksUnderRoot)) {
          throw 'Каталог выгрузки не должен проходить через символическую ссылку внутри репозитория.'
        }
        $resolved = $item.ResolveLinkTarget($true)
        if (-not $resolved -or -not $resolved.Exists) { throw 'Ссылка каталога выгрузки не имеет существующей цели.' }
        $next = Get-CanonicalExportPath -Path $resolved.FullName -RejectLinksUnderRoot $RejectLinksUnderRoot
      }
      if (-not $item.PSIsContainer) { throw 'Путь выгрузки должен указывать на каталог.' }
    }
    $current = $next
  }
  return $current
}

function Resolve-ExportDirectory {
  param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$Destination
  )

  $root = Get-CanonicalExportPath -Path $RepositoryRoot
  $target = Get-CanonicalExportPath -Path $Destination -RejectLinksUnderRoot $root
  if (Test-ExportPathInside -Path $target -Root $root) {
    $allowed = $false
    foreach ($name in @('private', 'export', 'База')) {
      if (Test-ExportPathInside -Path $target -Root (Join-Path $root $name)) {
        $allowed = $true
        break
      }
    }
    if (-not $allowed) {
      throw 'Выгрузка внутри репозитория разрешена только в private/, export/ или База/. Используй private/exports/merged.'
    }
  }

  New-Item -ItemType Directory -Force -Path $target | Out-Null
  return $target
}
