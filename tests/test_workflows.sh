#!/usr/bin/env bash
# =============================================================
# 단위 테스트: 개별 워크플로우 엔드포인트 검증
# 빠른 smoke test용 (LLM 응답 대기 없음)
# =============================================================

set -uo pipefail

BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
API_KEY="${API_SECRET_KEY:-n8n-ollama-api-key-2024}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

assert_status() {
  local label="$1"
  local expected_code="$2"
  local url="$3"
  local payload="$4"
  local extra_headers="${5:-}"

  local actual
  actual=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    ${extra_headers:+-H "$extra_headers"} \
    "$url" \
    -d "$payload")

  if [[ "$actual" == "$expected_code" ]]; then
    echo -e "${GREEN}[PASS]${NC} $label (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAIL]${NC} $label (기대: HTTP $expected_code, 실제: HTTP $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "\n${YELLOW}=== N8N-Ollama 단위 테스트 ===${NC}\n"

# N8N 헬스체크
echo "--- N8N 서비스 확인 ---"
if curl -sf --max-time 5 "${BASE_URL}/healthz" &>/dev/null; then
  echo -e "${GREEN}[OK]${NC} N8N 서비스 실행 중"
else
  echo -e "${RED}[FAIL]${NC} N8N 서비스 응답 없음"
  exit 1
fi

echo ""
echo "--- 인증 테스트 ---"

# 잘못된 API 키 → 401
assert_status "AI 어시스턴트 - 잘못된 API 키 거부" \
  "401" \
  "${BASE_URL}/webhook/ai-assistant" \
  '{"message":"test"}' \
  "X-API-Key: wrong-key-12345"

assert_status "모델 라우터 - 잘못된 API 키 거부" \
  "401" \
  "${BASE_URL}/webhook/model-router" \
  '{"message":"test"}' \
  "X-API-Key: wrong-key-12345"

assert_status "감정 분석 - 잘못된 API 키 거부" \
  "401" \
  "${BASE_URL}/webhook/sentiment-response" \
  '{"message":"test"}' \
  "X-API-Key: wrong-key-12345"

echo ""
echo "--- 입력 검증 테스트 ---"

# 빈 메시지 → 400
assert_status "AI 어시스턴트 - 빈 메시지 거부" \
  "400" \
  "${BASE_URL}/webhook/ai-assistant" \
  '{"message":""}' \
  "X-API-Key: ${API_KEY}"

assert_status "감정 분석 - 빈 메시지 거부" \
  "400" \
  "${BASE_URL}/webhook/sentiment-response" \
  '{"message":""}' \
  "X-API-Key: ${API_KEY}"

echo ""
echo "--- 결과 요약 ---"
echo -e "통과: ${GREEN}${PASS}${NC}  실패: ${RED}${FAIL}${NC}"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
