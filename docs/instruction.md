# Claude Code 개발지시서  
## n8n Workflow + MCP 연동 기반 AI 과제 자동화 파이프라인 구현

문서 버전: v1.0  
작성일: 2026-06-02  
대상 도구: Claude Code  
대상 플랫폼: n8n, MCP Gateway, Vector DB, Object Storage, LLM Gateway  
연동 대상: Base44 AI 과제 자동화 시스템  
목표: Base44가 제공하는 프론트/엔드포인트/운영 UI와 연동되는 실제 실행 가능한 n8n 기반 RAG·문서처리·웹크롤링·자동화·LLM 파이프라인을 구현한다.

---

# 1. 개발 목표

Base44는 IDE 환경이 제공되고 프론트엔드/업무 UI/엔드포인트/서버 운영 화면 구현이 편리하다.  
그러나 문서 처리, RAG, 웹 크롤링, LLM 라우팅, 자동화 워크플로우는 품질의 일관성, 재실행성, 로그 추적, 단계별 오류 처리, 외부 시스템 연동이 중요하므로 n8n에서 구현한다.

Claude Code는 n8n workflow를 구성하고, 필요한 경우 MCP Gateway 또는 별도 API 서비스를 통해 Base44와 연결한다.

---

# 2. 전체 구성

```text
[Base44]
  ├── Frontend UI
  ├── Project / Document / Issue / Report Entity
  ├── API Endpoint
  └── Workflow Callback Receiver
        ↓
[n8n Webhook Workflows]
  ├── document-ingest
  ├── rag-chat
  ├── web-crawl
  ├── evaluation-simulate
  ├── report-generate
  ├── wbs-delay-check
  ├── llm-route
  └── notify
        ↓
[MCP Gateway / Tools]
  ├── File Parser
  ├── Web Crawler
  ├── Vector DB
  ├── Object Storage
  ├── External LLM
  ├── Local SLLM
  └── Notification
```

---

# 3. n8n 배포 구조

권장 Docker Compose 구조:

```text
infra/
├── docker-compose.yml
├── .env
├── n8n/
│   ├── workflows/
│   ├── credentials/
│   └── README.md
├── services/
│   ├── mcp-gateway/
│   ├── document-parser/
│   ├── crawler/
│   └── llm-gateway/
└── storage/
    ├── files/
    ├── parsed/
    └── logs/
```

---

# 4. 환경변수

```text
# n8n
N8N_HOST=n8n.example.com
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=change-me

# Base44
BASE44_BASE_URL=https://base44-app.example.com
BASE44_CALLBACK_URL=https://base44-app.example.com/api/workflow-callback
BASE44_CALLBACK_TOKEN=change-me

# Security
N8N_WEBHOOK_TOKEN=change-me
INTERNAL_API_TOKEN=change-me

# Vector DB
VECTOR_DB_PROVIDER=qdrant
QDRANT_URL=http://qdrant:6333
QDRANT_API_KEY=change-me
VECTOR_COLLECTION_PREFIX=project_

# Object Storage
STORAGE_PROVIDER=s3
S3_ENDPOINT=https://s3.example.com
S3_BUCKET=ai-project-docs
S3_ACCESS_KEY=change-me
S3_SECRET_KEY=change-me

# LLM
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=
LOCAL_SLLM_BASE_URL=http://local-llm:8000/v1
LOCAL_SLLM_MODEL=qwen2.5:14b
DEFAULT_LLM_PROVIDER=local
DEFAULT_EMBEDDING_MODEL=bge-m3
```

---

# 5. n8n Workflow 목록

Claude Code는 다음 workflow를 만든다.

```text
01_document_ingest.json
02_rag_chat.json
03_web_crawl.json
04_evaluation_simulate.json
05_report_generate.json
06_wbs_delay_check.json
07_llm_route.json
08_notification.json
09_vector_delete_reindex.json
10_health_check.json
```

각 workflow는 다음 공통 규칙을 따른다.

```text
- Webhook Trigger로 시작한다.
- Authorization Bearer Token을 검증한다.
- X-Project-Id, X-User-Id, X-Request-Id를 확인한다.
- request_id가 없으면 즉시 실패 처리한다.
- 각 단계별 로그를 남긴다.
- 성공/실패 결과를 Base44 callback_url로 전송한다.
- 실패 시 error_message와 failed_node 정보를 포함한다.
- 재실행 가능한 구조로 만든다.
```

---

# 6. 공통 요청/응답 규격

## 6.1 공통 Header

```http
Authorization: Bearer {N8N_WEBHOOK_TOKEN}
X-Project-Id: {project_id}
X-User-Id: {user_id}
X-Request-Id: {request_id}
Content-Type: application/json
```

## 6.2 공통 성공 Callback

```json
{
  "request_id": "REQ-001",
  "workflow_type": "document_ingestion",
  "project_id": "PRJ-2026-001",
  "status": "success",
  "progress": 100,
  "result": {},
  "error": null,
  "n8n_execution_id": "12345"
}
```

## 6.3 공통 실패 Callback

```json
{
  "request_id": "REQ-001",
  "workflow_type": "document_ingestion",
  "project_id": "PRJ-2026-001",
  "status": "failed",
  "progress": 0,
  "result": null,
  "error": {
    "message": "PDF parsing failed",
    "node": "Parse Document",
    "code": "PARSER_ERROR"
  },
  "n8n_execution_id": "12345"
}
```

---

# 7. Workflow 01: Document Ingest

## 7.1 목적

Base44에서 업로드한 문서를 받아 파싱, 정제, chunking, embedding, vector 저장까지 수행한다.

## 7.2 Webhook

```http
POST /webhook/document-ingest
```

## 7.3 Request

```json
{
  "request_id": "REQ-DOC-001",
  "project_id": "PRJ-2026-001",
  "document_id": "DOC-001",
  "file_name": "RFP.pdf",
  "file_url": "https://...",
  "file_type": "pdf",
  "callback_url": "https://base44-app/api/workflow-callback",
  "user_id": "user_001"
}
```

## 7.4 처리 단계

```text
1. Validate Token
2. Validate Payload
3. Download File
4. Detect File Type
5. Parse Document
   - pdf
   - docx
   - pptx
   - xlsx
   - hwp/hwpx 가능 시 별도 parser 사용
   - txt/md/html
6. Normalize Text
7. Extract Metadata
   - page
   - section
   - heading
   - table 여부
8. Chunking
   - 기본 800~1200 tokens
   - overlap 100~150 tokens
   - 표/목차/평가지표는 별도 chunk 보존
9. Generate Embedding
10. Upsert Vector DB
    - collection: project_{project_id}
    - payload: document_id, file_name, page, section, chunk_index
11. Callback Success
```

## 7.5 Vector Payload

```json
{
  "project_id": "PRJ-2026-001",
  "document_id": "DOC-001",
  "file_name": "RFP.pdf",
  "page": 12,
  "section": "3.2 주요 요구사항",
  "chunk_index": 45,
  "text": "...",
  "source_type": "uploaded_document",
  "created_at": "2026-06-02T09:00:00+09:00"
}
```

## 7.6 완료 결과

```json
{
  "document_id": "DOC-001",
  "index_status": "success",
  "page_count": 54,
  "chunk_count": 183,
  "vector_collection": "project_PRJ-2026-001"
}
```

---

# 8. Workflow 02: RAG Chat

## 8.1 목적

사용자 질문에 대해 과제별 문서 Vector DB를 검색하고, LLM으로 출처 기반 답변을 생성한다.

## 8.2 Webhook

```http
POST /webhook/rag-chat
```

## 8.3 Request

```json
{
  "request_id": "REQ-RAG-001",
  "project_id": "PRJ-2026-001",
  "session_id": "CHAT-001",
  "question": "이 RFP의 핵심 요구사항은?",
  "document_filter": ["DOC-001"],
  "top_k": 8,
  "response_style": "business_report",
  "callback_url": "https://base44-app/api/workflow-callback",
  "user_id": "user_001"
}
```

## 8.4 처리 단계

```text
1. Validate Token
2. Normalize Question
3. Generate Query Embedding
4. Vector Search
   - collection: project_{project_id}
   - filter: document_id in document_filter
5. Rerank Results
6. Determine Confidence
   - document_based: score high and enough chunks
   - mixed: partial evidence
   - general_knowledge: no strong evidence
7. Build Prompt
   - answer only with citations when possible
   - separate document evidence and inference
8. LLM Route Workflow 호출
9. Parse LLM Output
10. Attach Citations
11. Callback Result
```

## 8.5 Response

```json
{
  "answer": "핵심 요구사항은 ...",
  "confidence": "document_based",
  "citations": [
    {
      "document_id": "DOC-001",
      "file_name": "RFP.pdf",
      "page": 12,
      "section": "3.2 주요 요구사항",
      "chunk_id": "chunk_0045",
      "score": 0.87,
      "excerpt": "..."
    }
  ],
  "model_used": "local-sllm",
  "usage": {
    "input_tokens": 2200,
    "output_tokens": 680
  }
}
```

---

# 9. Workflow 03: Web Crawl

## 9.1 목적

공고 사이트, 기관 사이트, 과제 공고 페이지, 첨부 PDF 링크를 수집하고 정제한 뒤 문서로 등록할 수 있는 데이터를 반환한다.

## 9.2 Webhook

```http
POST /webhook/web-crawl
```

## 9.3 Request

```json
{
  "request_id": "REQ-CRAWL-001",
  "project_id": "PRJ-2026-001",
  "urls": ["https://example.go.kr/notice"],
  "crawl_depth": 1,
  "allowed_domains": ["example.go.kr"],
  "include_pdf_links": true,
  "callback_url": "https://base44-app/api/workflow-callback",
  "user_id": "user_001"
}
```

## 9.4 처리 단계

```text
1. Validate Token
2. Validate URL / Domain Allowlist
3. Fetch Page
4. Extract Main Content
5. Extract Links
6. If include_pdf_links, collect downloadable PDF/HWPX/DOCX links
7. Remove duplicated content
8. Save crawled pages as document records
9. Optional: call Document Ingest for each collected document
10. Callback Result
```

## 9.5 크롤링 제한

```text
- robots.txt 존중
- allowed_domains 외부 링크 차단
- depth 기본 1
- rate limit 적용
- 로그인 필요한 사이트는 별도 수동 업로드 우선
- 개인정보 포함 페이지 수집 금지
```

---

# 10. Workflow 04: Evaluation Simulate

## 10.1 목적

RFP와 제안서 문서를 비교하여 평가 항목별 예상 점수, 미흡 요소, 개선 제안을 생성한다.

## 10.2 Webhook

```http
POST /webhook/evaluation-simulate
```

## 10.3 처리 단계

```text
1. Validate Token
2. Load RFP chunks
3. Extract Evaluation Criteria
4. Load Proposal chunks
5. Match Proposal Evidence to Criteria
6. Score Each Criterion
7. Identify Weakness
8. Generate Improvement Suggestions
9. Return Structured JSON
```

## 10.4 출력 JSON Schema

```json
{
  "total_score": 83,
  "max_score": 100,
  "items": [
    {
      "criterion": "사업 이해도",
      "max_score": 20,
      "expected_score": 16,
      "evidence": [
        {
          "document_id": "DOC-PROP-001",
          "page": 5,
          "excerpt": "..."
        }
      ],
      "weakness": "정량 목표가 부족함",
      "improvement": "대기시간 50% 단축 등 KPI를 명시"
    }
  ],
  "critical_gaps": [],
  "recommended_actions": []
}
```

---

# 11. Workflow 05: Report Generate

## 11.1 목적

RAG 문서와 과제 정보를 기반으로 제안서, 중간보고서, 최종보고서, 발표자료 초안 등을 생성한다.

## 11.2 Webhook

```http
POST /webhook/report-generate
```

## 11.3 Request

```json
{
  "request_id": "REQ-REPORT-001",
  "project_id": "PRJ-2026-001",
  "report_id": "REPORT-001",
  "report_type": "interim_report",
  "section_outline": ["사업 개요", "추진 실적", "문제점", "향후 계획"],
  "source_document_ids": ["DOC-001", "DOC-002"],
  "generation_instruction": "공공기관 보고서 문체로 작성",
  "callback_url": "https://base44-app/api/workflow-callback",
  "user_id": "user_001"
}
```

## 11.4 처리 단계

```text
1. Validate Token
2. Load Project Context
3. Retrieve Relevant Chunks by section
4. Generate Section Drafts
5. Merge Sections
6. Citation Insert
7. Consistency Check
8. Return Report Content
```

## 11.5 응답

```json
{
  "report_id": "REPORT-001",
  "content": "# 중간보고서\n...",
  "sections": [
    {
      "title": "사업 개요",
      "content": "...",
      "citations": []
    }
  ],
  "model_used": "gpt-4.1",
  "source_documents": ["DOC-001", "DOC-002"]
}
```

---

# 12. Workflow 06: WBS Delay Check

## 12.1 목적

WBS 지연을 자동 감지하고 Issue 생성 후보를 반환한다.

## 12.2 Webhook

```http
POST /webhook/wbs-delay-check
```

## 12.3 Request

```json
{
  "request_id": "REQ-WBS-001",
  "project_id": "PRJ-2026-001",
  "wbs_items": [
    {
      "id": "WBS-001",
      "title": "RFP 분석",
      "assignee_id": "user_002",
      "due_date": "2026-06-01",
      "progress": 60,
      "status": "in_progress"
    }
  ],
  "existing_open_issues": [],
  "callback_url": "https://base44-app/api/workflow-callback",
  "user_id": "user_001"
}
```

## 12.4 지연 판단 규칙

```text
if due_date < today and progress < 100:
    delayed = true

delay_days:
    today - due_date

severity:
    1~2일: low
    3~6일: medium
    7~13일: high
    14일 이상: critical
```

## 12.5 응답

```json
{
  "issues_to_create": [
    {
      "project_id": "PRJ-2026-001",
      "wbs_id": "WBS-001",
      "title": "WBS 지연: RFP 분석",
      "description": "마감일이 1일 지났고 완료율은 60%입니다.",
      "source": "auto_wbs",
      "severity": "low",
      "status": "open",
      "assignee_id": "user_002",
      "auto_rule_id": "RULE-WBS-DELAY-001"
    }
  ],
  "issues_to_update": []
}
```

---

# 13. Workflow 07: LLM Route

## 13.1 목적

외부 LLM, Fallback LLM, 온프레미스 SLLM을 정책에 따라 선택하여 호출한다.

## 13.2 라우팅 전략

```text
external_primary:
  외부 LLM 우선 사용

local_first:
  온프레미스 SLLM 우선 사용

privacy_strict:
  confidential 문서는 local only

hybrid:
  문서 민감도, 작업 유형, 실패 여부에 따라 자동 선택
```

## 13.3 입력

```json
{
  "request_id": "REQ-LLM-001",
  "project_id": "PRJ-2026-001",
  "task_type": "rag_answer",
  "privacy_level": "confidential",
  "prompt": "...",
  "context": "...",
  "routing_strategy": "hybrid",
  "preferred_model": null
}
```

## 13.4 처리 단계

```text
1. Check privacy_level
2. Check routing_strategy
3. Select provider
4. Call model
5. If failed and policy allows, call fallback
6. Return output
7. Log model_used, latency, token_usage, cost_estimate
```

## 13.5 정책

```text
- privacy_level=confidential → local_sllm only
- task_type=evaluation/report → high quality external 가능
- task_type=rag_answer with confidential document → local first
- external failure → fallback external or local
- local failure → fallback external only if privacy policy allows
```

---

# 14. MCP Gateway 개발 지시

n8n이 직접 처리하기 어려운 작업은 MCP Gateway 또는 내부 API 서비스로 분리한다.

## 14.1 MCP Tools

```text
document.parse
document.chunk
embedding.create
vector.upsert
vector.search
vector.delete
web.fetch
web.extract_main_content
llm.call
storage.download
storage.upload
security.mask_pii
```

## 14.2 MCP Gateway API 예시

```http
POST /mcp/document.parse
POST /mcp/document.chunk
POST /mcp/embedding.create
POST /mcp/vector.upsert
POST /mcp/vector.search
POST /mcp/web.extract
POST /mcp/llm.call
```

## 14.3 document.parse 응답 예시

```json
{
  "document_id": "DOC-001",
  "pages": [
    {
      "page": 1,
      "text": "...",
      "tables": [],
      "images": [],
      "metadata": {}
    }
  ]
}
```

## 14.4 vector.search 응답 예시

```json
{
  "matches": [
    {
      "chunk_id": "chunk_0045",
      "score": 0.87,
      "payload": {
        "document_id": "DOC-001",
        "file_name": "RFP.pdf",
        "page": 12,
        "section": "3.2 주요 요구사항",
        "text": "..."
      }
    }
  ]
}
```

---

# 15. Docker Compose 예시

```yaml
version: "3.9"

services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - WEBHOOK_URL=${N8N_PROTOCOL}://${N8N_HOST}/
    volumes:
      - ./n8n/data:/home/node/.n8n
      - ./storage:/storage
    depends_on:
      - qdrant

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    ports:
      - "6333:6333"
    volumes:
      - ./qdrant/storage:/qdrant/storage

  mcp-gateway:
    build: ./services/mcp-gateway
    restart: unless-stopped
    ports:
      - "8088:8088"
    environment:
      - QDRANT_URL=http://qdrant:6333
      - INTERNAL_API_TOKEN=${INTERNAL_API_TOKEN}
      - LOCAL_SLLM_BASE_URL=${LOCAL_SLLM_BASE_URL}
```

---

# 16. 테스트 시나리오

## 16.1 문서 인덱싱 테스트

```text
1. Base44에서 RFP.pdf 업로드
2. document-ingest webhook 호출 확인
3. n8n 실행 성공 확인
4. Qdrant collection 생성 확인
5. chunk_count > 0 확인
6. Base44 Document index_status=success 확인
```

## 16.2 RAG Chat 테스트

```text
1. 인덱싱 완료 문서를 선택
2. 질문 입력
3. rag-chat webhook 호출
4. citations 포함 응답 확인
5. confidence=document_based 확인
6. Base44 채팅 이력 저장 확인
```

## 16.3 웹 크롤링 테스트

```text
1. 공고 URL 입력
2. web-crawl workflow 실행
3. 페이지 본문 추출
4. PDF 링크 추출
5. 문서 등록 및 인덱싱 연결 확인
```

## 16.4 평가 시뮬레이션 테스트

```text
1. RFP 문서 선택
2. 제안서 문서 선택
3. evaluation-simulate 실행
4. 항목별 점수와 근거 확인
5. 개선 제안 생성 확인
```

## 16.5 보고서 생성 테스트

```text
1. 보고서 유형 선택
2. 문서 선택
3. report-generate 실행
4. Base44 ReportVersion 생성 확인
5. 버전 이력 확인
```

## 16.6 WBS 자동 이슈 테스트

```text
1. due_date 지난 WBS 생성
2. progress 60 설정
3. wbs-delay-check 실행
4. auto_wbs Issue 생성 확인
5. 중복 Issue 생성 방지 확인
```

---

# 17. 에러 처리 기준

```text
- 문서 다운로드 실패: FILE_DOWNLOAD_ERROR
- 파싱 실패: DOCUMENT_PARSE_ERROR
- 임베딩 실패: EMBEDDING_ERROR
- Vector DB 저장 실패: VECTOR_UPSERT_ERROR
- 검색 실패: VECTOR_SEARCH_ERROR
- LLM 호출 실패: LLM_CALL_ERROR
- Callback 실패: CALLBACK_ERROR
- 인증 실패: AUTH_ERROR
- Payload 오류: VALIDATION_ERROR
```

각 에러는 다음 구조로 반환한다.

```json
{
  "message": "Vector DB upsert failed",
  "node": "Vector Upsert",
  "code": "VECTOR_UPSERT_ERROR",
  "details": {}
}
```

---

# 18. 보안 지시

```text
- Webhook token 검증 필수
- project_id namespace 분리 필수
- confidential 문서는 외부 LLM 전송 금지
- 개인정보 마스킹 옵션 제공
- LLM 호출 로그 저장
- 문서 원문 로그 저장 금지
- Vector payload에는 필요한 메타데이터만 저장
- callback_url allowlist 적용
```

---

# 19. Claude Code 실행 프롬프트

```text
너는 n8n, MCP Gateway, RAG, 문서처리, 웹크롤링, LLM Gateway를 구현하는 백엔드/워크플로우 개발자다.

Base44가 프론트엔드, 업무 UI, 엔드포인트, 운영 모니터링을 담당하고, 너는 n8n과 MCP 기반의 실제 실행 가능한 파이프라인을 구현해야 한다.

다음 작업을 수행하라.

1. Docker Compose로 n8n, qdrant, mcp-gateway 개발 환경을 구성하라.
2. n8n workflow를 다음 이름으로 생성하라.
   - 01_document_ingest
   - 02_rag_chat
   - 03_web_crawl
   - 04_evaluation_simulate
   - 05_report_generate
   - 06_wbs_delay_check
   - 07_llm_route
   - 08_notification
   - 09_vector_delete_reindex
   - 10_health_check
3. 모든 workflow는 Webhook Trigger로 시작하고 Authorization Bearer Token을 검증하라.
4. 모든 workflow는 X-Project-Id, X-User-Id, X-Request-Id를 검증하라.
5. 문서 업로드 workflow는 파일 다운로드, 파싱, 정제, chunking, embedding, vector upsert를 수행하라.
6. RAG chat workflow는 query embedding, vector search, rerank, prompt build, LLM route, citation response를 수행하라.
7. web-crawl workflow는 URL allowlist, fetch, main content extraction, link extraction, PDF link collection, optional document ingest를 수행하라.
8. evaluation workflow는 RFP 평가 기준 추출, 제안서 근거 매칭, 예상 점수, 미흡 요소, 개선 제안을 JSON으로 반환하라.
9. report-generate workflow는 문서 기반 보고서 초안을 생성하고 section별 citations를 포함하라.
10. wbs-delay-check workflow는 due_date와 progress 기준으로 auto_wbs Issue 후보를 생성하라.
11. llm-route workflow는 external primary, fallback, local_sllm, privacy_strict, hybrid routing을 지원하라.
12. 모든 workflow 결과는 Base44 callback_url로 success/failed callback을 전송하라.
13. MCP Gateway에는 document.parse, document.chunk, embedding.create, vector.upsert, vector.search, web.extract_main_content, llm.call API를 구현하라.
14. Qdrant collection은 project_id 기준으로 분리하라.
15. confidential 문서는 외부 LLM으로 전송하지 말고 local_sllm만 사용하라.
16. 모든 실패는 error code, node, message를 포함해 callback하라.
17. 테스트용 sample payload와 curl 명령을 README에 작성하라.

최종 목표는 Base44 UI에서 버튼을 누르면 n8n workflow가 실제 실행되고, 문서 인덱싱, RAG 답변, 웹 크롤링, 평가 가채점, 보고서 생성, WBS 자동 이슈 생성이 실제로 완료되는 운영 가능한 파이프라인이다.
```

---

# 20. 완료 기준

```text
[ ] n8n Docker 환경이 실행된다.
[ ] Qdrant가 실행된다.
[ ] MCP Gateway가 실행된다.
[ ] document-ingest workflow가 파일을 받아 vector 저장까지 수행한다.
[ ] rag-chat workflow가 citations 포함 답변을 반환한다.
[ ] web-crawl workflow가 URL 본문과 첨부 링크를 수집한다.
[ ] evaluation workflow가 구조화된 점수 JSON을 반환한다.
[ ] report-generate workflow가 보고서 초안을 반환한다.
[ ] wbs-delay-check workflow가 auto_wbs issue 후보를 반환한다.
[ ] llm-route workflow가 local/external/fallback 정책을 따른다.
[ ] 모든 workflow가 Base44 callback을 호출한다.
[ ] 실패 시 Base44에 failed status와 error가 전달된다.
[ ] sample curl 테스트가 모두 통과한다.
```
