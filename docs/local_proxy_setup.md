# 로컬 n8n 외부 공개 설정 가이드 (ngrok / cloudflared / FRP)

Base44(클라우드)가 로컬 PC의 n8n(`http://localhost:5678`)을 직접 호출할 수 없으므로,
외부에서 접근 가능한 공개 URL을 만들어 Base44에 `N8N_BASE_URL`(또는 `N8N_PROXY_URL`)로 전달한다.

세 가지 방법 중 하나를 선택한다. **개발/시연은 cloudflared 임시 터널이 가장 간단**하다.

---

## 옵션 A. cloudflared (권장: 빠른 임시 터널, 계정 불필요)

```powershell
# 설치 (Windows, winget)
winget install --id Cloudflare.cloudflared

# 로컬 n8n(5678)을 임시 공개 URL로 노출
cloudflared tunnel --url http://localhost:5678
```

출력되는 `https://<random>.trycloudflare.com` 이 공개 URL이다.
- webhook 호출 주소: `https://<random>.trycloudflare.com/webhook/<path>`
- Base44에 전달: `N8N_BASE_URL=https://<random>.trycloudflare.com`

> 임시 터널 URL은 재시작 때마다 바뀐다. 고정 도메인이 필요하면 Cloudflare 계정 + named tunnel을 사용한다.
> (참고: 이 PC에는 SECL AX Twin 시연에서 `--config NUL` 임시터널 방식을 쓴 이력이 있음 — 동일 방식으로 충돌 없이 병행 가능.)

### 고정 도메인 named tunnel (선택)
```powershell
cloudflared tunnel login
cloudflared tunnel create n8n-pipeline
# config.yml 에 ingress 규칙 작성 후
cloudflared tunnel route dns n8n-pipeline n8n.example.com
cloudflared tunnel run n8n-pipeline
```

---

## 옵션 B. ngrok (계정 필요, 안정적)

```powershell
winget install --id Ngrok.Ngrok
ngrok config add-authtoken <YOUR_TOKEN>
ngrok http 5678
```

출력되는 `https://<random>.ngrok-free.app` 을 사용한다.
- Base44에 전달: `N8N_BASE_URL=https://<random>.ngrok-free.app`
- 무료 플랜도 URL이 재시작마다 바뀜. 고정은 유료 reserved domain.

### ngrok 주의
- 무료 플랜은 요청 시 인터스티셜(경고 페이지)이 뜰 수 있다. API 호출에는 헤더 `ngrok-skip-browser-warning: true` 를 추가하거나 유료 플랜을 사용.

---

## 옵션 C. FRP (자체 서버 보유 시 — 이 저장소 루트에 frp 바이너리 존재)

`C:\Users\User\works\base44\frp_0.69.0_*` 바이너리 활용. 공개 IP를 가진 서버(frps)와
로컬(frpc)을 연결해 `5678`을 노출한다.

```ini
# frpc.ini (로컬)
[common]
server_addr = <PUBLIC_SERVER_IP>
server_port = 7000

[n8n]
type = http
local_port = 5678
custom_domains = n8n.yourdomain.com
```
```powershell
.\frpc.exe -c .\frpc.ini
```
- Base44에 전달: `N8N_BASE_URL=https://n8n.yourdomain.com`

---

## 공통: native n8n의 WEBHOOK_URL 정렬

n8n이 생성하는 production webhook 절대 URL을 공개 URL과 맞추려면
n8n 환경변수 `WEBHOOK_URL` 을 공개 URL로 설정한 뒤 재시작한다.

```powershell
$env:WEBHOOK_URL = "https://<random>.trycloudflare.com/"
# native n8n 재시작
```

설정하지 않아도 webhook은 동작하지만, n8n UI가 표시하는 webhook 주소가 localhost로 나오므로
Base44에 전달할 주소는 수동으로 `<공개URL>/webhook/<path>` 형태로 구성한다.

---

## 검증

터널을 띄운 뒤 health-check workflow로 외부 접근을 확인한다.

```powershell
curl "https://<공개URL>/webhook/health"
# => {"status":"ok", ...}  (health workflow가 active 상태여야 함)
```
