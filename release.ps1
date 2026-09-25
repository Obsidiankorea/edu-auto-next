<#
  코드로 넘기기 - 배포 스크립트

  쓰기
    .\release.ps1            빌드만 합니다. dist 폴더에 zip, SHA256SUMS.txt, notes.md 가 생깁니다.
    .\release.ps1 -Publish   빌드한 뒤 태그를 올리고 GitHub 릴리스를 만듭니다. (gh 필요)

  버전은 코드로넘기기.ahk 의 appVersion, 릴리스 설명은 CHANGELOG.md 의 '## v버전' 칸을 씁니다.
  zip 에 넣는 것: 코드로넘기기.exe, 사이트\*.ini, 사이트\원본.txt, 설명서들
    원본.txt 는 넣은 프로필들의 SHA256 목록입니다. exe 가 스스로 업데이트할 때
    '사용자가 손대지 않은 프로필' 을 알아보는 데 씁니다. (고친 프로필은 덮어쓰지 않는다)
#>
param([switch]$Publish)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function Fail($msg) {
    Write-Host "!! $msg" -ForegroundColor Red
    exit 1
}

$utf8 = New-Object Text.UTF8Encoding $false

# ---------- 1) 버전 ----------
$src = [IO.File]::ReadAllText("$root\코드로넘기기.ahk", [Text.Encoding]::UTF8)

if ($src -notmatch 'global appVersion\s*:=\s*"(\d+(?:\.\d+)*)"') { Fail 'appVersion 을 찾지 못했습니다' }

$ver = $Matches[1]
$tag = "v$ver"
Write-Host "버전 $tag"

# ---------- 2) 바뀐 내역 ----------
$log = [IO.File]::ReadAllText("$root\CHANGELOG.md", [Text.Encoding]::UTF8)
$m = [regex]::Match($log, "(?ms)^## $([regex]::Escape($tag))\b.*?(?=^## v|\z)")

if (-not $m.Success) { Fail "CHANGELOG.md 에 '## $tag' 칸이 없습니다" }

# 첫 줄('## v1.6.0 — 날짜')은 릴리스 제목과 겹치므로 뺀다
$notes = ($m.Value -replace '^[^\r\n]*\r?\n', '').Trim()

# ---------- 3) 검사와 빌드 ----------
$ahk2exe = "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
$base    = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"

foreach ($f in $ahk2exe, $base) {
    if (-not (Test-Path $f)) { Fail "없음: $f" }
}

$dist  = Join-Path $root 'dist'
$stage = Join-Path $dist 'stage'

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }

New-Item -ItemType Directory -Force (Join-Path $stage '사이트') | Out-Null

# 문법 오류가 있으면 빌드하지 않는다
$p = Start-Process $base -ArgumentList '/ErrorStdOut', '/validate', "`"$root\코드로넘기기.ahk`"" -Wait -PassThru -NoNewWindow

if ($p.ExitCode -ne 0) { Fail "스크립트 검사 실패 (exit $($p.ExitCode))" }

$exe = Join-Path $stage '코드로넘기기.exe'
$p = Start-Process $ahk2exe -ArgumentList '/in', "`"$root\코드로넘기기.ahk`"", '/out', "`"$exe`"", '/base', "`"$base`"", '/silent' -Wait -PassThru

if ($p.ExitCode -ne 0 -or -not (Test-Path $exe)) { Fail "exe 빌드 실패 (exit $($p.ExitCode))" }

Write-Host ('exe 빌드  {0:N0} 바이트' -f (Get-Item $exe).Length)

# ---------- 4) 같이 넣을 것 ----------
Copy-Item "$root\사이트\*.ini" (Join-Path $stage '사이트')

$lines = Get-ChildItem (Join-Path $stage '사이트') -Filter *.ini | Sort-Object Name | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}

[IO.File]::WriteAllLines((Join-Path $stage '사이트\원본.txt'), [string[]]$lines, $utf8)

foreach ($f in '코드로넘기기_설명.txt', 'README.md', 'CHANGELOG.md') {
    Copy-Item "$root\$f" $stage
}

# ---------- 5) zip 과 SHA256 ----------
#   .NET 으로 만든다: 한글 파일 이름을 UTF-8 표시와 함께 넣어, 윈도우 탐색기와 tar 가 모두 제대로 읽는다
$zipName = "edu-auto-next-$tag.zip"
$zip = Join-Path $dist $zipName

Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'), "$hash  $zipName`n", $utf8)

# ---------- 6) 릴리스 설명 ----------
$body = @"
$notes

---

### 받기
- ``$zipName`` 을 받아 원하는 폴더에 풀고 ``코드로넘기기.exe`` 를 실행하세요. 설치나 레지스트리 설정은 필요 없습니다.
- v1.6.0 부터는 켤 때 새 버전이 있으면 알려 주고, [예] 를 누르면 알아서 바꿉니다. 개인 설정과 직접 고친 사이트 프로필은 그대로 둡니다.
- v1.5.0 이하 exe 는 스스로 바꾸지 못하니, 이번 한 번은 직접 받아 주세요.
- 서명하지 않은 exe 라 처음 실행할 때 Windows 경고가 뜰 수 있습니다. ([추가 정보] → [실행])
- SHA256 (``$zipName``): ``$hash``
"@

[IO.File]::WriteAllText((Join-Path $dist 'notes.md'), $body, $utf8)

Write-Host "zip       $zip"
Write-Host "SHA256    $hash"

if (-not $Publish) {
    Write-Host ''
    Write-Host '빌드만 했습니다. 올리려면:  .\release.ps1 -Publish'
    exit 0
}

# ---------- 7) 올리기 ----------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail 'gh (GitHub CLI) 가 없습니다.  winget install --id GitHub.cli' }

gh auth status *> $null

if ($LASTEXITCODE -ne 0) { Fail 'gh 로그인이 필요합니다.  gh auth login' }

if (git status --porcelain) { Fail '커밋하지 않은 변경이 있습니다. 먼저 커밋하세요.' }

git fetch origin --tags --quiet

$head = (git rev-parse HEAD).Trim()

if (git tag -l $tag) {
    $at = (git rev-list -n 1 $tag).Trim()

    if ($at -ne $head) { Fail "태그 $tag 가 이미 다른 커밋에 있습니다." }
} else {
    git tag -a $tag -m $tag

    if ($LASTEXITCODE -ne 0) { Fail '태그를 만들지 못했습니다' }
}

git push origin HEAD

if ($LASTEXITCODE -ne 0) { Fail 'push 실패' }

git push origin $tag

if ($LASTEXITCODE -ne 0) { Fail '태그 push 실패' }

gh release create $tag $zip (Join-Path $dist 'SHA256SUMS.txt') --title $tag --notes-file (Join-Path $dist 'notes.md') --verify-tag

if ($LASTEXITCODE -ne 0) { Fail '릴리스를 만들지 못했습니다' }

Write-Host ''
Write-Host "올렸습니다: https://github.com/Obsidiankorea/edu-auto-next/releases/tag/$tag"
