#!/bin/bash
# =============================================================================
# setup_root.sh - 과제 환경 설치 (root 권한 작업)
#
# 실행 방법:
#   su -                      # root로 전환
#   bash /tmp/setup_root.sh   # 이 스크립트 실행
#
# 수행 단계: STEP 1 ~ STEP 5
#   1. 패키지 설치
#   2. SSH 보안 설정 (포트 20022, root 차단)
#   3. UFW 방화벽 설정
#   4. 계정/그룹 생성
#   5. /var/log/agent-app 생성 및 권한 설정
# =============================================================================

set -u   # 정의 안 된 변수 사용 시 에러 (오타 방지)
# set -e 는 사용하지 않음:
#   groupadd(이미 존재), ufw(환경 차이) 등에서 의도치 않게 멈출 수 있어
#   각 단계를 개별 처리하며 진행

# 색상 (가독성용)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'   # 색상 초기화

log() { echo -e "${GREEN}[OK]${NC} $1"; }
step() { echo -e "\n${YELLOW}===== $1 =====${NC}"; }


# ─────────────────────────────────────────────────────────────
# root 권한 체크
# ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "이 스크립트는 root로 실행해야 합니다. 'su -' 후 다시 실행하세요."
    exit 1
fi


# ─────────────────────────────────────────────────────────────
# STEP 1. 패키지 설치
# ─────────────────────────────────────────────────────────────
step "STEP 1. 패키지 설치"

apt-get update
apt-get install -y openssh-server ufw cron acl iproute2 procps vim
log "패키지 설치 완료"


# ─────────────────────────────────────────────────────────────
# STEP 2. SSH 보안 설정
#   - sed로 기존 줄을 바꾸되, Port 라인이 아예 없는 경우를 대비해
#     별도 설정 파일(/etc/ssh/sshd_config.d/)을 추가하는 방식 사용
#     → 가장 확실하게 포트/root 차단을 적용
# ─────────────────────────────────────────────────────────────
step "STEP 2. SSH 보안 설정"

# Ubuntu 24.04는 /etc/ssh/sshd_config.d/ 안의 설정이
# 기본 sshd_config보다 우선 적용됨 → 여기에 추가하면 가장 확실
cat > /etc/ssh/sshd_config.d/99-agent-security.conf << 'CONF'
Port 20022
PermitRootLogin no
CONF
chmod 644 /etc/ssh/sshd_config.d/99-agent-security.conf

# 기존 sshd_config의 충돌 가능한 라인도 정리 (있으면 변경)
sed -i 's/^#\?Port 22$/#Port 22/'                    /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/#PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# 호스트키가 없으면 생성 (sshd -t 통과에 필요)
ssh-keygen -A 2>/dev/null || true

# 설정 문법 검사 (문제 있으면 경고만, set -e로 중단하지 않음)
sshd -t && log "SSH 설정 문법 정상" || echo "  ⚠️  sshd -t 경고 발생 (계속 진행)"

# 서비스 재시작 및 자동시작 등록
# Ubuntu 24.04 표준 서비스명은 ssh
systemctl restart ssh
systemctl enable ssh
log "SSH 포트 20022 변경, root 접속 차단 완료"


# ─────────────────────────────────────────────────────────────
# STEP 3. UFW 방화벽 설정
# ─────────────────────────────────────────────────────────────
step "STEP 3. UFW 방화벽 설정"

ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp    # SSH
ufw allow 15034/tcp    # Agent App
ufw --force enable
log "UFW 활성화, 20022/15034 포트만 허용 완료"


# ─────────────────────────────────────────────────────────────
# STEP 4. 계정/그룹 생성
# ─────────────────────────────────────────────────────────────
step "STEP 4. 계정/그룹 생성"

# 그룹 생성 (이미 있으면 무시)
groupadd -f agent-common
groupadd -f agent-core

# 계정 생성 (이미 있으면 건너뜀)
id agent-admin &>/dev/null || useradd -m -s /bin/bash agent-admin
id agent-dev   &>/dev/null || useradd -m -s /bin/bash agent-dev
id agent-test  &>/dev/null || useradd -m -s /bin/bash agent-test

# 그룹 소속 보장 (계정이 이미 있던 경우에도 그룹을 확실히 설정)
# -a -G : 기존 그룹은 유지하면서 지정 그룹 추가
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common            agent-test

log "계정/그룹 생성 완료"
echo "  ⚠️  비밀번호는 보안상 수동으로 설정하세요:"
echo "       passwd agent-admin"
echo "       passwd agent-dev"
echo "       passwd agent-test"


# ─────────────────────────────────────────────────────────────
# STEP 5. /var/log/agent-app 생성 및 권한 설정
# ─────────────────────────────────────────────────────────────
step "STEP 5. 로그 디렉토리 생성 및 권한 설정"

mkdir -p /var/log/agent-app
chown agent-admin:agent-core /var/log/agent-app
chmod 770 /var/log/agent-app

# ACL 설정 (agent-core 그룹만 접근)
setfacl -m  g:agent-core:rwx /var/log/agent-app
setfacl -dm g:agent-core:rwx /var/log/agent-app
log "/var/log/agent-app 생성 및 권한 설정 완료"


# ─────────────────────────────────────────────────────────────
# 완료 안내
# ─────────────────────────────────────────────────────────────
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN} root 작업(STEP 1~5) 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "다음 작업:"
echo "  1. 계정 비밀번호 설정 (위 안내 참고)"
echo "  2. agent-admin으로 전환: su - agent-admin"
echo "  3. setup_admin.sh 실행: bash /tmp/setup_admin.sh"
