좋습니다. 아래는 지금까지 합의한 방향을 기준으로 정리한 **milkit SPEC 초안**입니다.
범위는 요청하신 대로 **개요**와 **Public API** 중심입니다.

---

# milkit SPEC

## 1. 개요

### 1.1 목적

`milkit`은 **PowerShell 5.*** 환경에서 동작하는 경량 HTTP 서버 프레임워크다.

이 프레임워크의 목적은 서버 개발 시 반복적으로 작성되는 다음 요소를 추상화하는 것이다.

* HTTP 서버 시작 및 종료
* 요청 수신 및 라우팅
* JSON 요청 파싱 및 JSON 응답 작성
* 상태 코드 기반 응답 처리
* 정적 파일(static) 서빙
* 공통 예외 처리
* 404 / 500 기본 처리
* 공통 미들웨어 적용

`milkit`은 `express`, `flask`와 유사하게, 서버 작성자가 저수준 `HttpListener` 처리나 `method/path` 직접 비교 대신 **라우트와 핸들러 중심**으로 서버를 구성할 수 있도록 설계한다.

---

### 1.2 목표

`milkit`의 목표는 다음과 같다.

1. **PowerShell 5 기반 운영**

   * Windows PowerShell 5.* 환경에서 동작해야 한다.
   * 가능한 한 C# 또는 별도 컴파일 구성요소에 의존하지 않는다.

2. **간결한 서버 작성 경험 제공**

   * 서버 작성자는 라우트 등록, 응답 작성, static 등록에 집중할 수 있어야 한다.
   * 저수준 스트림 처리, 상태 코드 작성, 헤더 처리 등의 반복 작업은 프레임워크가 담당한다.

3. **PowerShell다운 API 유지**

   * 공개 API는 `Verb-Noun` 스타일을 따른다.
   * 프레임워크 이름인 `milkit` 또는 `Mil` 접두사를 공개 함수명에 반복해서 사용하지 않는다.

4. **상대경로 기반 static 관리**

   * static 파일 경로는 앱 루트 기준 상대경로로 선언한다.
   * 외부에는 URL prefix만 노출하며, 내부 파일 시스템 절대경로는 감춘다.

5. **핸들러 분리 지원**

   * 인라인 script block 뿐 아니라 별도 함수 정의 후 연결하는 방식도 지원한다.

---

### 1.3 비목표

초기 버전(v1)에서 `milkit`의 범위에 포함하지 않는 항목은 다음과 같다.

* 템플릿 엔진 렌더링
* 세션 / 쿠키 관리
* multipart 파일 업로드
* WebSocket
* 고급 라우트 패턴 (`/users/:id` 등)
* 인증/인가 프레임워크
* 비동기 런타임 또는 멀티런스페이스 최적화
* CORS / compression / reverse proxy 기능 일체

이 항목들은 추후 확장 대상으로 둘 수 있으나, v1에서는 핵심 HTTP micro framework 역할에 집중한다.

---

### 1.4 설계 원칙

#### 1.4.1 라우팅 중심

라우트 등록의 중심 API는 `Add-Route` 하나로 통일한다.

별도의 `Get-Route`, `Post-Route` 등은 v1 public API에 포함하지 않는다.

#### 1.4.2 핸들러 추상화

라우트 핸들러는 `HttpListenerContext`를 직접 다루지 않는다.
프레임워크가 제공하는 request/response wrapper를 통해 요청과 응답을 처리한다.

#### 1.4.3 공개 API 최소화

공개 API는 가능한 작고 명확하게 유지한다.
복잡한 기능은 내부 구현 또는 이후 확장 대상으로 둔다.

#### 1.4.4 static 경로 일관성

정적 파일은 앱 루트 기준 상대경로로만 등록한다.
서버 구현 코드에 절대경로가 직접 노출되지 않도록 한다.

#### 1.4.5 함수 연결 허용

핸들러는 아래 두 방식 모두 허용한다.

* 인라인 script block
* 별도 함수 참조(`${function:Name}`)

이를 통해 라우팅 선언과 핸들러 구현을 분리할 수 있어야 한다.

---

### 1.5 기본 사용 예시

```powershell
$app = New-App -Root $PSScriptRoot

function Get-Home {
    param($req, $res)
    $res.Text('hello')
}

function Get-Health {
    param($req, $res)
    $res.Ok(@{
        status = 'ok'
    })
}

Add-Route $app GET '/' ${function:Get-Home}
Add-Route $app GET '/health' ${function:Get-Health}
Use-Static $app '/public' './public'

Start-App $app -Port 8080
```

---

## 2. Public API

## 2.1 목록

`milkit` v1의 public API는 다음과 같다.

* `New-App`
* `Start-App`
* `Stop-App`
* `Add-Route`
* `Use-Static`
* `Use`
* `Set-NotFoundHandler`
* `Set-ErrorHandler`

---

## 2.2 `New-App`

### 목적

앱 인스턴스를 생성한다.

### 시그니처

```powershell
New-App
    [-Root <string>]
    [-Name <string>]
```

### 파라미터

#### `-Root <string>`

* 앱의 루트 경로
* 상대경로 기반 리소스(static, file 응답 등)의 기준점
* 지정하지 않으면 구현 정책에 따른 기본 경로를 사용한다

#### `-Name <string>`

* 앱 식별용 이름
* 로깅 또는 내부 진단 정보에 사용할 수 있다

### 반환값

* App 객체

### 동작 규약

* 앱 객체는 라우트, static 규칙, 미들웨어, 에러 핸들러, 실행 상태 등을 저장한다
* `-Root`는 내부적으로 절대경로로 normalize 할 수 있다

### 예시

```powershell
$app = New-App -Root $PSScriptRoot -Name 'sample'
```

---

## 2.3 `Start-App`

### 목적

앱을 HTTP 서버로 실행한다.

### 시그니처

```powershell
Start-App
    -App <psobject>
    [-Port <int>]
    [-BindHost <string>]
    [-Prefix <string[]>]
```

### 파라미터

#### `-App <psobject>`

* `New-App`으로 생성된 앱 객체

#### `-Port <int>`

* 서버 포트 번호

#### `-BindHost <string>`

* 서버 바인딩 호스트
* 기본값은 구현 정책에 따른다

#### `-Prefix <string[]>`

* `HttpListener` prefix를 직접 지정할 수 있는 고급 옵션
* 지정 시 `Host/Port` 조합보다 우선 적용할 수 있다

### 반환값

* 없음

### 동작 규약

* 내부적으로 HTTP listener를 시작한다
* 요청 수신 루프를 시작한다
* route, static, middleware, not-found, error 처리 규약을 사용한다

### 예시

```powershell
Start-App -App $app -Port 8080
```

---

## 2.4 `Stop-App`

### 목적

실행 중인 앱을 종료한다.

### 시그니처

```powershell
Stop-App
    -App <psobject>
```

### 파라미터

#### `-App <psobject>`

* 실행 중인 앱 객체

### 반환값

* 없음

### 동작 규약

* listener를 중지한다
* 실행 상태를 종료 상태로 변경한다

### 예시

```powershell
Stop-App -App $app
```

---

## 2.5 `Add-Route`

### 목적

HTTP 라우트를 등록한다.

### 시그니처

명시형:

```powershell
Add-Route
    -App <psobject>
    -Method <string[]>
    -Path <string>
    -Handler <scriptblock | function reference>
```

축약형:

```powershell
Add-Route <App> <Method> <Path> <Handler>
```

### 파라미터

#### `-App <psobject>`

* 라우트를 등록할 앱 객체

#### `-Method <string[]>`

* 허용할 HTTP 메서드 목록
* v1 허용 값:

  * `GET`
  * `POST`
  * `PUT`
  * `DELETE`
  * `PATCH`
  * `HEAD`
  * `OPTIONS`
  * `*`

#### `-Path <string>`

* 매칭할 요청 경로
* v1에서는 exact path match만 지원한다

#### `-Handler <scriptblock | function reference>`

* 요청 처리 핸들러
* 아래 형식을 허용한다

  * 인라인 script block
  * `${function:FunctionName}` 형태의 함수 참조

### 반환값

* 없음 또는 내부 route 객체
* v1에서는 반환값 없이 등록만 수행해도 충분하다

### 핸들러 규약

라우트 핸들러는 아래 형태를 따른다.

```powershell
param($req, $res)
```

### 동작 규약

* 등록 시 handler를 실행 가능한 형태로 normalize 한다
* 요청 시 method + path 기준으로 route를 찾는다
* 일치하는 route가 있으면 연결된 handler를 호출한다

### 예시

#### 인라인 script block

```powershell
Add-Route $app GET '/health' {
    param($req, $res)
    $res.Ok(@{ status = 'ok' })
}
```

#### 함수 연결

```powershell
function Get-Health {
    param($req, $res)
    $res.Ok(@{ status = 'ok' })
}

Add-Route $app GET '/health' ${function:Get-Health}
```

---

## 2.6 `Use-Static`

### 목적

정적 파일 서빙 규칙을 등록한다.

### 시그니처

명시형:

```powershell
Use-Static
    -App <psobject>
    -Prefix <string>
    -Path <string>
    [-DefaultDocument <string[]>]
```

축약형:

```powershell
Use-Static <App> <Prefix> <Path>
```

### 파라미터

#### `-App <psobject>`

* static 규칙을 등록할 앱 객체

#### `-Prefix <string>`

* 외부 URL 경로 prefix
* 예: `/public`

#### `-Path <string>`

* 앱 루트 기준 상대경로
* 예: `./public`, `./assets`

#### `-DefaultDocument <string[]>`

* 디렉터리 요청 시 기본 반환할 문서 목록
* 예: `index.html`

### 반환값

* 없음

### 동작 규약

* `-Path`는 앱 루트 기준 상대경로로 해석한다
* 내부적으로 절대경로로 resolve 한다
* 요청 URL에서 `-Prefix`를 제거한 상대 파일 경로를 계산한다
* 최종 경로가 static root 하위인지 검증해야 한다
* directory traversal 공격을 방지해야 한다

### 예시

```powershell
Use-Static $app '/public' './public'
Use-Static -App $app -Prefix '/assets' -Path './assets'
```

---

## 2.7 `Use`

### 목적

공통 미들웨어를 등록한다.

### 시그니처

```powershell
Use
    -App <psobject>
    -Handler <scriptblock | function reference>
```

또는 축약형:

```powershell
Use <App> <Handler>
```

### 파라미터

#### `-App <psobject>`

* 미들웨어를 등록할 앱 객체

#### `-Handler <scriptblock | function reference>`

* 미들웨어 핸들러
* 인라인 script block 또는 함수 참조 허용

### 반환값

* 없음

### 핸들러 규약

미들웨어는 아래 형태를 따른다.

```powershell
param($req, $res, $next)
```

### 동작 규약

* 등록 순서대로 실행된다
* `$next` 호출을 통해 다음 단계로 흐름을 넘긴다
* v1에서는 간단한 전처리/후처리 목적 위주로 사용한다

### 예시

```powershell
Use $app {
    param($req, $res, $next)
    Write-Host "$($req.Method) $($req.Path)"
    & $next
}
```

#### 함수 연결

```powershell
function Write-RequestLog {
    param($req, $res, $next)
    Write-Host "$($req.Method) $($req.Path)"
    & $next
}

Use $app ${function:Write-RequestLog}
```

---

## 2.8 `Set-NotFoundHandler`

### 목적

라우트 및 static 규칙에 매칭되지 않은 요청의 기본 처리기를 등록한다.

### 시그니처

```powershell
Set-NotFoundHandler
    -App <psobject>
    -Handler <scriptblock | function reference>
```

### 파라미터

#### `-App <psobject>`

* 앱 객체

#### `-Handler <scriptblock | function reference>`

* not found 처리 핸들러

### 반환값

* 없음

### 핸들러 규약

```powershell
param($req, $res)
```

### 동작 규약

* route, static 모두 미매칭일 때 호출된다
* 지정하지 않으면 framework 기본 404 응답을 사용한다

### 예시

```powershell
Set-NotFoundHandler $app {
    param($req, $res)
    $res.NotFound(@{ message = 'not found' })
}
```

---

## 2.9 `Set-ErrorHandler`

### 목적

핸들러 또는 미들웨어 실행 중 발생한 예외를 공통 처리한다.

### 시그니처

```powershell
Set-ErrorHandler
    -App <psobject>
    -Handler <scriptblock | function reference>
```

### 파라미터

#### `-App <psobject>`

* 앱 객체

#### `-Handler <scriptblock | function reference>`

* 에러 처리 핸들러

### 반환값

* 없음

### 핸들러 규약

```powershell
param($req, $res, $err)
```

### 동작 규약

* 라우트 핸들러, 미들웨어, static 처리 중 발생한 예외를 공통 처리한다
* 지정하지 않으면 framework 기본 500 응답을 사용한다

### 예시

```powershell
Set-ErrorHandler $app {
    param($req, $res, $err)
    $res.InternalServerError(@{
        message = 'internal server error'
    })
}
```

#### 함수 연결

```powershell
function Handle-Error {
    param($req, $res, $err)
    $res.InternalServerError(@{
        message = $err.Exception.Message
    })
}

Set-ErrorHandler $app ${function:Handle-Error}
```

---

## 3. 공통 핸들러 규약

### 3.1 Route Handler

```powershell
param($req, $res)
```

### 3.2 Middleware Handler

```powershell
param($req, $res, $next)
```

### 3.3 NotFound Handler

```powershell
param($req, $res)
```

### 3.4 Error Handler

```powershell
param($req, $res, $err)
```

---

## 4. Handler 연결 규칙

public API 중 handler를 받는 함수는 모두 다음 두 방식을 지원한다.

* 인라인 script block
* `${function:Name}` 형태의 함수 참조

적용 대상:

* `Add-Route`
* `Use`
* `Set-NotFoundHandler`
* `Set-ErrorHandler`

### 예시

```powershell
function Get-Health {
    param($req, $res)
    $res.Ok(@{ status = 'ok' })
}

Add-Route $app GET '/health' ${function:Get-Health}
```

```powershell
Add-Route $app POST '/echo' {
    param($req, $res)
    $res.Ok(@{ received = $req.Json() })
}
```

---

## 5. 요약

`milkit` v1은 PowerShell 5 환경에서 다음 public API를 제공하는 경량 HTTP 프레임워크다.

* `New-App`
* `Start-App`
* `Stop-App`
* `Add-Route`
* `Use-Static`
* `Use`
* `Set-NotFoundHandler`
* `Set-ErrorHandler`

이 프레임워크는 다음 원칙을 따른다.

* 공개 API는 PowerShell다운 명명 사용
* 라우팅은 `Add-Route` 중심으로 통일
* static은 앱 루트 기준 상대경로로 등록
* 핸들러는 인라인 또는 함수 연결 모두 지원
* JSON 응답, 상태 코드 처리, 공통 예외 처리를 프레임워크가 담당