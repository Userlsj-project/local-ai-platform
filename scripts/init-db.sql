-- =============================================================
-- PostgreSQL 초기화 스크립트
-- N8N-Ollama 플랫폼에서 사용할 테이블 생성
-- =============================================================

-- 대화 기록 테이블
CREATE TABLE IF NOT EXISTS conversation_logs (
    id              BIGSERIAL PRIMARY KEY,
    session_id      VARCHAR(255) NOT NULL,
    user_message    TEXT NOT NULL,
    ai_response     TEXT NOT NULL,
    model_used      VARCHAR(100) NOT NULL DEFAULT 'llama3.2',
    response_time   INTEGER,                    -- 응답 시간 (밀리초)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 빠른 세션 검색을 위한 인덱스
CREATE INDEX IF NOT EXISTS idx_conv_logs_session ON conversation_logs(session_id);
CREATE INDEX IF NOT EXISTS idx_conv_logs_created ON conversation_logs(created_at DESC);

-- 감정 분석 결과 테이블
CREATE TABLE IF NOT EXISTS sentiment_logs (
    id              BIGSERIAL PRIMARY KEY,
    session_id      VARCHAR(255),
    user_message    TEXT NOT NULL,
    sentiment       VARCHAR(50) NOT NULL,       -- positive / negative / neutral
    confidence      NUMERIC(4,3),               -- 0.000 ~ 1.000
    tone_used       VARCHAR(100),               -- 사용된 응답 톤
    ai_response     TEXT,
    model_used      VARCHAR(100) DEFAULT 'llama3.2',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sentiment_logs_sentiment ON sentiment_logs(sentiment);
CREATE INDEX IF NOT EXISTS idx_sentiment_logs_created  ON sentiment_logs(created_at DESC);

-- 라우터 결정 기록 테이블
CREATE TABLE IF NOT EXISTS router_logs (
    id              BIGSERIAL PRIMARY KEY,
    session_id      VARCHAR(255),
    user_message    TEXT NOT NULL,
    complexity      VARCHAR(50) NOT NULL,       -- simple / medium / complex
    model_selected  VARCHAR(100) NOT NULL,
    selection_reason TEXT,
    ai_response     TEXT,
    response_time   INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_router_logs_complexity ON router_logs(complexity);
CREATE INDEX IF NOT EXISTS idx_router_logs_created    ON router_logs(created_at DESC);

-- 통계 뷰: 모델별 평균 응답 시간
CREATE OR REPLACE VIEW model_performance_stats AS
SELECT
    model_used,
    COUNT(*)                            AS total_requests,
    ROUND(AVG(response_time))           AS avg_response_ms,
    MIN(response_time)                  AS min_response_ms,
    MAX(response_time)                  AS max_response_ms,
    DATE_TRUNC('day', created_at)       AS stat_date
FROM conversation_logs
WHERE response_time IS NOT NULL
GROUP BY model_used, DATE_TRUNC('day', created_at)
ORDER BY stat_date DESC, model_used;

-- 통계 뷰: 감정 분포
CREATE OR REPLACE VIEW sentiment_distribution AS
SELECT
    sentiment,
    COUNT(*)                            AS count,
    ROUND(AVG(confidence) * 100, 1)    AS avg_confidence_pct,
    DATE_TRUNC('day', created_at)       AS stat_date
FROM sentiment_logs
GROUP BY sentiment, DATE_TRUNC('day', created_at)
ORDER BY stat_date DESC, sentiment;
