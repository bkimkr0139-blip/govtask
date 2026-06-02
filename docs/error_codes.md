# 에러 코드 목록 (Base44 contract 공통)

모든 workflow는 실패 시 아래 구조의 `error` 객체를 success/failed callback의 `error` 필드에 담아 반환한다.

```json
{
  "message": "사람이 읽을 수 있는 실패 사유",
  "node": "실패가 발생한 처리 단계/노드명",
  "code": "ERROR_CODE",
  "details": {}
}
```

전체 failed callback 형태:

```json
{
  "request_id": "REQ-001",
  "workflow_type": "document_ingestion",
  "project_id": "PRJ-2026-001",
  "status": "failed",
  "progress": 0,
  "result": null,
  "error": { "message": "...", "node": "Parse Document", "code": "DOCUMENT_PARSE_ERROR", "details": {} },
  "n8n_execution_id": "12345"
}
```

## 코드 표

| code | 의미 | 대표 발생 노드 | HTTP 상태(응답) |
|------|------|----------------|------|
| `AUTH_ERROR` | Authorization Bearer 토큰 누락/불일치 | Validate Token | 200(콜백패턴), 401(동기) |
| `VALIDATION_ERROR` | 필수 payload 필드 누락/형식 오류 | Validate Payload | 200/400 |
| `FILE_DOWNLOAD_ERROR` | file_url 다운로드 실패 | Download File | 200 |
| `DOCUMENT_PARSE_ERROR` | PDF/DOCX/HWP 등 파싱 실패 | Parse Document | 200 |
| `EMBEDDING_ERROR` | 임베딩 생성 실패 | Generate Embedding | 200 |
| `VECTOR_UPSERT_ERROR` | Vector DB 저장 실패 | Vector Upsert | 200 |
| `VECTOR_SEARCH_ERROR` | Vector 검색 실패 | Vector Search | 200 |
| `LLM_CALL_ERROR` | LLM 호출 실패(외부/로컬) | LLM Route / LLM Call | 200 |
| `CRAWL_ERROR` | 페이지 fetch/추출 실패 | Fetch Page | 200 |
| `DOMAIN_BLOCKED` | allowed_domains 밖의 URL 요청 | Validate URL | 200 |
| `CALLBACK_ERROR` | Base44 callback_url 전송 실패 | Send Callback | (로컬 로그 저장) |
| `POLICY_VIOLATION` | confidential 문서를 외부 LLM으로 보내려 함 | LLM Route | 200 |
| `INTERNAL_ERROR` | 위에 해당하지 않는 미분류 예외 | (해당 step) | 200/500 |

## 규칙

1. **AUTH_ERROR / VALIDATION_ERROR** 는 처리 시작 전 단계이므로 callback_url이 있으면 failed callback을 보내되, 동기 응답 코드는 각각 401/400을 권장(현재 mock 구현은 콜백패턴 일관성을 위해 200 + status:"failed" 반환).
2. `node` 필드에는 contract 처리 단계명(예: "Parse Document")을 그대로 적어 Base44가 어느 단계에서 실패했는지 식별 가능하게 한다.
3. `details` 에는 디버깅 보조 정보(누락 필드 목록, 원본 HTTP status 등)를 넣되 **문서 원문/개인정보는 넣지 않는다**(보안 지시 §18).
4. `CALLBACK_ERROR` 는 Base44로 전송 자체가 실패한 경우다. 이때도 workflow는 중단하지 않고 결과 JSON을 `storage/logs/` 와 n8n execution log에 남긴다(원칙 §6).
