#!/usr/bin/env bash
# =============================================================
# Git 저장소 초기화 및 GitHub 푸시 스크립트
# 한국어 커밋 메시지로 순차적 커밋 후 GitHub에 푸시
# =============================================================

set -euo pipefail

# --- 색상 정의 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# --- 현재 스크립트 디렉토리로 이동 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

log_step "Git 저장소 설정 시작"
echo -e "  프로젝트 경로: ${PROJECT_ROOT}"

# =============================================================
# Git 사용자 설정 확인
# =============================================================
log_step "Git 설정 확인"

if ! git config user.name &>/dev/null || [[ -z "$(git config user.name)" ]]; then
  log_warn "Git 사용자 이름이 설정되지 않았습니다."
  read -rp "  Git 사용자 이름을 입력하세요: " GIT_USER_NAME
  git config --global user.name "$GIT_USER_NAME"
fi

if ! git config user.email &>/dev/null || [[ -z "$(git config user.email)" ]]; then
  log_warn "Git 사용자 이메일이 설정되지 않았습니다."
  read -rp "  Git 사용자 이메일을 입력하세요: " GIT_USER_EMAIL
  git config --global user.email "$GIT_USER_EMAIL"
fi

log_success "Git 사용자: $(git config user.name) <$(git config user.email)>"

# =============================================================
# 1단계: Git 저장소 초기화
# =============================================================
log_step "1단계: Git 초기화"

if [[ -d "$PROJECT_ROOT/.git" ]]; then
  log_warn "이미 Git 저장소가 존재합니다. 기존 기록을 제거하고 재초기화합니다..."
  rm -rf "$PROJECT_ROOT/.git"
fi

git init
git checkout -b main
log_success "Git 저장소 초기화 완료 (브랜치: main)"

# =============================================================
# .gitignore 생성
# =============================================================
log_step ".gitignore 생성"

cat > "$PROJECT_ROOT/.gitignore" << 'GITIGNORE'
# =============================================================
# N8N-Ollama 플랫폼 .gitignore
# =============================================================

# 환경 변수 파일 (민감 정보 포함)
.env
.env.local
.env.production
.env.*.local

# Docker 볼륨 데이터
volumes/
data/

# Node.js 의존성
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# 운영체제 생성 파일
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
Thumbs.db
ehthumbs.db
Desktop.ini

# IDE 설정
.vscode/settings.json
.vscode/launch.json
.idea/
*.swp
*.swo
*~

# 로그 파일
*.log
logs/
*.pid

# 임시 파일
*.tmp
*.temp
.cache/

# 빌드 출력물
dist/
build/
out/

# Python 가상환경 (테스트용)
venv/
__pycache__/
*.pyc
GITIGNORE

log_success ".gitignore 생성 완료"

# =============================================================
# 커밋 헬퍼 함수
# =============================================================

make_commit() {
  local message="$1"
  shift
  local files=("$@")

  # 지정된 파일만 스테이징
  for file in "${files[@]}"; do
    if [[ -e "$PROJECT_ROOT/$file" ]]; then
      git add "$PROJECT_ROOT/$file"
    else
      log_warn "파일 없음, 건너뜀: $file"
    fi
  done

  # 변경사항이 있는 경우에만 커밋
  if git diff --cached --quiet; then
    log_warn "커밋할 변경사항 없음: $message"
  else
    git commit -m "$message"
    log_success "커밋 완료: $message"
  fi
}

# =============================================================
# 2단계: 순차 커밋 생성
# =============================================================
log_step "2단계: 순차 커밋 생성"

# 커밋 1: 프로젝트 초기화
log_info "커밋 1/7: 프로젝트 초기화"
git add .gitignore
git commit -m "init: 프로젝트 초기화"
log_success "init: 프로젝트 초기화"

# 커밋 2: Docker Compose 설정
log_info "커밋 2/7: Docker Compose 설정 추가"
make_commit "feat: Docker Compose 설정 추가" \
  "docker-compose.yaml" \
  ".env" \
  "scripts/init-db.sql" \
  "scripts/setup.sh"

# 커밋 3: 메인 AI 어시스턴트 워크플로우
log_info "커밋 3/7: 메인 AI 어시스턴트 워크플로우"
make_commit "feat: 메인 AI 어시스턴트 워크플로우 구현" \
  "workflows/01_main_ai_assistant.json"

# 커밋 4: 멀티 모델 라우터 워크플로우
log_info "커밋 4/7: 멀티 모델 라우터 워크플로우"
make_commit "feat: 멀티 모델 라우터 워크플로우 구현" \
  "workflows/02_multi_model_router.json"

# 커밋 5: 감정 분석 워크플로우
log_info "커밋 5/7: 감정 분석 워크플로우"
make_commit "feat: 감정 분석 워크플로우 구현" \
  "workflows/04_sentiment_analysis.json"

# 커밋 6: README 및 문서
log_info "커밋 6/7: README 및 아키텍처 문서"
make_commit "docs: README 및 아키텍처 문서 작성" \
  "README.md" \
  "docs/"

# 커밋 7: 테스트 스크립트
log_info "커밋 7/7: 테스트 스크립트 추가"
make_commit "test: 테스트 스크립트 추가" \
  "scripts/test-all.sh" \
  "scripts/git-setup.sh" \
  "tests/"

# =============================================================
# 3단계: 커밋 기록 확인
# =============================================================
log_step "3단계: 커밋 기록 확인"
git log --oneline --graph --decorate
echo ""

# =============================================================
# 4단계: GitHub 푸시
# =============================================================
log_step "4단계: GitHub 원격 저장소 연결"

echo ""
echo -e "${YELLOW}GitHub 원격 저장소 URL을 입력하세요.${NC}"
echo -e "  예시: https://github.com/username/n8n-ollama-platform.git"
echo -e "  또는: git@github.com:username/n8n-ollama-platform.git"
echo ""
read -rp "  GitHub URL (건너뛰려면 Enter): " GITHUB_URL

if [[ -z "$GITHUB_URL" ]]; then
  log_warn "GitHub URL이 입력되지 않아 푸시를 건너뜁니다."
  echo ""
  echo -e "  나중에 푸시하려면:"
  echo -e "  ${CYAN}git remote add origin <GitHub URL>${NC}"
  echo -e "  ${CYAN}git push -u origin main${NC}"
else
  log_info "원격 저장소 추가 중: $GITHUB_URL"
  git remote add origin "$GITHUB_URL"

  log_info "GitHub에 푸시 중..."
  if git push -u origin main; then
    log_success "GitHub 푸시 완료!"
    echo ""
    echo -e "  저장소 URL: ${CYAN}${GITHUB_URL%.git}${NC}"
  else
    log_error "푸시 실패. 인증 정보나 URL을 확인하세요."
    echo ""
    echo -e "  수동 푸시 명령:"
    echo -e "  ${CYAN}git push -u origin main${NC}"
  fi
fi

# =============================================================
# 완료
# =============================================================
log_step "Git 설정 완료"

echo ""
echo -e "${GREEN}✓ Git 저장소 설정이 완료되었습니다!${NC}"
echo ""
git log --oneline --graph --decorate --all
echo ""
