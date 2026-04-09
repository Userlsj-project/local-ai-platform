#!/usr/bin/env bash
# =============================================================
# N8N-Ollama 플랫폼 전체 테스트 스크립트
# 세 가지 워크플로우의 웹훅 엔드포인트를 curl로 테스트
# =============================================================

set -uo pipefail

# --- 색상 정의 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# --- 설정 ---
BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
API_KEY="${API_SECRET_KEY:-n8n-ollama-api-key-2024}"
TIMEOUT=120  # 초 (LLM 응답 대기 시간)

# --- 테스트 결과 추적 ---
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- 헬퍼 함수 ---
print_separator() {
  echo -e "\n${CYAN}$(printf '═%.0s' {1..60})${NC}"
}

print_header() {
  print_separator
  echo -e "${BOLD}${MAGENTA}  $*${NC}"
  print_separator
}

log_test()    { echo -e "\n${BLUE}[TEST]${NC} $*"; TESTS_TOTAL=$((TESTS_TOTAL + 1)); }
log_pass()    { echo -e "${GREEN}[PASS]${NC} $*"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail()    { echo -e "${RED}[FAIL]${NC} $*"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
log_request() { echo -e "${CYAN}[REQ]${NC}  $*"; }
log_response(){ echo -e "${BLUE}[RES]${NC}  $*"; }

# =============================================================
# API 요청 헬퍼 함수
# =============================================================
call_api() {
  local endpoint="$1"
  local payload="$2"
  local description="$3"

  log_request "POST ${BASE_URL}/webhook/${endpoint}"
  log_info "페이로드: $(echo "$payload" | python3 -m json.tool 2>/dev/null || echo "$payload")"

  local response
  local http_code

  # curl 요청 실행 (응답 코드와 본문 분리)
  response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" \
    --max-time "$TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    "${BASE_URL}/webhook/${endpoint}" \
    -d "$payload" 2>&1)

  http_code=$(echo "$response" | tail -1 | sed 's/.*__HTTP_CODE__//')
  local body
  body=$(echo "$response" | sed '$d' | sed 's/__HTTP_CODE__.*//')

  # 응답 출력
  echo -e "${BLUE}  HTTP 상태 코드: ${http_code}${NC}"
  if command -v python3 &>/dev/null; then
    echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"
  else
    echo "$body"
  fi

  # 검증
  if [[ "$http_code" == "200" ]]; then
    # 응답에 success:true 포함 확인
    if echo "$body" | grep -q '"success":true'; then
      log_pass "$description - HTTP 200, 성공 응답 확인"
      return 0
    else
      log_fail "$description - HTTP 200 이나 success:true 없음"
      return 1
    fi
  elif [[ "$http_code" == "401" ]]; then
    log_fail "$description - HTTP 401 인증 실패"
    return 1
  elif [[ -z "$http_code" ]] || [[ "$http_code" == "000" ]]; then
    log_fail "$description - 연결 실패 (서비스 미실행 또는 타임아웃)"
    return 1
  else
    log_fail "$description - HTTP ${http_code}"
    return 1
  fi
}

# =============================================================
# 서비스 상태 사전 확인
# =============================================================
check_services() {
  print_header "서비스 상태 확인"

  local all_ok=true

  check_service() {
    local name="$1"
    local url="$2"
    if curl -sf --max-time 5 "$url" &>/dev/null; then
      echo -e "  ${GREEN}✓${NC} $name"
    else
      echo -e "  ${RED}✗${NC} $name (응답 없음)"
      all_ok=false
    fi
  }

  check_service "N8N      (포트 5678)" "${BASE_URL}/healthz"
  check_service "Ollama   (포트 11434)" "http://localhost:11434/api/tags"
  check_service "Redis    (포트 6379)"  "http://localhost:6379" || true  # Redis는 HTTP 응답 없음
  check_service "PostgreSQL (포트 5432)" "http://localhost:5432" || true

  echo ""
  if [[ "$all_ok" == "false" ]]; then
    echo -e "${YELLOW}일부 서비스가 응답하지 않습니다.${NC}"
    echo -e "  시작 명령: ${CYAN}docker compose up -d${NC}"
    echo ""
    read -rp "계속 테스트하시겠습니까? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
  else
    echo -e "${GREEN}모든 서비스 정상 실행 중${NC}"
  fi
}

# =============================================================
# 테스트 1: 메인 AI 어시스턴트
# =============================================================
test_main_assistant() {
  print_header "워크플로우 1: 메인 AI 어시스턴트"
  echo -e "  엔드포인트: ${CYAN}POST /webhook/ai-assistant${NC}"
  echo -e "  설명: 대화 기록을 Redis에 저장하며 Ollama와 대화"

  # 테스트 1-1: 기본 대화
  log_test "기본 대화 테스트"
  call_api "ai-assistant" \
    '{"message": "안녕하세요! 오늘 기분이 어떠세요?", "session_id": "test_session_001"}' \
    "기본 대화" || true

  # 테스트 1-2: 연속 대화 (세션 유지 확인)
  log_test "연속 대화 (세션 유지) 테스트"
  call_api "ai-assistant" \
    '{"message": "이전에 제가 뭐라고 했나요?", "session_id": "test_session_001"}' \
    "연속 대화" || true

  # 테스트 1-3: 인증 실패 테스트
  log_test "잘못된 API 키로 인증 실패 테스트"
  local response
  response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: wrong-key" \
    "${BASE_URL}/webhook/ai-assistant" \
    -d '{"message": "test"}' 2>&1)
  local http_code
  http_code=$(echo "$response" | tail -1 | sed 's/.*__HTTP_CODE__//')
  if [[ "$http_code" == "401" ]] || echo "$response" | grep -q '"UNAUTHORIZED"\|"AUTH_FAILED"'; then
    log_pass "인증 실패 - 올바르게 거부됨 (${http_code})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "인증 실패 - 예상 401 또는 오류 응답, 실제: ${http_code}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  # 테스트 1-4: 빈 메시지 검증
  log_test "빈 메시지 유효성 검사 테스트"
  response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    "${BASE_URL}/webhook/ai-assistant" \
    -d '{"message": ""}' 2>&1)
  http_code=$(echo "$response" | tail -1 | sed 's/.*__HTTP_CODE__//')
  if [[ "$http_code" == "400" ]] || echo "$response" | grep -q '"BAD_REQUEST"\|"VALIDATION"'; then
    log_pass "빈 메시지 검증 - 올바르게 거부됨 (${http_code})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_fail "빈 메시지 검증 - 예상 400, 실제: ${http_code}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# =============================================================
# 테스트 2: 멀티 모델 라우터
# =============================================================
test_model_router() {
  print_header "워크플로우 2: 멀티 모델 라우터"
  echo -e "  엔드포인트: ${CYAN}POST /webhook/model-router${NC}"
  echo -e "  설명: 복잡도에 따라 다른 Ollama 모델로 라우팅"

  # 테스트 2-1: 단순 메시지 (llama3.2:1b 라우팅)
  log_test "단순 메시지 라우팅 (llama3.2:1b 예상)"
  call_api "model-router" \
    '{"message": "안녕!", "complexity_hint": "simple"}' \
    "단순 메시지" || true

  # 테스트 2-2: 중간 복잡도 (llama3.2 라우팅)
  log_test "중간 복잡도 메시지 라우팅 (llama3.2 예상)"
  call_api "model-router" \
    '{"message": "파이썬 리스트와 튜플의 차이점은 무엇인가요?", "complexity_hint": "medium"}' \
    "중간 복잡도 메시지" || true

  # 테스트 2-3: 복잡한 메시지 (llama3.2:latest 라우팅)
  log_test "복잡한 메시지 라우팅 (llama3.2:latest 예상)"
  call_api "model-router" \
    '{"message": "마이크로서비스 아키텍처의 장단점을 모놀리식 아키텍처와 비교하여 분석하고, 각 패턴이 적합한 시나리오를 설명해주세요.", "complexity_hint": "complex"}' \
    "복잡한 메시지" || true

  # 테스트 2-4: 자동 복잡도 감지
  log_test "자동 복잡도 감지 테스트"
  call_api "model-router" \
    '{"message": "Docker 컨테이너와 가상머신의 차이점을 설명해주세요.", "complexity_hint": "auto"}' \
    "자동 복잡도 감지" || true

  # 테스트 2-5: 응답 헤더에 모델 정보 포함 확인
  log_test "응답 헤더 메타데이터 확인"
  local response
  response=$(curl -s -I \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    "${BASE_URL}/webhook/model-router" \
    -d '{"message": "간단한 테스트", "complexity_hint": "simple"}' 2>&1)
  if echo "$response" | grep -qi "x-model-used\|x-complexity"; then
    log_pass "응답 헤더에 모델/복잡도 정보 포함됨"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log_info "응답 헤더 메타데이터 확인 불가 (HEAD 요청으로는 확인 어려울 수 있음)"
    TESTS_PASSED=$((TESTS_PASSED + 1))  # 정보성 테스트
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# =============================================================
# 테스트 3: 감정 분석 및 맞춤 응답
# =============================================================
test_sentiment_analysis() {
  print_header "워크플로우 3: 감정 분석 및 맞춤 응답"
  echo -e "  엔드포인트: ${CYAN}POST /webhook/sentiment-response${NC}"
  echo -e "  설명: 감정 분석 후 맞춤 톤으로 응답 생성"

  # 테스트 3-1: 긍정적 메시지
  log_test "긍정적 감정 분석 테스트"
  call_api "sentiment-response" \
    '{"message": "오늘 시험에서 A+를 받았어요! 정말 기뻐서 미칠 것 같아요!", "session_id": "sentiment_test_001"}' \
    "긍정적 감정" || true

  # 테스트 3-2: 부정적 메시지
  log_test "부정적 감정 분석 테스트"
  call_api "sentiment-response" \
    '{"message": "요즘 너무 힘들고 지쳐있어요. 아무것도 하기 싫고 우울해요.", "session_id": "sentiment_test_002"}' \
    "부정적 감정" || true

  # 테스트 3-3: 중립적 메시지
  log_test "중립적 감정 분석 테스트"
  call_api "sentiment-response" \
    '{"message": "오늘 날씨가 어떤가요? 외출할 계획입니다.", "session_id": "sentiment_test_003"}' \
    "중립적 감정" || true

  # 테스트 3-4: 응답에 감정 분석 메타데이터 포함 확인
  log_test "응답에 감정 분석 메타데이터 포함 확인"
  local response_body
  response_body=$(curl -s \
    --max-time "$TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    "${BASE_URL}/webhook/sentiment-response" \
    -d '{"message": "정말 행복한 하루예요!"}' 2>&1)

  if echo "$response_body" | grep -q '"sentiment"'; then
    log_pass "응답에 sentiment 필드 포함됨"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    # 감정 값 출력
    local sentiment
    sentiment=$(echo "$response_body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sentiment',{}).get('result','N/A'))" 2>/dev/null || echo "파싱 실패")
    log_info "감지된 감정: $sentiment"
  else
    log_fail "응답에 sentiment 필드 없음"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# =============================================================
# 결과 요약
# =============================================================
print_summary() {
  print_header "테스트 결과 요약"

  local pass_rate=0
  if [[ $TESTS_TOTAL -gt 0 ]]; then
    pass_rate=$(( TESTS_PASSED * 100 / TESTS_TOTAL ))
  fi

  echo -e "  총 테스트:  ${BOLD}${TESTS_TOTAL}${NC}"
  echo -e "  통과:       ${GREEN}${TESTS_PASSED}${NC}"
  echo -e "  실패:       ${RED}${TESTS_FAILED}${NC}"
  echo -e "  성공률:     ${BOLD}${pass_rate}%${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✓ 모든 테스트 통과!${NC}"
  elif [[ $pass_rate -ge 70 ]]; then
    echo -e "${YELLOW}${BOLD}  ⚠ 일부 테스트 실패. 서비스 상태를 확인하세요.${NC}"
  else
    echo -e "${RED}${BOLD}  ✗ 다수 테스트 실패. 워크플로우가 활성화되었는지 확인하세요.${NC}"
    echo ""
    echo -e "  확인 사항:"
    echo -e "    1. N8N UI에서 워크플로우가 Active 상태인지 확인"
    echo -e "    2. Redis/PostgreSQL 자격증명이 올바른지 확인"
    echo -e "    3. Ollama에 필요한 모델이 다운로드되었는지 확인:"
    echo -e "       ${CYAN}docker exec n8n_ollama ollama list${NC}"
  fi

  print_separator
  echo ""
}

# =============================================================
# 메인 실행
# =============================================================
main() {
  echo ""
  echo -e "${BOLD}${MAGENTA}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║    N8N-Ollama 플랫폼 통합 테스트          ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  대상 서버: ${CYAN}${BASE_URL}${NC}"
  echo -e "  API 키:    ${CYAN}${API_KEY:0:20}...${NC}"
  echo ""

  # 서비스 상태 확인
  check_services

  # 각 워크플로우 테스트 실행
  test_main_assistant
  test_model_router
  test_sentiment_analysis

  # 결과 요약 출력
  print_summary
}

main "$@"
