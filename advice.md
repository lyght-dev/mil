# Ping Scheduling Check Advice

실제 서버 코드를 다 치기 전에 확인할 것은 두 가지다.

1. 현재 환경에서 `Ping.Send()`가 실제로 성공하는가
2. 10초 간격 반복이 실제로 돌아가는가

가장 간단한 방법은 “실제 서버와 같은 API로 1회 ping”과 “10초 간격 루프”를 따로 확인하는 것이다.

## 1. 핑이 되는가

`Ping.Send()` 자체를 먼저 확인하면 된다. 실제 코드 경로와 가장 가깝다.

```powershell
$p = New-Object System.Net.NetworkInformation.Ping
$r = $p.Send("8.8.8.8", 5000)
$r.Status
$r.RoundtripTime
$p.Dispose()
```

정상이라면 보통:

- `Status` = `Success`
- `RoundtripTime` = 숫자

전부 `TimedOut`이면:

- 대상이 ICMP에 응답하지 않거나
- 현재 환경이 ICMP를 막고 있는 것이다.

## 2. 스케줄링이 되는가

10초마다 반복 호출만 확인하면 된다.

```powershell
$p = New-Object System.Net.NetworkInformation.Ping
1..3 | ForEach-Object {
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $r = $p.Send("8.8.8.8", 5000)
    "{0} status={1} rtt={2}" -f $now, $r.Status, $r.RoundtripTime
    Start-Sleep -Seconds 10
}
$p.Dispose()
```

여기서 보면:

- 출력 시간이 10초 간격이면 스케줄링은 된다
- 각 회차의 `Status`/`rtt`로 ping 가능 여부를 바로 확인할 수 있다

## 3. 여러 호스트를 같이 보는 최소 확인

실제 서버 형태에 조금 더 가깝게 보려면:

```powershell
$hosts = @("8.8.8.8", "1.1.1.1")
$p = New-Object System.Net.NetworkInformation.Ping

1..3 | ForEach-Object {
    Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    foreach ($host in $hosts) {
        try {
            $r = $p.Send($host, 5000)
            "{0} status={1} rtt={2}" -f $host, $r.Status, $r.RoundtripTime
        } catch {
            "{0} error={1}" -f $host, $_.Exception.Message
        }
    }
    ""
    Start-Sleep -Seconds 10
}

$p.Dispose()
```

핵심은 이렇다.

- `Ping.Send()` 1회 테스트로 “핑이 되는가”
- `Start-Sleep 10` 포함 루프로 “스케줄링이 되는가”
