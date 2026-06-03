# 다시 시작 가이드 (RESUME / RUNBOOK)

> PC 재부팅·세션 종료 후 이 파이프라인 작업을 **문제 없이 재개**하기 위한 절차.
> 최초 구축: 2026-06-02 · 최종 갱신: 2026-06-03

---

## 0. 핵심 사실 (먼저 알아둘 것)

| 항목 | 값 |
|------|----|
| 작업 폴더 | `C:\Users\User\works\base44\n8n-pipeline` |
| GitHub 백업 | https://github.com/bkimkr0139-blip/govtask (branch `main`) |
| n8n | 로컬 **native** 프로세스, `http://localhost:5678`, v2.56.0 (Docker 아님) |
| 워크플로우 | `[BC44·파이프라인] 01~10`, 전부 **active**, n8n DB에 영구 저장(재시작해도 유지) |
| 동작 모드 | **mock** (`PIPELINE_MODE=mock`) — 외부 Qdrant/LLM/MCP Gateway 미가동 |
| 웹훅 토큰 | native n8n에 `N8N_WEBHOOK_TOKEN` 미설정 → 워크플로우가 **`dev-local-token`** 으로 폴백 |
| 콜백 토큰 | `dev-callback-token` |
| 워크플로우 ID | `docs/workflow_registry.md` 참조 |

---

## 1. Claude Code 세션 재시작 시

- **반드시 `C:\Users\User\works\base44` 디렉터리에서 세션을 시작**해야 `n8n-mcp` 도구가 로드된다.
  - 다른 디렉터리에서 시작하면 n8n MCP 도구(`n8n_*`)가 안 보일 수 있다.
- 연결 확인:  MCP `n8n_health_check` → `connected: true` / version 2.56.0 이면 정상.
- n8n API 키는 `~/.claude.json` 의 `mcpServers.n8n-mcp.env.N8N_API_KEY` 에 있음 (이 repo에 **절대 커밋 금지**).

## 2. n8n 본체 확인 (PC 재부팅했다면)

```powershell
# n8n이 떠 있는지
curl http://localhost:5678/webhook/health        # => {"status":"ok",...}
```
- 응답이 없으면 native n8n을 먼저 기동한다(설치 방식대로: `n8n start` 또는 등록된 서비스/시작프로그램).
- 워크플로우는 n8n DB에 저장돼 있으므로 **재생성 불필요**. 안 보이면 §5의 import로 복구.

## 3. mock 콜백 서버 (Base44 미완 상태 테스트용)

```powershell
node C:\Users\User\works\base44\n8n-pipeline\mock\mock_callback_server.cjs   # 포트 4000
```
- ⚠️ 확장자는 반드시 **`.cjs`** (상위 `C:\Users\User\package.json` 의 `"type":"module"` 때문에 `.js`는 ESM 오류).

## 4. 동작 검증 (스모크 → end-to-end)

```powershell
cd C:\Users\User\works\base44\n8n-pipeline
powershell -File scripts\test_all.ps1        # 전체 워크플로우 호출
powershell -File scripts\callback_test.ps1   # mock 콜백 end-to-end (mock 서버 먼저 기동)
# bash 환경:  bash scripts/curl_samples.sh
```

## 5. 워크플로우 복구/재배포 (필요 시)

- **export** (n8n → 파일):
  ```powershell
  $env:N8N_API_URL="http://127.0.0.1:5678"; $env:N8N_API_KEY="<~/.claude.json 의 키>"
  powershell -File scripts\export_workflows.ps1
  ```
- **import** (파일 → n8n): n8n UI → *Import from File* 로 `workflows\*.json` 임포트, 또는
  Claude Code에서 MCP `n8n_create_workflow` 로 재생성(공통 구조는 `docs/workflow_registry.md`).

## 6. 외부 공개 (Base44에서 호출 가능하게)

```powershell
cloudflared tunnel --url http://localhost:5678
# => 출력된 https://<...>.trycloudflare.com 를 Base44에 N8N_BASE_URL 로 등록
```
- 임시 터널 URL은 재시작마다 바뀜 → 그때마다 Base44 설정 갱신. 상세: `docs/local_proxy_setup.md`.

## 7. GitHub 백업 갱신

```powershell
cd C:\Users\User\works\base44\n8n-pipeline
git add -A
git commit -m "변경 내용 요약"
git push                     # origin main (Git Credential Manager 자격증명 사용)
```

---

## 8. 미완료 / 다음 작업 (TODO)

- [ ] **mock → live 전환**: `.env` `PIPELINE_MODE=live` + `QDRANT_URL`/`MCP_GATEWAY_URL`/`LOCAL_SLLM_BASE_URL` 설정 후,
      각 워크플로우 Code 노드의 `if (PIPELINE_MODE==='live')` 분기를 실제 HTTP/MCP 호출로 교체.
- [ ] **운영 토큰**: native n8n 환경에 강한 `N8N_WEBHOOK_TOKEN` 설정·재시작 → Base44와 공유(현재 dev 폴백).
- [ ] **MCP Gateway 구현**: `services/mcp-gateway/server.cjs` 스텁(현재 501) → 실제 도구 구현.
- [ ] **Qdrant/Ollama 기동**: docker-compose `--profile full` 또는 개별 기동.
- [ ] **Base44 callback receiver**: `/api/workflow-callback` 구현(또는 mock 계속 사용).
- [ ] **고정 도메인**: cloudflared named tunnel 또는 ngrok reserved domain(임시 URL 변동 해소).

## 9. 자주 막히는 지점

- PowerShell 5.1은 UTF-8(BOM 없는) `.ps1`의 한글 주석을 깨뜨린다 → 스크립트 주석은 ASCII 유지.
- `.js` 파일이 ESM으로 처리됨(상위 package.json) → Node 단독 실행 스크립트는 `.cjs` 사용.
- 워크플로우가 `inactive`면 webhook 호출 불가 → MCP `n8n_update_partial_workflow` `[{type:"activateWorkflow"}]` 또는 UI에서 활성화.
- `responseNode` 모드 webhook은 에러 시에도 응답하도록 노드에 `onError:"continueRegularOutput"` 필요(이미 적용됨).
