# 3공장 MES → 사이트 업로더 (Node 없이 Windows PowerShell 만으로 동작, 읽기 전용 조회)
# 같은 폴더의 .env 에서 설정을 읽음 (KEY=값 한 줄씩):
#   MES_SERVER  MES_PORT  MES_DB  MES_USER  MES_PW   ← IT/SWIT 에서 받은 읽기 전용 계정
#   MES_PLANT   (3공장 PLANT_CODE)
#   SB_URL=https://pauyimvawypicqrqczmp.supabase.co
#   SB_SERVICE_KEY=(Supabase service_role 키, 이 PC에만 보관)
# 실행: 한 번 돌고 끝남. 작업 스케줄러에 10분마다 등록(install-task.bat).
# 시험: powershell -ExecutionPolicy Bypass -File uploader.ps1 -Dry   (올리지 않고 결과만 표로 보여줌)
param([switch]$Dry)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = @{}
Get-Content (Join-Path $here '.env') -Encoding UTF8 | ForEach-Object { if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $cfg[$matches[1]] = $matches[2] } }
$log = Join-Path $here 'uploader.log'
function Log($m) { $l = "$(Get-Date -Format 'MM-dd HH:mm:ss') $m"; Write-Host $l; Add-Content $log $l -Encoding UTF8 }

try {
  $port = if ($cfg.MES_PORT) { $cfg.MES_PORT } else { '1433' }
  $cs = "Server=$($cfg.MES_SERVER),$port;Database=$($cfg.MES_DB);User ID=$($cfg.MES_USER);Password=$($cfg.MES_PW);ApplicationIntent=ReadOnly;Connect Timeout=15"
  $conn = New-Object System.Data.SqlClient.SqlConnection $cs
  $conn.Open()
  $cmd = $conn.CreateCommand()
  $cmd.CommandText = Get-Content (Join-Path $here 'mes.sql') -Raw -Encoding UTF8
  $cmd.CommandTimeout = 30
  [void]$cmd.Parameters.AddWithValue('@PLANT', [string]$cfg.MES_PLANT)
  $t = New-Object System.Data.DataTable
  $t.Load($cmd.ExecuteReader())
  $conn.Close()

  $now = (Get-Date).ToUniversalTime().ToString('o')
  $rows = foreach ($r in $t.Rows) {
    if ($r['no'] -is [DBNull]) { continue }
    $o = [ordered]@{}
    foreach ($c in $t.Columns) { $v = $r[$c.ColumnName]; $o[$c.ColumnName] = if ($v -is [DBNull]) { $null } elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-ddTHH:mm:ss+09:00') } else { $v } }
    $o.no = [int]$o.no; $o.updated_at = $now
    [pscustomobject]$o
  }
  if ($Dry -or -not $cfg.SB_SERVICE_KEY) { $rows | Format-Table no, status, part, mold, prod, ng, ct, std_ct -AutoSize; Log "시험 조회 $(@($rows).Count)대 (올리지 않음)"; exit 0 }

  $body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @($rows) -Depth 3 -Compress))
  $h = @{ apikey = $cfg.SB_SERVICE_KEY; Authorization = "Bearer $($cfg.SB_SERVICE_KEY)"; Prefer = 'resolution=merge-duplicates,return=minimal' }
  Invoke-RestMethod -Method Post -Uri "$($cfg.SB_URL)/rest/v1/machines_live?on_conflict=no" -Headers $h -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
  Log "올림 $(@($rows).Count)대"
} catch { Log "오류 $($_.Exception.Message)"; exit 1 }
