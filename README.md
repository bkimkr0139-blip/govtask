# BC44 — n8n + MCP AI 과제 자동화 파이프라인

Base44(프론트/UI/엔드포인트) ↔ 로컬 n8n(문서처리·RAG·크롤링·평가·보고서·WBS·LLM 라우팅) 연동 파이프라인.
지시서: `../claude_code_n8n_mcp_pipeline_instruction.md`

> **현재 상태**: 10개 워크플로우가 로컬 native n8n(`http://localhost:5678`, v2.56.0)에
> **생성·검증·활성화 완료**. 외부 서비스(Qdrant/LLM/MCP Gateway) 미가동이라 **mock 모드**로
> Base44 contract와 동일한 JSON을 반환한다. Base44는 `N8N_BASE_URL` 만 연결하면 호출 가능.

---

## 빠른 시작

```powershell
# 0) env 준비
copy .env.example .env        # 값 확인/수정

# 1) n8n 헬스체크 (native n8n이 이미 가동 중)
curl http://localhost:5678/webhook/health

# 2) mock 콜백 서버 기동 (Base44 미완 상태용)
node mock\mock_callback_server.cjs        # 포트 4000

# 3) 전체 워크플로우 샘플 호출
powershell -File scripts\test_all.ps1
#   또는  bash scripts/curl_samples.sh

# 4) end-to-end 콜백 검증
powershell -File scripts\callback_test.ps1

# 5) 외부 공개 (Base44에서 호출 가능하게)
cloudflared tunnel --url http://localhost:5678
#   => 출력된 https URL 을 Base44에 N8N_BASE_URL 로 등록
```

curl 단건 예:
```bash
curl -X POST http://localhost:5678/webhook/document-ingest \
  -H "Authorization: Bearer dev-local-token" \
  -H "Content-Type: application/json" \
  --data-binary @samples/payloads/document-ingest.json
```

---

## 디렉터리 / 산출물 맵

| 산출물(지시서 요구) | 위치 |
|----------------------|------|
| 1. n8n workflow JSON export | `workflows/*.json` (10종) |
| 2. docker-compose.yml | `docker-compose.yml` |
| 3. .env.example | `.env.example` |
| 4. sample payload JSON | `samples/payloads/*.json` |
| 5. sample curl scripts | `scripts/curl_samples.sh`, `scripts/test_all.ps1` |
| 6. callback test script | `scripts/callback_test.ps1` + `mock/mock_callback_server.cjs` |
| 7. Base44 연동 가이드 | `docs/base44_integration_guide.md` |
| 8. health-check workflow | n8n `10 헬스체크` + `workflows/health.json` |
| 9. error code 목록 | `docs/error_codes.md` |
| 10. local_proxy 설정 가이드 | `docs/local_proxy_setup.md` |
| (부록) 워크플로우 ID 레지스트리 | `docs/workflow_registry.md` |
| (부록) MCP Gateway 스텁 | `services/mcp-gateway/` |
| (부록) export 스크립트 | `scripts/export_workflows.ps1` |

---

## 워크플로우 (전부 active)

| path | workflow_type | 비고 |
|------|---------------|------|
| `document-ingest` | document_ingestion | mock: page/chunk/collection 반환 |
| `rag-chat` | rag_chat | mock: answer + citations |
| `web-crawl` | web_crawl | 도메인 allowlist 실검증 + mock 페이지 |
| `evaluation-simulate` | evaluation_simulation | mock: 항목별 점수 schema |
| `report-generate` | report_generation | mock: section별 초안 |
| `wbs-delay-check` | wbs_delay_check | **실로직**: 지연일/severity/중복방지 |
| `llm-route` | llm_route | **실정책**: confidential→local, hybrid 등 |
| `notify` | notification | mock 발송 |
| `vector-reindex` | vector_delete_reindex | mock 삭제·재색인 |
| `health` | - | GET, 인증 불필요 |

상세 요청/응답 규격 → `docs/base44_integration_guide.md`, `docs/workflow_registry.md`.

---

## 설계 원칙 준수 체크 (사용자 10원칙)

- ① contract 우선: Base44 `workflow_contracts.*` 부재 → 지시서 §6~13 규격을 contract로 채택.
- ② payload 필드명 불변: `request_id/project_id/workflow_type/user_id/callback_url` 그대로 처리.
- ③ 공통 식별자 전 워크플로우 검증(헤더/본문 병행).
- ④ 성공/실패 콜백 모두 contract 동일 JSON.
- ⑤ 외부 공개: cloudflared/ngrok/FRP 가이드 제공(`docs/local_proxy_setup.md`).
- ⑥ 콜백 실패해도 결과 보존: n8n execution log(`saveData*=all`) + mock JSONL 로그.
- ⑦ polling/수동 업데이트: 동기 응답 = 결과 JSON, `/api/v1/executions`, mock `/callbacks`.
- ⑧ health-check + sample curl 제공.
- ⑨ 실패 시 `error.{code,node,message,details}` 포함.
- ⑩ document-ingest/rag-chat/web-crawl/evaluation/report/wbs/llm-route + notify/vector/health 구현.

---

## mock → live 전환

`.env` 의 `PIPELINE_MODE=live` + 실제 서비스 URL 설정 후, 각 워크플로우 Code 노드의
`if (PIPELINE_MODE==='live')` 분기를 실제 HTTP/MCP 호출로 교체. 상세 → 연동 가이드 §7.
