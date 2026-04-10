# 시스템 아키텍처 다이어그램

N8N-Ollama 플랫폼의 전체 동작 원리를 한눈에 볼 수 있는 다이어그램 모음입니다.

---

## 다이어그램 1: 전체 시스템 구성

4개 Docker 서비스가 하나의 네트워크에서 동작하는 구성입니다.

```mermaid
graph TB
    Client["🖥️ 클라이언트<br/>(curl / 웹 앱)"]

    subgraph DockerNet["🐳 Docker Network: ollama-network"]
        subgraph N8N_Block["⚙️ N8N 워크플로우 엔진 :5678"]
            WF1["📝 워크플로우 1<br/>메인 AI 어시스턴트"]
            WF2["🔀 워크플로우 2<br/>멀티 모델 라우터"]
            WF4["💬 워크플로우 4<br/>감정 분석 응답"]
        end

        subgraph Ollama_Block["🤖 Ollama LLM 서버 :11434"]
            M1["exaone3.5:2.4b<br/>한국어 특화 모델<br/>(LG AI Research)"]
        end

        Redis["⚡ Redis :6379<br/>대화 기록 캐시<br/>TTL: 24시간"]
        Postgres["🗄️ PostgreSQL :5432<br/>대화·분석 로그<br/>영구 저장"]
    end

    Client -->|"POST /webhook/*<br/>+ X-API-Key 헤더"| N8N_Block
    WF1 <-->|"대화 기록 조회/저장"| Redis
    WF1 -->|"conversation_logs"| Postgres
    WF2 -->|"router_logs"| Postgres
    WF4 -->|"sentiment_logs"| Postgres
    WF1 & WF2 & WF4 -->|"HTTP POST /api/chat"| M1
    N8N_Block -->|"JSON 응답"| Client
```

---

## 다이어그램 2: 메인 AI 어시스턴트 시퀀스

Redis 대화 기록을 활용한 멀티턴 대화 흐름입니다.

```mermaid
sequenceDiagram
    participant C as 🖥️ 클라이언트
    participant N as ⚙️ N8N
    participant R as ⚡ Redis
    participant O as 🤖 Ollama
    participant P as 🗄️ PostgreSQL

    C->>N: POST /webhook/ai-assistant<br/>{ message, session_id }<br/>X-API-Key: ***

    Note over N: 1. API 키 인증<br/>2. 입력값 검증

    N->>R: GET conversation:{session_id}
    R-->>N: 이전 대화 기록 (JSON 배열)

    Note over N: 시스템 프롬프트 +<br/>대화 기록 + 새 메시지 조합

    N->>O: POST /api/chat<br/>{ model: exaone3.5:2.4b,<br/>  messages: [...] }
    Note over O: EXAONE 3.5 추론<br/>(수 초 소요)
    O-->>N: { message: { content: "AI 응답" } }

    Note over N: 대화 기록에 새 교환 추가

    par 병렬 저장
        N->>R: SET conversation:{session_id}<br/>TTL: 86400초
    and
        N->>P: INSERT INTO conversation_logs
    end

    N-->>C: HTTP 200<br/>{ success, data.message,<br/>  metadata.model,<br/>  metadata.responseTime }
```

---

## 다이어그램 3: 멀티 모델 라우터 흐름

메시지 복잡도를 자동 감지하여 적합한 응답 전략을 선택합니다.

```mermaid
flowchart TD
    A["📨 사용자 입력\nmessage + complexity_hint"] --> B

    B["🔍 복잡도 분석기\n키워드 + 길이 분석"]

    B --> C{complexity?}

    C -->|"simple\n단순 키워드 + 단어 ≤ 10"| D["⚡ 경량 응답\n빠른 처리\n낮은 리소스"]
    C -->|"medium\n중간 복잡도"| E["⚖️ 균형 응답\n속도·품질 균형"]
    C -->|"complex\n복잡 키워드\n단어 > 50 또는 글자 > 300"| F["🧠 심층 응답\n포괄적 분석"]

    D & E & F --> G["🤖 exaone3.5:2.4b\nOllama 추론"]

    G --> H["🗄️ PostgreSQL\nrouter_logs 저장\n(모델명 + 선택 이유 + 응답시간)"]

    H --> I["📤 응답 반환\n{ message, complexity,\n  selectionReason, responseTime }"]
```

---

## 다이어그램 4: 감정 분석 워크플로우

2단계 LLM 호출로 감정을 먼저 분석한 후, 맞춤 톤으로 응답합니다.

```mermaid
flowchart TD
    A["📨 사용자 메시지 입력"] --> B["🔑 API 키 인증 + 입력 검증"]

    B --> C["🤖 1단계: 감정 분석 LLM 호출\nexaone3.5:2.4b\nJSON 형식 응답 요청"]

    C --> D["📊 감정 파싱\n{ sentiment, confidence,\n  reason, emotions }"]

    D --> E{sentiment?}

    E -->|"positive\n자신감 ≥ 기준"| F["🎉 열정적 톤\n긍정 에너지 공감\n격려와 활기"]
    E -->|"negative\n자신감 ≥ 기준"| G["🤗 공감적 톤\n감정 인정\n판단 없는 지지"]
    E -->|"neutral\n또는 기준 미달"| H["📖 정보 제공 톤\n객관적·구조적\n사실 기반"]

    F & G & H --> I["🤖 2단계: 맞춤 응답 LLM 호출\n선택된 톤의 시스템 프롬프트 적용"]

    I --> J["🗄️ PostgreSQL\nsentiment_logs 저장"]

    J --> K["📤 최종 응답\n{ message, sentiment,\n  confidence, toneApplied }"]
```

---

## 다이어그램 5: 인증 및 에러 처리 흐름

모든 워크플로우 공통 보안 레이어입니다.

```mermaid
flowchart TD
    REQ["📨 HTTP 요청\nPOST /webhook/*"] --> AUTH

    AUTH{"🔑 X-API-Key\n헤더 확인"}

    AUTH -->|"키 불일치"| E401["❌ HTTP 401\nAUTH_FAILED"]
    AUTH -->|"키 일치"| VALIDATE

    VALIDATE{"📋 입력값 검증\nmessage 필드 존재?"}

    VALIDATE -->|"message 없음"| E400["❌ HTTP 400\nVALIDATION_ERROR"]
    VALIDATE -->|"message 4000자 초과"| E400
    VALIDATE -->|"정상"| PROCESS["✅ 워크플로우 처리 시작"]

    PROCESS --> OLLAMA{"🤖 Ollama 응답"}

    OLLAMA -->|"타임아웃"| E504["❌ HTTP 504\nGATEWAY_TIMEOUT"]
    OLLAMA -->|"모델 없음"| E503["❌ HTTP 503\nMODEL_NOT_FOUND"]
    OLLAMA -->|"성공"| SUCCESS["✅ HTTP 200\n정상 응답"]
```

---

## 다이어그램 6: Docker 서비스 의존성

```mermaid
graph LR
    subgraph "docker compose up -d"
        PG["🗄️ postgres\n:5432"]
        RD["⚡ redis\n:6379"]
        OL["🤖 ollama\n:11434"]
        N8["⚙️ n8n\n:5678"]
    end

    PG -->|"healthcheck 통과 후"| N8
    RD -->|"healthcheck 통과 후"| N8
    OL -->|"시작 후"| N8

    N8 -->|"볼륨: n8n_data"| V1["💾 n8n_data"]
    PG -->|"볼륨: postgres_data"| V2["💾 postgres_data"]
    RD -->|"볼륨: redis_data"| V3["💾 redis_data"]
    OL -->|"볼륨: ollama_data"| V4["💾 ollama_data\n(모델 파일 포함)"]
```

---

## API 요청/응답 요약

| 엔드포인트 | 필수 헤더 | 요청 바디 | 응답 특이사항 |
|-----------|----------|----------|--------------|
| `/webhook/ai-assistant` | `X-API-Key` | `message`, `session_id` | `historySize` 포함 |
| `/webhook/model-router` | `X-API-Key` | `message`, `complexity_hint` | `complexity`, `selectionReason` 포함 |
| `/webhook/sentiment-response` | `X-API-Key` | `message`, `session_id` | `sentiment`, `confidence`, `toneApplied` 포함 |
