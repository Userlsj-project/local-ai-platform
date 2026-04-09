#!/usr/bin/env bash
# =============================================================
# N8N-Ollama 플랫폼 설정 스크립트
# 의존성 설치, Docker 서비스 시작, Ollama 모델 다운로드
# =============================================================

set -euo pipefail

# --- 색상 정의 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 초기화

# --- 로그 함수 ---
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# --- 현재 스크립트 디렉토리로 이동 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

log_step "N8N-Ollama 플랫폼 설정 시작"
echo -e "  프로젝트 경로: ${PROJECT_ROOT}"

# =============================================================
# 1단계: 필수 의존성 확인
# =============================================================
log_step "1단계: 의존성 확인"

check_command() {
  local cmd="$1"
  local install_hint="$2"
  if command -v "$cmd" &>/dev/null; then
    log_success "$cmd 설치 확인됨 ($(command -v "$cmd"))"
  else
    log_error "$cmd 가 설치되어 있지 않습니다."
    log_error "설치 방법: $install_hint"
    exit 1
  fi
}

check_command "docker"         "https://docs.docker.com/get-docker/ 참조"
check_command "docker"         "docker compose 플러그인 포함 확인"
check_command "curl"           "sudo apt-get install curl"

# Docker Compose V2 확인
if docker compose version &>/dev/null 2>&1; then
  log_success "Docker Compose V2 확인됨"
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  log_warn "Docker Compose V1 감지됨 (V2 권장)"
  COMPOSE_CMD="docker-compose"
else
  log_error "Docker Compose가 설치되어 있지 않습니다."
  exit 1
fi

# Docker 데몬 실행 확인
if ! docker info &>/dev/null; then
  log_error "Docker 데몬이 실행되고 있지 않습니다."
  log_error "Docker Desktop 또는 Docker 서비스를 시작하세요."
  exit 1
fi
log_success "Docker 데몬 실행 중"

# =============================================================
# 2단계: 환경 변수 파일 확인
# =============================================================
log_step "2단계: 환경 설정 확인"

if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
  log_warn ".env 파일이 없습니다. 기본 설정으로 생성합니다..."
  cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env" 2>/dev/null || {
    log_error ".env 파일을 생성할 수 없습니다. 수동으로 생성하세요."
    exit 1
  }
fi

log_success ".env 파일 확인됨"

# 중요 환경 변수 경고
source "$PROJECT_ROOT/.env" 2>/dev/null || true
if [[ "${N8N_ENCRYPTION_KEY:-}" == *"change-in-production"* ]]; then
  log_warn "N8N_ENCRYPTION_KEY가 기본값입니다. 프로덕션에서는 반드시 변경하세요!"
fi

# =============================================================
# 3단계: Docker 서비스 시작
# =============================================================
log_step "3단계: Docker 서비스 시작"

log_info "기존 컨테이너 정지 및 제거 중..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

log_info "최신 이미지 다운로드 중..."
$COMPOSE_CMD pull

log_info "서비스 시작 중 (백그라운드)..."
$COMPOSE_CMD up -d

# =============================================================
# 4단계: 서비스 헬스체크 대기
# =============================================================
log_step "4단계: 서비스 헬스체크"

wait_for_service() {
  local service_name="$1"
  local url="$2"
  local max_attempts="${3:-30}"
  local attempt=0

  log_info "$service_name 준비 대기 중..."
  while [[ $attempt -lt $max_attempts ]]; do
    if curl -sf "$url" &>/dev/null; then
      log_success "$service_name 준비 완료"
      return 0
    fi
    attempt=$((attempt + 1))
    echo -n "."
    sleep 3
  done
  echo ""
  log_warn "$service_name 응답 없음 (계속 진행...)"
  return 1
}

wait_for_service "PostgreSQL" "http://localhost:5432" 20 || true
wait_for_service "Redis"      "http://localhost:6379" 10 || true
wait_for_service "Ollama"     "http://localhost:11434/api/tags" 30
wait_for_service "N8N"        "http://localhost:5678/healthz" 40

# =============================================================
# 5단계: Ollama 모델 다운로드
# =============================================================
log_step "5단계: Ollama 모델 다운로드"

OLLAMA_URL="http://localhost:11434"

pull_model() {
  local model_name="$1"
  log_info "모델 다운로드 중: ${model_name}"

  if curl -sf "${OLLAMA_URL}/api/tags" | grep -q "\"${model_name}\"" 2>/dev/null; then
    log_success "${model_name} 이미 다운로드됨"
    return 0
  fi

  # Docker exec로 모델 풀 (컨테이너 내부에서 실행)
  if docker exec n8n_ollama ollama pull "${model_name}"; then
    log_success "${model_name} 다운로드 완료"
  else
    log_warn "${model_name} 다운로드 실패 (수동으로 실행: docker exec n8n_ollama ollama pull ${model_name})"
  fi
}

# 워크플로우에서 사용하는 모든 모델 다운로드
pull_model "llama3.2"        # 기본 모델 (메인 어시스턴트, 감정 분석)
pull_model "llama3.2:1b"    # 경량 모델 (라우터 - simple)

# llama3.2:latest는 llama3.2와 동일하므로 별도 풀 불필요
log_info "llama3.2:latest 태그 확인 중..."
docker exec n8n_ollama ollama list 2>/dev/null || true

# =============================================================
# 6단계: N8N 워크플로우 가져오기 안내
# =============================================================
log_step "6단계: N8N 워크플로우 설정"

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  N8N 워크플로우 수동 가져오기 필요${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  1. N8N 웹 UI 접속: ${CYAN}http://localhost:5678${NC}"
echo -e "     계정: ${GREEN}admin${NC} / 비밀번호: ${GREEN}admin123!${NC}"
echo ""
echo -e "  2. 다음 자격증명(Credentials)을 먼저 생성하세요:"
echo -e "     ${CYAN}[Settings → Credentials → New]${NC}"
echo ""
echo -e "     a) ${GREEN}Redis 연결${NC}"
echo -e "        - 유형: Redis"
echo -e "        - Host: redis, Port: 6379"
echo -e "        - Password: redis_secure_password_2024"
echo ""
echo -e "     b) ${GREEN}PostgreSQL 연결${NC}"
echo -e "        - 유형: Postgres"
echo -e "        - Host: postgres, Port: 5432"
echo -e "        - Database: n8n_ollama"
echo -e "        - User: n8n_user"
echo -e "        - Password: n8n_secure_password_2024"
echo ""
echo -e "  3. 워크플로우 가져오기:"
echo -e "     ${CYAN}[Workflows → Import from file]${NC}"
echo -e "     - ${PROJECT_ROOT}/workflows/01_main_ai_assistant.json"
echo -e "     - ${PROJECT_ROOT}/workflows/02_multi_model_router.json"
echo -e "     - ${PROJECT_ROOT}/workflows/04_sentiment_analysis.json"
echo ""
echo -e "  4. 각 워크플로우를 열고 ${GREEN}[Active]${NC} 토글을 켜세요."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================
# 설정 완료 요약
# =============================================================
log_step "설정 완료"

echo ""
echo -e "${GREEN}✓ N8N-Ollama 플랫폼이 성공적으로 시작되었습니다!${NC}"
echo ""
echo -e "  서비스 상태 확인: ${CYAN}docker compose ps${NC}"
echo -e "  로그 확인:        ${CYAN}docker compose logs -f${NC}"
echo -e "  서비스 중지:      ${CYAN}docker compose down${NC}"
echo ""
echo -e "  API 테스트:       ${CYAN}bash scripts/test-all.sh${NC}"
echo ""
