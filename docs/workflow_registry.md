# 워크플로우 레지스트리 (라이브 n8n)

생성일: 2026-06-02 · n8n: native `http://localhost:5678` (v2.56.0) · 상태: 전부 **active**

| # | 이름 | n8n ID | webhook path | method | export 파일 |
|---|------|--------|--------------|--------|-------------|
| 01 | [BC44·파이프라인] 01 문서 인덱싱 | `UkAaB6vqATmoRqk2` | `document-ingest` | POST | `workflows/document-ingest.json` |
| 02 | [BC44·파이프라인] 02 RAG 채팅 | `l5FiRxpbkoQv7Jlq` | `rag-chat` | POST | `workflows/rag-chat.json` |
| 03 | [BC44·파이프라인] 03 웹 크롤링 | `o9uu5L3w1KO7pyUW` | `web-crawl` | POST | `workflows/web-crawl.json` |
| 04 | [BC44·파이프라인] 04 평가 시뮬레이션 | `q83JgEzoaf95nhnC` | `evaluation-simulate` | POST | `workflows/evaluation-simulate.json` |
| 05 | [BC44·파이프라인] 05 보고서 생성 | `ceOeKkZS7jSHqJbE` | `report-generate` | POST | `workflows/report-generate.json` |
| 06 | [BC44·파이프라인] 06 WBS 지연 점검 | `UXjXvJqH4KkwCxrQ` | `wbs-delay-check` | POST | `workflows/wbs-delay-check.json` |
| 07 | [BC44·파이프라인] 07 LLM 라우팅 | `Qmx5AEi25ybBlkwg` | `llm-route` | POST | `workflows/llm-route.json` |
| 08 | [BC44·파이프라인] 08 알림 | `q3hKK18G4WV88AC9` | `notify` | POST | `workflows/notify.json` |
| 09 | [BC44·파이프라인] 09 벡터 삭제·재색인 | `h9vUdJTAeLGivAPt` | `vector-reindex` | POST | `workflows/vector-reindex.json` |
| 10 | [BC44·파이프라인] 10 헬스체크 | `54x25z8fKKCrd1Ab` | `health` | GET | `workflows/health.json` |

## 공통 노드 구조 (01~09)

```
Webhook (POST, responseNode)
  → Process & Build Callback (Code: 토큰검증 + payload검증 + mock처리 + 콜백조립)
  → Send Callback (HTTP POST callback_url, onError=continueRegularOutput)
  → Respond (동기 응답 = 콜백 payload)
```
- 10 헬스체크: `Webhook(GET) → Health(Code) → Respond`
- 모든 워크플로우 settings: `saveDataSuccessExecution/Error = all` (결과 영구 보존).

## 재생성/갱신

- export: `.\scripts\export_workflows.ps1` (N8N_API_KEY env 필요)
- import: n8n UI → Import from File, 또는 MCP `n8n_create_workflow`.
