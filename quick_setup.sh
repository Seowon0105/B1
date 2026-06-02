#!/bin/bash
# =============================================================================
# quick_setup.sh - 초기화된 환경에서 과제 전체를 한 번에 재구성
#
# 사용법 (root로 실행):
#   su -
#   bash quick_setup.sh
#
# 사전 준비: 같은 폴더에 아래 파일이 있어야 함
#   - agent-app-linux-x86   (제공된 앱)
#   - monitor.sh            (관제 스크립트)
#
# 이 스크립트가 STEP 1~10을 전부 자동 처리하고,
# 마지막에 계정 비밀번호 설정과 앱 실행만 안내한다.
# =============================================================================

set -u
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $1"; }
step() { echo -e "\n${YELLOW}===== $1 =====${NC}"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# root 체크
if [ "$(id -u)" -ne 0 ]; then
    err "root로 실행하세요: su - 후 bash quick_setup.sh"
    exit 1
fi

# 스크립트가 있는 폴더 (앱/monitor.sh 위치 기준)
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_HOME="/home/agent-admin/agent-app"

# 필수 파일 확인
if [ ! -f "$SRC_DIR/agent-app-linux-x86" ]; then
    err "agent-app-linux-x86 파일이 $SRC_DIR 에 없습니다."
    exit 1
fi
if [ ! -f "$SRC_DIR/monitor.sh" ]; then
    err "monitor.sh 파일이 $SRC_DIR 에 없습니다."
    exit 1
fi


# ── STEP 1. 패키지 설치 ──
step "STEP 1. 패키지 설치"
apt-get update -qq
apt-get install -y -qq openssh-server ufw cron acl iproute2 procps vim
log "패키지 설치 완료"


# ── STEP 2. SSH 보안 설정 ──
step "STEP 2. SSH 보안 설정"
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-agent-security.conf << 'CONF'
Port 20022
PermitRootLogin no
CONF
chmod 644 /etc/ssh/sshd_config.d/99-agent-security.conf
ssh-keygen -A 2>/dev/null || true
sshd -t && systemctl restart ssh && systemctl enable ssh 2>/dev/null
log "SSH 포트 20022 + root 차단"


# ── STEP 3. UFW 방화벽 ──
step "STEP 3. UFW 방화벽"
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 20022/tcp >/dev/null 2>&1
ufw allow 15034/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1
systemctl enable ufw 2>/dev/null
log "UFW 활성화, 20022/15034 허용"


# ── STEP 4. 계정/그룹 ──
step "STEP 4. 계정/그룹 생성"
groupadd -f agent-common
groupadd -f agent-core
id agent-admin &>/dev/null || useradd -m -s /bin/bash agent-admin
id agent-dev   &>/dev/null || useradd -m -s /bin/bash agent-dev
id agent-test  &>/dev/null || useradd -m -s /bin/bash agent-test
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common            agent-test
log "계정 3개 + 그룹 2개"


# ── STEP 5. 폴더 + 권한 + ACL (root가 한 번에) ──
step "STEP 5. 폴더 구조 + 권한 + ACL"
mkdir -p $AGENT_HOME/upload_files $AGENT_HOME/api_keys $AGENT_HOME/bin
mkdir -p /var/log/agent-app

# 소유권: agent-admin 홈 전체를 agent-core 그룹으로
chown -R agent-admin:agent-core $AGENT_HOME
chown agent-admin:agent-core /var/log/agent-app

chmod 750 $AGENT_HOME
chmod 770 $AGENT_HOME/upload_files
chmod 750 $AGENT_HOME/api_keys
chmod 750 $AGENT_HOME/bin
chmod 770 /var/log/agent-app

# ACL
setfacl -m  g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -dm g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -m  g:agent-core:rwx   $AGENT_HOME/api_keys
setfacl -dm g:agent-core:rwx   $AGENT_HOME/api_keys
setfacl -m  g:agent-core:rwx   /var/log/agent-app
setfacl -dm g:agent-core:rwx   /var/log/agent-app
log "폴더/권한/ACL 완료"


# ── STEP 6. 앱 + 키 파일 배포 ──
step "STEP 6. 앱 + 키 파일 배포"
cp "$SRC_DIR/agent-app-linux-x86" $AGENT_HOME/agent-app
chmod +x $AGENT_HOME/agent-app
chown agent-admin:agent-core $AGENT_HOME/agent-app

# 키 파일 (폴더 안 secret.key, 줄바꿈 없이)
echo -n 'agent_api_key_test' > $AGENT_HOME/api_keys/secret.key
chmod 640 $AGENT_HOME/api_keys/secret.key
chown agent-admin:agent-core $AGENT_HOME/api_keys/secret.key
log "앱 + secret.key 배포"


# ── STEP 7. monitor.sh 배포 ──
step "STEP 7. monitor.sh 배포"
cp "$SRC_DIR/monitor.sh" $AGENT_HOME/bin/monitor.sh
chown agent-dev:agent-core $AGENT_HOME/bin/monitor.sh
chmod 750 $AGENT_HOME/bin/monitor.sh
log "monitor.sh (소유자 agent-dev, 750)"


# ── STEP 8. 환경변수 (agent-admin) ──
#   .bashrc 와 .profile 양쪽에 등록:
#   - .bashrc  : 대화형 셸 (일반 터미널 작업)
#   - .profile : 로그인 셸 (su - 로그인 등). .bashrc 상단의
#                "비대화형이면 return" 가드를 우회하기 위함
step "STEP 8. 환경변수 등록"
ENV_BLOCK='
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=/var/log/agent-app'

for RC in /home/agent-admin/.bashrc /home/agent-admin/.profile; do
    if ! grep -q "AGENT_HOME" "$RC" 2>/dev/null; then
        echo "$ENV_BLOCK" >> "$RC"
        chown agent-admin:agent-admin "$RC"
    fi
done
log "환경변수 등록 (.bashrc + .profile)"


# ── STEP 9. crontab (agent-admin) ──
step "STEP 9. crontab 등록"
if ! command -v crontab &>/dev/null; then
    err "crontab 명령어가 없습니다. cron 패키지 설치를 확인하세요."
else
    CRON_JOB="* * * * * /home/agent-admin/agent-app/bin/monitor.sh"
    CRON_TMP="$(mktemp)"
    crontab -u agent-admin -l 2>/dev/null > "$CRON_TMP" || true
    if ! grep -qF "$CRON_JOB" "$CRON_TMP"; then
        echo "$CRON_JOB" >> "$CRON_TMP"
        if crontab -u agent-admin "$CRON_TMP"; then
            log "crontab 매분 등록"
        else
            err "crontab 등록 실패"
        fi
    else
        log "crontab 이미 등록됨"
    fi
    rm -f "$CRON_TMP"
    systemctl enable cron 2>/dev/null || true
    systemctl start cron 2>/dev/null || true
fi


# ── 완료 안내 ──
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN} 자동 설정 완료! (STEP 1~9)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "남은 수동 작업:"
echo "  1. 계정 비밀번호 설정 (root에서):"
echo "       passwd agent-admin"
echo "       passwd agent-dev"
echo "       passwd agent-test"
echo ""
echo "  2. agent-admin으로 앱 실행:"
echo "       su - agent-admin"
echo "       \$AGENT_HOME/agent-app"
echo ""
echo "  3. 1~2분 후 로그 확인:"
echo "       tail /var/log/agent-app/monitor.log"
