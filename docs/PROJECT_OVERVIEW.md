# 🤖 Local AI Platform — 프로젝트 설명서

> N8N 워크플로우 자동화 + Ollama 로컬 LLM + Docker 통합 플랫폼

---

## 1. 프로젝트 개요

본 프로젝트는 **오픈소스만으로 구성된 완전한 로컬 AI 자동화 플랫폼**입니다.  
외부 AI API(OpenAI 등) 없이 로컬에서 LLM을 실행하며, N8N 워크플로우로 AI 로직을 자동화합니다.

### 핵심 구성 요소

| 구성 요소 | 기술 스택 | 역할 |
|----------|-----------|------|
| 워크플로우 엔진 | N8N | API 요청 수신, 로직 처리, 응답 반환 |
| LLM 추론 서버 | Ollama + llama3.2 | 자연어 처리 및 응답 생성 |
| 세션 캐시 | Redis | 대화 기록 임시 저장 (TTL 24h) |
| 영구 저장소 | PostgreSQL | 대화 로그, 감정 분석 결과 저장 |
| 컨테이너 | Docker Compose | 전체 스택 단일 명령 실행 |
| 데모 UI | HTML/JS | 브라우저 기반 시각화 인터페이스 |

### 제공 워크플로우 3종

```
┌─────────────────────────────────────────────────────────┐
│  워크플로우 1  │  메인 AI 어시스턴트   │ /webhook/ai-assistant      │
│  워크플로우 2  │  멀티 모델 라우터     │ /webhook/model-router      │
│  워크플로우 4  │  감정 분석 및 맞춤 응답│ /webhook/sentiment-response│
└─────────────────────────────────────────────────────────┘
```

---

## 2. 전체 시스템 아키텍처

```mermaid
graph TB
    Client(["👤 클라이언트<br/>(브라우저 / curl)"])

    subgraph Docker["🐳 Docker Network: ollama-network"]
        direction TB

        subgraph N8N_SVC["⚙️ N8N 워크플로우 엔진  :5678"]
            WF1["📌 워크플로우 1<br/>메인 AI 어시스턴트"]
            WF2["📌 워크플로우 2<br/>멀티 모델 라우터"]
            WF4["📌 워크플로우 4<br/>감정 분석 응답"]
        end

        subgraph Ollama_SVC["🧠 Ollama LLM 서버  :11434"]
            M1["llama3.2:1b<br/>경량 모델"]
            M2["llama3.2<br/>기본 모델"]
            M3["llama3.2:latest<br/>고급 모델"]
        end

        Redis[("🗄️ Redis  :6379<br/>대화 기록 캐시<br/>TTL: 24h")]
        Postgres[("🗃️ PostgreSQL  :5432<br/>영구 로그 저장")]
    end

    Client -->|"POST + X-API-Key"| N8N_SVC

    WF1 <-->|"세션 기록 조회/저장"| Redis
    WF1 -->|"대화 로그"| Postgres
    WF2 -->|"라우터 로그"| Postgres
    WF4 -->|"감정 분석 로그"| Postgres

    WF1 -->|"llama3.2"| M2
    WF2 -->|"simple"| M1
    WF2 -->|"medium"| M2
    WF2 -->|"complex"| M3
    WF4 -->|"감정분석 + 응답생성"| M2

    N8N_SVC -->|"JSON 응답"| Client

    style Docker fill:#0f0f2a,stroke:#6366f1,color:#e2e8f0
    style N8N_SVC fill:#1a1a3e,stroke:#6366f1,color:#e2e8f0
    style Ollama_SVC fill:#1a2e1a,stroke:#22c55e,color:#e2e8f0
```

---

## 3. 워크플로우 1 — 메인 AI 어시스턴트

### 설명

사용자 메시지를 받아 Redis에서 이전 대화 기록을 불러오고,  
Ollama(llama3.2)로 컨텍스트 인식 응답을 생성한 뒤 기록을 업데이트합니다.  
모든 대화는 PostgreSQL에 영구 저장됩니다.

### 처리 흐름 (시퀀스 다이어그램)

```mermaid
sequenceDiagram
    actor C as 👤 클라이언트
    participant N as ⚙️ N8N
    participant R as 🗄️ Redis
    participant O as 🧠 Ollama
    participant P as 🗃️ PostgreSQL

    C->>N: POST /webhook/ai-assistant<br/>{ message, session_id }<br/>헤더: X-API-Key

    rect rgb(30, 30, 60)
        Note over N: 🔐 API 키 인증 검증
        Note over N: ✅ 입력값 유효성 검사
    end

    N->>R: GET conversation:{session_id}
    R-->>N: 이전 대화 기록 배열

    rect rgb(20, 40, 20)
        Note over N: 📝 시스템 프롬프트 + 기록 + 새 메시지 조합
    end

    N->>O: POST /api/chat<br/>{ model: llama3.2, messages: [...] }
    Note over O: ⏳ LLM 추론 처리
    O-->>N: { message: { content: "AI 응답" } }

    par 병렬 저장
        N->>R: SET conversation:{session_id}<br/>(TTL: 86400초)
    and
        N->>P: INSERT INTO conversation_logs
    end

    N-->>C: HTTP 200<br/>{ success, data.message,<br/>metadata.model, metadata.responseTime }
```

### 블록 다이어그램

```mermaid
flowchart LR
    A([📥 웹훅 수신]) --> B[🔐 API 키 인증]
    B -->|실패| Z1([❌ 401 오류 반환])
    B -->|성공| C[📖 Redis 기록 조회]
    C --> D[📝 프롬프트 구성\n시스템+기록+질문]
    D --> E[🧠 Ollama llama3.2 요청]
    E --> F{응답 성공?}
    F -->|실패| Z2([❌ 503 오류 반환])
    F -->|성공| G[🔄 대화 기록 업데이트]
    G --> H[(💾 Redis 저장\nTTL 24h)]
    G --> I[(🗃️ PostgreSQL 로그)]
    H --> J([✅ JSON 응답 반환])
    I --> J
```

---

## 4. 워크플로우 2 — 멀티 모델 라우터

### 설명

메시지의 복잡도를 자동으로 분석하여 가장 적합한 LLM 모델로 라우팅합니다.  
키워드와 텍스트 길이를 기반으로 Simple / Medium / Complex를 판별합니다.

### 복잡도 분류 기준

| 등급 | 조건 | 할당 모델 | 특징 |
|------|------|----------|------|
| ⚡ Simple | 단순 키워드 포함 AND 단어 수 ≤ 10 | llama3.2:1b | 빠른 응답, 낮은 메모리 |
| ⚖️ Medium | Simple/Complex 기준 미해당 | llama3.2 | 균형 잡힌 성능 |
| 🧠 Complex | 복잡 키워드 OR 단어 수 > 50 OR 글자 수 > 300 | llama3.2:latest | 심층 분석, 포괄적 응답 |

### 라우팅 블록 다이어그램

```mermaid
flowchart TD
    A([📥 메시지 수신\nmessage + complexity_hint]) --> B[🔐 API 키 인증]
    B -->|실패| E1([❌ 401 반환])
    B -->|성공| C{complexity_hint?}

    C -->|사용자 지정\nsimple/medium/complex| D[지정 복잡도 사용]
    C -->|auto| F[🔍 자동 분석\n키워드 + 길이 검사]

    F --> G{복잡도 판별}
    D --> G

    G -->|⚡ Simple\n단순 키워드, 단어≤10| H["llama3.2:1b\n경량 모델\ntemp: 0.5 / max_token: 256"]
    G -->|⚖️ Medium\n중간 복잡도| I["llama3.2\n기본 모델\ntemp: 0.7 / max_token: 512"]
    G -->|🧠 Complex\n복잡 키워드/길이초과| J["llama3.2:latest\n고급 모델\ntemp: 0.8 / max_token: 1024"]

    H --> K[📊 선택 이유 기록]
    I --> K
    J --> K

    K --> L[(🗃️ PostgreSQL\nrouter_logs 저장)]
    L --> M([✅ 응답 반환\n모델명 + 복잡도 + 이유 포함])
```

---

## 5. 워크플로우 4 — 감정 분석 및 맞춤 응답

### 설명

사용자 메시지의 감정을 먼저 분석(1차 LLM 호출)한 뒤,  
감정에 맞는 톤의 시스템 프롬프트를 적용하여 최종 응답을 생성(2차 LLM 호출)합니다.

### 감정별 응답 전략

| 감정 | 이모지 | 톤 | 특징 |
|------|--------|-----|------|
| positive | 😊 | 열정적 톤 | 긍정 에너지 공감, 격려, 활기찬 표현 |
| negative | 😢 | 공감적 톤 | 감정 인정, 판단 없는 따뜻한 지지 |
| neutral | 😐 | 정보 제공 톤 | 객관적, 구조적, 사실 기반 |

### 2단계 처리 블록 다이어그램

```mermaid
flowchart TD
    A([📥 메시지 수신]) --> B[🔐 API 키 인증]
    B -->|실패| E1([❌ 401 반환])
    B -->|성공| C

    subgraph STEP1["🔍 1단계: 감정 분석"]
        C["Ollama llama3.2 호출\n감정 분석 전용 프롬프트\nJSON 형식 응답 요청"] --> D["JSON 파싱\n{ sentiment, confidence, reason, emotions }"]
    end

    D --> E{감정 판별}

    E -->|positive 😊\n신뢰도 반영| F["열정적 톤 선택\n긍정 에너지 공감\n격려하는 방식"]
    E -->|negative 😢\n신뢰도 반영| G["공감적 톤 선택\n감정 먼저 인정\n따뜻한 지지"]
    E -->|neutral 😐\n신뢰도 반영| H["정보 제공 톤 선택\n객관적 구조적\n사실 기반"]

    subgraph STEP2["💬 2단계: 맞춤 응답 생성"]
        F --> I["Ollama llama3.2 호출\n선택된 톤을 system 프롬프트로 적용"]
        G --> I
        H --> I
    end

    I --> J[(🗃️ PostgreSQL\nsentiment_logs 저장)]
    J --> K([✅ 응답 반환\n감정결과 + 신뢰도 + 감지감정 + AI응답])

    style STEP1 fill:#1a1a3e,stroke:#6366f1,color:#e2e8f0
    style STEP2 fill:#1a2e1a,stroke:#22c55e,color:#e2e8f0
```

---

## 6. 데이터베이스 스키마

```mermaid
erDiagram
    conversation_logs {
        bigserial id PK
        varchar session_id
        text user_message
        text ai_response
        varchar model_used
        integer response_time
        timestamptz created_at
    }

    sentiment_logs {
        bigserial id PK
        varchar session_id
        text user_message
        varchar sentiment
        numeric confidence
        varchar tone_used
        text ai_response
        varchar model_used
        timestamptz created_at
    }

    router_logs {
        bigserial id PK
        varchar session_id
        text user_message
        varchar complexity
        varchar model_selected
        text selection_reason
        text ai_response
        integer response_time
        timestamptz created_at
    }
```

---

## 7. Git 커밋 이력

```mermaid
gitGraph
   commit id: "init: 프로젝트 초기화"

   branch feature/docker
   checkout feature/docker
   commit id: "feat: Docker Compose 설정 추가"

   checkout main
   merge feature/docker

   branch feature/workflows
   checkout feature/workflows
   commit id: "feat: 메인 AI 어시스턴트 구현"
   commit id: "feat: 멀티 모델 라우터 구현"
   commit id: "feat: 감정 분석 워크플로우 구현"

   checkout main
   merge feature/workflows

   commit id: "docs: README 및 아키텍처 문서 작성"
   commit id: "test: 테스트 스크립트 추가"
```

---

## 8. 실행 방법

### 전체 스택 시작

```bash
git clone https://github.com/Userlsj-project/local-ai-platform.git
cd local-ai-platform

# 환경 변수 설정
cp .env.example .env  # 값 수정 후 저장

# Docker 서비스 시작
docker compose up -d

# Ollama 모델 다운로드
docker exec n8n_ollama ollama pull llama3.2
docker exec n8n_ollama ollama pull llama3.2:1b
```

### API 호출 예시

```bash
# 워크플로우 1: 메인 AI 어시스턴트
curl -X POST http://localhost:5678/webhook/ai-assistant \
  -H "Content-Type: application/json" \
  -H "X-API-Key: n8n-ollama-api-key-2024" \
  -d '{"message": "안녕하세요!", "session_id": "my_session"}'

# 워크플로우 2: 멀티 모델 라우터
curl -X POST http://localhost:5678/webhook/model-router \
  -H "Content-Type: application/json" \
  -H "X-API-Key: n8n-ollama-api-key-2024" \
  -d '{"message": "도커란 무엇인가요?", "complexity_hint": "auto"}'

# 워크플로우 4: 감정 분석
curl -X POST http://localhost:5678/webhook/sentiment-response \
  -H "Content-Type: application/json" \
  -H "X-API-Key: n8n-ollama-api-key-2024" \
  -d '{"message": "오늘 발표가 잘 됐어요! 정말 기뻐요!"}'
```

### 웹 데모 실행

```bash
cd docs
python3 -m http.server 8080
# 브라우저에서 http://localhost:8080/demo.html 접속
```

---

## 9. 보안 구조

```mermaid
flowchart LR
    Client -->|"모든 요청"| Guard

    subgraph Guard["🔐 인증 레이어"]
        direction TB
        H["X-API-Key 헤더 검사"]
        H -->|"불일치"| R401["HTTP 401\nUNAUTHORIZED"]
        H -->|"일치"| PASS["✅ 통과"]
    end

    PASS --> WF["워크플로우 처리"]

    subgraph Network["🐳 Docker 내부 네트워크"]
        WF --> Ollama["Ollama\n외부 미노출"]
        WF --> Redis["Redis\n비밀번호 인증"]
        WF --> PG["PostgreSQL\n전용 계정"]
    end
```

| 보안 항목 | 적용 방법 |
|----------|-----------|
| API 인증 | 모든 웹훅에 `X-API-Key` 헤더 필수 |
| 네트워크 격리 | Docker 브리지 네트워크로 내부 서비스 격리 |
| 민감 정보 | `.env` 파일 분리, `.gitignore`로 Git 제외 |
| Redis 보안 | `requirepass` 설정 |
| PostgreSQL | 전용 사용자/비밀번호, 일반 계정 미사용 |

---

*N8N-Ollama Local AI Platform — 오픈소스 기반 로컬 AI 자동화 솔루션*
