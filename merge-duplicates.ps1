# Объединение вероятных дублей клиентов в локальной выгрузке (YCLIENTS не меняется).
# Вход: export/full (raw/ + дубли_клиентов.csv). Выход по умолчанию: private/exports/merged.
# Производный аналитический результат: не импортировать без ручной проверки соответствий.
param([string]$Dest = (Join-Path $PSScriptRoot 'private/exports/merged'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/resolve-export-directory.ps1')
$Dest = Resolve-ExportDirectory -RepositoryRoot $PSScriptRoot -Destination $Dest
$src = Join-Path $PSScriptRoot 'export\full'

function CF($obj, $code) { if ($obj -and $obj.custom_fields) { $obj.custom_fields.$code } }
function SaveCsv($name, $rows) { @($rows) | Export-Csv (Join-Path $Dest "$name.csv") -Delimiter ';' -Encoding utf8BOM -NoTypeInformation }
function Uniq($vals) { @($vals | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique) }

Write-Host "== Загрузка"
$records = @(Get-Content "$src\raw\records.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
$staff = @(Get-Content "$src\raw\staff.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
$byId = @{}
Get-ChildItem "$src\raw\clients" -Filter *.json | ForEach-Object {
  $o = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $byId["$($o.client.id)"] = $o.client
}
$recCount = @{}; $records | Where-Object client | ForEach-Object { $recCount["$($_.client.id)"]++ }

# --- Группы «вероятный дубль» → объединение пересекающихся (union-find)
$parent = @{}
function Find($x) { while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; $x }
$dups = Import-Csv "$src\дубли_клиентов.csv" -Delimiter ';' | Where-Object Вывод -eq 'вероятный дубль'
$dups | ForEach-Object { if (-not $parent.ContainsKey($_.id)) { $parent[$_.id] = $_.id } }
$dups | Group-Object Группа | ForEach-Object {
  $ids = @($_.Group.id); $r0 = Find $ids[0]
  foreach ($i in $ids[1..($ids.Count)]) { if ($i) { $ri = Find $i; if ($ri -ne $r0) { $parent[$ri] = $r0 } } }
}
$clusters = @(@($parent.Keys) | Group-Object { Find $_ } | ForEach-Object { , @($_.Group) })
Write-Host "  групп для объединения: $($clusters.Count), карточек: $(($clusters | ForEach-Object Count | Measure-Object -Sum).Sum)"

# --- Главная карточка: больше записей, при равенстве — самая старая (меньший id)
$masterOf = @{}; $mergeLog = [Collections.Generic.List[object]]::new(); $merged = @{}
foreach ($cl in $clusters) {
  $cards = @($cl | ForEach-Object { $byId[$_] } | Where-Object { $_ } |
    Sort-Object @{ e = { [int]$recCount["$($_.id)"] }; Descending = $true }, @{ e = { [long]$_.id } })
  $m = $cards[0]; $others = @($cards | Select-Object -Skip 1)
  foreach ($c in $cards) { $masterOf["$($c.id)"] = "$($m.id)" }
  $first = { param($f) @($cards | ForEach-Object { & $f $_ } | Where-Object { "$_".Trim() })[0] }
  $merged["$($m.id)"] = [pscustomobject]@{
    id = $m.id; Объединено_из = (@($cards.id) -join ', ')
    Фамилия = (& $first { $args[0].surname }); Имя = (& $first { $args[0].name }); Отчество = (& $first { $args[0].patronymic })
    Телефон = $m.phone; Доп_телефоны = ((Uniq ($others.phone | Where-Object { $_ -ne $m.phone })) -join ', ')
    Email = (& $first { $args[0].email })
    Дата_рождения = (& $first { if ($args[0].birth_date -and "$($args[0].birth_date)" -ne '0') { $args[0].birth_date } }); Пол = (& $first { if ($args[0].sex -ne 'Неизвестно') { $args[0].sex } })
    Кличка = ((Uniq ($cards | ForEach-Object { CF $_ 'klichka-pitomtsa' })) -join ' / ')
    Порода_пол = ((Uniq ($cards | ForEach-Object { CF $_ 'poroda-i-pol-pitomtsa' })) -join ' / ')
    Визитов = ($cards.visits | Measure-Object -Sum).Sum; Потрачено = ($cards.spent | Measure-Object -Sum).Sum
    Оплачено = ($cards.paid | Measure-Object -Sum).Sum; Баланс = ($cards.balance | Measure-Object -Sum).Sum
    Скидка = ($cards.discount | Measure-Object -Maximum).Maximum
    Категории = ((Uniq ($cards | ForEach-Object { $_.categories } | ForEach-Object title)) -join ', ')
    Комментарий = ((Uniq $cards.comment) -join ' | ')
    Записей = ($cards | ForEach-Object { [int]$recCount["$($_.id)"] } | Measure-Object -Sum).Sum
    Изменён = ($cards.last_change_date | Sort-Object -Descending | Select-Object -First 1)
  }
  foreach ($o in $others) {
    $mergeLog.Add([pscustomobject]@{ Главная_id = $m.id; Объединённая_id = $o.id; ФИО = "$($o.surname) $($o.name)".Trim()
      Телефон = $o.phone; Email = $o.email; Записей_было = [int]$recCount["$($o.id)"] })
  }
}

# --- Клиенты после объединения
function ClientRow($c) { [pscustomobject]@{
  id = $c.id; Объединено_из = ''; Фамилия = $c.surname; Имя = $c.name; Отчество = $c.patronymic
  Телефон = $c.phone; Доп_телефоны = ''; Email = $c.email; Дата_рождения = $c.birth_date; Пол = $c.sex
  Кличка = (CF $c 'klichka-pitomtsa'); Порода_пол = (CF $c 'poroda-i-pol-pitomtsa')
  Визитов = $c.visits; Потрачено = $c.spent; Оплачено = $c.paid; Баланс = $c.balance; Скидка = $c.discount
  Категории = (@($c.categories | ForEach-Object title) -join ', '); Комментарий = $c.comment
  Записей = [int]$recCount["$($c.id)"]; Изменён = $c.last_change_date
} }
$clientRows = @{}
foreach ($c in ($byId.Values | Sort-Object id)) {
  $k = "$($c.id)"
  if ($merged.ContainsKey($k)) { $clientRows[$k] = $merged[$k] }
  elseif (-not $masterOf.ContainsKey($k)) { $clientRows[$k] = ClientRow $c }
}

# --- Записи: client_id → главная карточка
$attendance = @{ '-1' = 'не пришёл'; '0' = 'ожидание'; '1' = 'пришёл'; '2' = 'подтвердил' }
function RecordRow($r) {
  $orig = if ($r.client) { "$($r.client.id)" }
  $cid = if ($orig -and $masterOf.ContainsKey($orig)) { $masterOf[$orig] } else { $orig }
  $cl = if ($cid) { $clientRows[$cid] }
  [pscustomobject]@{
    id = $r.id; Дата = $r.datetime; Длительность_мин = [int]($r.length / 60); Врач = $r.staff.name; staff_id = $r.staff_id
    client_id = $cid; client_id_исходный = $orig
    Клиент = if ($cl) { "$($cl.Фамилия) $($cl.Имя)".Trim() } elseif ($r.client) { "$($r.client.surname) $($r.client.name)".Trim() }
    Телефон = if ($cl) { $cl.Телефон } else { $r.client.phone }; Кличка = $cl.Кличка
    Услуги = (@($r.services | ForEach-Object title) -join ' + ')
    Стоимость = (@($r.services | ForEach-Object cost) | Measure-Object -Sum).Sum
    Оплачено_полностью = $r.paid_full; Явка = $attendance["$($r.attendance)"]; Онлайн = $r.online
    Удалена = $r.deleted; Комментарий = $r.comment; Источник = (CF $r 'kak-vi-o-nas-uznali')
    Создана = $r.create_date; visit_id = $r.visit_id
  }
}
Write-Host "== Сборка"
$allRec = @($records | Sort-Object datetime | ForEach-Object { RecordRow $_ })
# состоявшиеся, без дублей по id и по клиент+время+врач (после объединения клиентов)
$done = @($allRec | Where-Object { $_.Удалена -ne $true -and $_.Явка -eq 'пришёл' } |
  Group-Object id | ForEach-Object { $_.Group[0] } |
  Group-Object { if ($_.client_id) { "$($_.client_id)|$($_.Дата)|$($_.staff_id)" } else { "id$($_.id)" } } | ForEach-Object { $_.Group[0] })
$doneIds = @{}; $done | Where-Object client_id | ForEach-Object { $doneIds[$_.client_id] = 1 }
$clientsAll = @($clientRows.Values | Sort-Object { [long]$_.id })

SaveCsv 'клиенты' $clientsAll
SaveCsv 'клиенты_состоялись' ($clientsAll | Where-Object { $doneIds.ContainsKey("$($_.id)") })
SaveCsv 'записи' $allRec
SaveCsv 'записи_состоялись' $done
SaveCsv 'объединённые_дубли' $mergeLog
SaveCsv 'сотрудники' ($staff | ForEach-Object { [pscustomobject]@{
  id = $_.id; ФИО = $_.name; Специализация = $_.specialization; Должность = $_.position.title
  Телефон = $_.user.phone; Email = $_.user.email; Уволен = $_.fired; Дата_увольнения = $_.dismissal_date
  Скрыт_онлайн = $_.hidden; Услуг = @($_.services_links).Count; user_id = $_.user_id; Дата_приёма = $_.employee.date_admission
  Описание = ($_.information -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
} })

$slotDup = $allRec.Count - @($allRec | Group-Object id).Count
Write-Host "`nГотово → $Dest"
Write-Host "  клиентов: было $($byId.Count), стало $($clientsAll.Count) (объединено групп $($clusters.Count), убрано карточек $($mergeLog.Count))"
Write-Host "  записей: $($allRec.Count); состоялось: $($done.Count); клиентов с состоявшимися: $($doneIds.Count)"
