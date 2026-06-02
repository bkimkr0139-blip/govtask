# Base44 ↔ n8n 연동 가이드

> 목표: **Base44가 `N8N_BASE_URL` 하나만 연결하면** 버튼 → n8n workflow 실행 →
> 결과 callback 수신까지 동작하는 상태. 현재 모든 workflow는 **mock 모드**로
> Base44 contract와 동일한 JSON을 반환한다(실제 Qdrant/LLM은 후속 스왑).

---

## 1. 연결 구조

```
[Base44 (cloud)]
   │  ① POST https://<N8N_BASE_URL>/webhook/<path>   (Authorization: Bearer <token>)
   ▼
[cloudflared/ngrok 터널] ──► [로컬 native n8n  http://localhost:5678]
   ▲                                   │
   │  ② callback (success/failed)      ▼
[Base44 /api/workflow-callback] ◄── [n8n Send Callback 노드]
```

- 로컬 n8n은 외부에서 직접 접근 불가 → 터널로 공개 URL 생성(→ `docs/local_proxy_setup.md`).
- Base44에는 그 공개 URL을 **`N8N_BASE_URL`**(또는 `N8N_PROXY_URL`)로 등록한다.
- 호출 주소 패턴: `{N8N_BASE_URL}/webhook/{path}`

---

## 2. 엔드포인트 목록 (현재 라이브, active)

| # | path | method | workflow_type | 용도 |
|---|------|--------|---------------|------|
| 01 | `/webhook/document-ingest` | POST | `document_ingestion` | 문서 파싱·청킹·임베딩·벡터 저장 |
| 02 | `/webhook/rag-chat` | POST | `rag_chat` | 출처기반 RAG 답변 |
| 03 | `/webhook/web-crawl` | POST | `web_crawl` | 공고/기관 페이지 크롤링 |
| 04 | `/webhook/evaluation-simulate` | POST | `evaluation_simulation` | RFP↔제안서 가채점 |
| 05 | `/webhook/report-generate` | POST | `report_generation` | 보고서 초안 생성 |
| 06 | `/webhook/wbs-delay-check` | POST | `wbs_delay_check` | WBS 지연 자동 이슈 |
| 07 | `/webhook/llm-route` | POST | `llm_route` | LLM 라우팅(로컬/외부/정책) |
| 08 | `/webhook/notify` | POST | `notification` | 알림 발송 |
| 09 | `/webhook/vector-reindex` | POST | `vector_delete_reindex` | 벡터 삭제·재색인 |
| 10 | `/webhook/health` | GET | - | 헬스체크(인증 불필요) |

n8n 워크플로우 ID는 `docs/workflow_registry.md` 참조.

---

## 3. 공통 요청 규격

### 헤더
```http
Authorization: Bearer {N8N_WEBHOOK_TOKEN}
Content-Type: application/json
X-Project-Id: {project_id}     # 선택(본문 우선)
X-User-Id: {user_id}           # 선택
X-Request-Id: {request_id}     # 선택
```
- 인증: `Authorization: Bearer` 토큰을 n8n의 `N8N_WEBHOOK_TOKEN`과 대조.
  - 현재 native n8n에 해당 env 미설정 → workflow는 **`dev-local-token`** 으로 폴백(개발용).
  - 운영 토큰 적용: native n8n 환경에 `N8N_WEBHOOK_TOKEN=<강한값>` 설정 후 재시작
    → Base44는 동일 값을 Bearer로 전송.

### 본문(공통 필수 필드 — 원칙 §3)
모든 workflow는 다음을 처리한다. **필드명을 변경하지 말 것.**
```
request_id, project_id, user_id, callback_url   (+ workflow별 추가 필드)
```
- `callback_url` 누락 시 `BASE44_CALLBACK_URL`(기본 mock) 로 폴백.
- 워크플로별 본문 예시는 `samples/payloads/*.json` 참조.

---

## 4. 공통 응답/콜백 규격 (원칙 §4 — Base44 contract 동일)

워크플로우는 **동기 HTTP 응답**과 **callback** 으로 **같은 JSON** 을 반환한다.

### 성공
```json
{
  "request_id": "REQ-001",
  "workflow_type": "document_ingestion",
  "project_id": "PRJ-2026-001",
  "status": "success",
  "progress": 100,
  "result": { },
  "error": null,
  "n8n_execution_id": "56741"
}
```
### 실패
```json
{
  "request_id": "REQ-001",
  "workflow_type": "document_ingestion",
  "project_id": "PRJ-2026-001",
  "status": "failed",
  "progress": 0,
  "result": null,
  "error": { "message": "...", "node": "Parse Document", "code": "DOCUMENT_PARSE_ERROR", "details": {} },
  "n8n_execution_id": "56741"
}
```
에러 코드: `docs/error_codes.md`.

---

## 5. Base44가 구현할 Callback Receiver

엔드포인트(예): `POST /api/workflow-callback`
- 헤더: `Authorization: Bearer {BASE44_CALLBACK_TOKEN}` (n8n이 전송)
- 본문: 위 §4 JSON
- 처리: `request_id` 로 원 요청 매칭 → `status`/`result`/`error` 반영 →
  Document.index_status, Report 버전, Issue 후보 등 엔티티 갱신.
- 응답: 2xx 반환(아무 본문). 실패해도 n8n은 결과를 로컬 로그에 보존(원칙 §6).

> Base44 준비 전: 본 저장소의 mock 수신기(`mock/mock_callback_server.cjs`, 포트 4000)가
> 콜백을 받아 `mock/logs/callbacks.log` 에 JSONL로 적재한다.

---

## 6. Polling / 수동 업데이트 폴백 (원칙 §7)

callback이 실패하거나 Base44가 아직 수신 엔드포인트를 못 갖춘 경우:
1. **동기 응답** 자체가 결과 JSON이므로 호출측이 즉시 사용 가능.
2. n8n 실행 로그에 전체 결과 보존(워크플로우 settings: `saveDataSuccessExecution/Error = all`).
   - 조회: `GET {n8n}/api/v1/executions/{id}` (X-N8N-API-KEY) → `data` 에 결과 포함.
3. mock 수신기 `GET http://localhost:4000/callbacks` 로 최근 50건 복사 가능.

---

## 7. mock → live 전환 (후속)

각 workflow의 `Process & Build Callback` Code 노드 상단에 분기:
```js
if (PIPELINE_MODE === 'live') { /* 실제 서비스 호출 */ }
```
live 전환 시 권장 노드 교체:
- document-ingest: HTTP Request → MCP Gateway `document.parse/chunk`, `embedding.create`, `vector.upsert`
- rag-chat: `vector.search` → `llm-route` 호출 → citation 조립
- web-crawl: HTTP Request fetch + HTML 추출 노드
- llm-route: 실제 `llm.call`(외부/로컬 SLLM)

env `PIPELINE_MODE=live` + `QDRANT_URL`/`MCP_GATEWAY_URL`/`LOCAL_SLLM_BASE_URL` 설정 필요.

---

## 8. 연결 체크리스트

```
[ ] 1. native n8n 가동 확인:  GET http://localhost:5678/webhook/health → status ok
[ ] 2. (운영) N8N_WEBHOOK_TOKEN 설정 후 재시작, Base44와 토큰 공유
[ ] 3. 터널 기동:  cloudflared tunnel --url http://localhost:5678
[ ] 4. 공개 URL 확인:  GET https://<공개URL>/webhook/health → status ok
[ ] 5. Base44에 N8N_BASE_URL=<공개URL> 등록
[ ] 6. Base44 콜백 엔드포인트 구현(/api/workflow-callback) 또는 mock 사용
[ ] 7. 샘플 호출:  bash scripts/curl_samples.sh  (또는 .\scripts\test_all.ps1)
[ ] 8. 콜백 수신 검증:  .\scripts\callback_test.ps1
```

완료되면 Base44 UI 버튼 → n8n workflow 실행 → 콜백 반영까지 동작한다.
