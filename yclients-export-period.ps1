# Выгрузка из YCLIENTS за период: записи, клиенты из этих записей, все сотрудники.
# Результат: export/<from>_<to>/ — сырые JSON (raw/) + CSV для Excel (разделитель ;, UTF-8 BOM).
# -CsvOnly: не обращаться к API, пересобрать CSV из уже скачанных raw/*.json
param(
  [string]$From = '2026-09-01',
  [string]$To   = '2026-09-30',
  [switch]$CsvOnly
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$out = Join-Path $PSScriptRoot "export\${From}_${To}"
New-Item -ItemType Directory -Force -Path "$out\raw" | Out-Null

function Save($name, $obj) { $obj | ConvertTo-Json -Depth 30 | Set-Content "$out\raw\$name.json" -Encoding utf8 }
function Load($name) { Get-Content "$out\raw\$name.json" -Raw -Encoding UTF8 | ConvertFrom-Json }
function SaveCsv($name, $rows) { $rows | Export-Csv "$out\$name.csv" -Delimiter ';' -Encoding utf8BOM -NoTypeInformation }
# custom_fields приходят объектом { "<code>": значение }
function CF($obj, $code) { if ($obj -and $obj.custom_fields) { $obj.custom_fields.$code } }

if (-not $CsvOnly) {
  $cfg = @{}
  Get-Content (Join-Path $PSScriptRoot '.env') -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^\s*([^=#]+)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
  }
  $company = $cfg['YCLIENTS_COMPANY_ID']
  $headers = @{
    'Accept'        = 'application/vnd.yclients.v2+json'
    'Authorization' = "Bearer $($cfg['YCLIENTS_PARTNER_TOKEN']), User $($cfg['YCLIENTS_USER_TOKEN'])"
  }

  # ≤ 4 запросов/сек (лимит YCLIENTS — 5), повтор при 429/5xx
  function Call($method, $path, $body = $null) {
    $p = @{ Method = $method; Uri = "https://api.yclients.ru$path"; Headers = $headers; ContentType = 'application/json; charset=utf-8' }
    if ($PSVersionTable.PSVersion.Major -ge 6) { $p.SkipHeaderValidation = $true }
    if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10)) }
    for ($try = 1; $try -le 5; $try++) {
      Start-Sleep -Milliseconds 260
      try { return Invoke-RestMethod @p }
      catch {
        $code = [int]$_.Exception.Response.StatusCode
        if ($code -eq 429 -or $code -ge 500) { Start-Sleep -Seconds (5 * $try); continue }
        Write-Host "  ! $method $path -> HTTP ${code}: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        return $null
      }
    }
    Write-Host "  ! $method $path -> не удалось после 5 попыток" -ForegroundColor Yellow
    $null
  }

  Write-Host "== Справочники"
  Save 'company' (Call GET "/api/v1/company/$company/").data
  Save 'custom_fields_client' (Call GET "/api/v1/custom_fields/client/$company").data
  Save 'custom_fields_record' (Call GET "/api/v1/custom_fields/record/$company").data
  Save 'services' (Call GET "/api/v1/company/$company/services/").data
  Save 'service_categories' (Call GET "/api/v1/company/$company/service_categories/").data
  Save 'positions' (Call GET "/api/v1/company/$company/staff/positions/").data
  Save 'users' (Call GET "/api/v1/company/$company/users").data

  Write-Host "== Сотрудники"
  Save 'staff' @((Call GET "/api/v1/company/$company/staff/").data)
  Save 'staff_legacy' (Call GET "/api/v1/staff/$company/").data
  Save 'staff_schedule' (Call GET "/api/v1/company/$company/staff/schedule?start_date=$From&end_date=$To").data

  Write-Host "== Записи $From — $To"
  $records = @(); $page = 1
  do {
    $r = Call GET "/api/v1/records/$company`?page=$page&count=200&start_date=$From&end_date=$To&with_deleted=1&include_finance_transactions=1&include_consumables=1"
    if (-not $r) { break }
    $records += @($r.data); $total = $r.meta.total_count
    Write-Host "  страница $page`: $($records.Count) / $total"
    $page++
  } while (@($r.data).Count -gt 0 -and $records.Count -lt $total)
  Save 'records' $records

  $clientIds = @($records | Where-Object { $_.client } | ForEach-Object { $_.client.id } | Sort-Object -Unique)
  Write-Host "== Клиенты: $($clientIds.Count)"
  $clients = @(); $comments = @{}; $files = @{}; $i = 0
  foreach ($id in $clientIds) {
    $i++; if ($i % 25 -eq 0) { Write-Host "  $i / $($clientIds.Count)" }
    $c = (Call GET "/api/v1/client/$company/$id").data
    if ($c) { $clients += $c }
    $comments["$id"] = @((Call GET "/api/v1/company/$company/clients/$id/comments").data)
    $files["$id"] = @((Call GET "/api/v1/company/$company/clients/files/$id").data)
  }
  Save 'clients' $clients
  Save 'client_comments' $comments
  Save 'client_files' $files
}

# --- CSV (всегда из raw/)
$staff = @(Load 'staff'); $records = @(Load 'records'); $clients = @(Load 'clients')
$comments = Load 'client_comments'; $files = Load 'client_files'

SaveCsv 'staff' ($staff | ForEach-Object { [pscustomobject]@{
  id = $_.id; ФИО = $_.name; Специализация = $_.specialization; Должность = $_.position.title
  Телефон = $_.user.phone; Email = $_.user.email; Уволен = $_.fired; Дата_увольнения = $_.dismissal_date
  Скрыт_онлайн = $_.hidden; Услуг = @($_.services_links).Count; user_id = $_.user_id
  ФИО_полное = ("$($_.employee.surname) $($_.employee.firstname) $($_.employee.patronymic)").Trim(); Дата_приёма = $_.employee.date_admission
  Описание = ($_.information -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
} })

function ClientRow($c) { [pscustomobject]@{
  id = $c.id; Фамилия = $c.surname; Имя = $c.name; Отчество = $c.patronymic; Телефон = $c.phone; Email = $c.email
  Дата_рождения = $c.birth_date; Пол = $c.sex; Кличка = (CF $c 'klichka-pitomtsa'); Порода_пол = (CF $c 'poroda-i-pol-pitomtsa')
  Визитов = $c.visits; Потрачено = $c.spent; Оплачено = $c.paid; Баланс = $c.balance; Скидка = $c.discount
  Категории = (@($c.categories | ForEach-Object title) -join ', '); Комментарий = $c.comment
  Комментариев = @($comments."$($c.id)").Count; Файлов = @($files."$($c.id)").Count; Изменён = $c.last_change_date
} }

$attendance = @{ '-1' = 'не пришёл'; '0' = 'ожидание'; '1' = 'пришёл'; '2' = 'подтвердил' }
$byId = @{}; $clients | ForEach-Object { $byId["$($_.id)"] = $_ }
function RecordRow($r) {
  $cl = if ($r.client) { $byId["$($r.client.id)"] }
  [pscustomobject]@{
    id = $r.id; Дата = $r.datetime; Длительность_мин = [int]($r.length / 60); Врач = $r.staff.name; staff_id = $r.staff_id
    Клиент = if ($r.client) { "$($r.client.surname) $($r.client.name)".Trim() }; client_id = $r.client.id; Телефон = $r.client.phone
    Кличка = (CF $cl 'klichka-pitomtsa'); Порода_пол = (CF $cl 'poroda-i-pol-pitomtsa')
    Услуги = (@($r.services | ForEach-Object title) -join ' + ')
    Стоимость = (@($r.services | ForEach-Object cost) | Measure-Object -Sum).Sum
    Оплачено_полностью = $r.paid_full; Явка = $attendance["$($r.attendance)"]; Онлайн = $r.online
    Удалена = $r.deleted; Комментарий = $r.comment; Источник = (CF $r 'kak-vi-o-nas-uznali')
    Создана = $r.create_date; visit_id = $r.visit_id
  }
}

SaveCsv 'clients' ($clients | ForEach-Object { ClientRow $_ })
SaveCsv 'records' ($records | ForEach-Object { RecordRow $_ })

# --- Только состоявшиеся: не удалены, клиент пришёл; без дублей (по id и по клиент+время+врач)
$done = @($records | Where-Object { -not $_.deleted -and $_.attendance -eq 1 } |
  Group-Object id | ForEach-Object { $_.Group[0] } |
  Group-Object { "$($_.client.id)|$($_.datetime)|$($_.staff_id)" } | ForEach-Object { $_.Group[0] } |
  Sort-Object datetime)
$doneClients = @($done | Where-Object client | ForEach-Object { $byId["$($_.client.id)"] } | Where-Object { $_ } |
  Group-Object id | ForEach-Object { $_.Group[0] })
SaveCsv 'records_состоялись' ($done | ForEach-Object { RecordRow $_ })
SaveCsv 'clients_состоялись' ($doneClients | ForEach-Object { ClientRow $_ })

Write-Host "`nГотово: $out"
Write-Host "  записей: $($records.Count), клиентов: $($clients.Count), сотрудников: $($staff.Count)"
Write-Host "  состоялось: $($done.Count) записей, $($doneClients.Count) клиентов"