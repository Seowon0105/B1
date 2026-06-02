#!/bin/bash
# =============================================================================
# setup_admin.sh - 과제 환경 설치 (agent-admin 권한 작업)
#
# 실행 방법:
#   su - agent-admin            # agent-admin으로 전환
#   bash /tmp/setup_admin.sh    # 이 스크립트 실행
#
# 사전 준비 (스크립트 실행 전):
#   - /tmp/agent-app  파일이 있어야 함 (제공된 앱, x86 버전)
#   - /tmp/monitor.sh 파일이 있어야 함
#
#   파일 복사 방법 (VM 안에서, OrbStack /mnt/mac 경유):
#     cp /mnt/mac/Users/맥이름/Downloads/agent-app-linux-x86 /tmp/agent-app
#     cp /mnt/mac/Users/맥이름/Downloads/monitor.sh          /tmp/monitor.sh
#
# 수행 단계: STEP 6 ~ STEP 11
#   6.  폴더 구조 생성
#   7.  환경변수 / 키 파일 설정
#   8.  앱 파일 배포 (실행은 수동)
#   9.  monitor.sh 배포 (소유자 변경은 root 안내)
#   10. crontab 등록
# =============================================================================

set -u   # 정의 안 된 변수 사용 시 에러 (오타 방지)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
step() { echo -e "\n${YELLOW}===== $1 =====${NC}"; }


# ─────────────────────────────────────────────────────────────
# agent-admin 계정 체크
# ─────────────────────────────────────────────────────────────
if [ "$(whoami)" != "agent-admin" ]; then
    echo "이 스크립트는 agent-admin으로 실행해야 합니다."
    echo "'su - agent-admin' 후 다시 실행하세요."
    exit 1
fi

# 환경변수 기준값
export AGENT_HOME=/home/agent-admin/agent-app


# ─────────────────────────────────────────────────────────────
# STEP 6. 폴더 구조 생성
#   ⚠️ 폴더의 소유 그룹은 자동으로 agent-admin(개인 그룹)이 됨
#      → agent-core로 바꾸는 chown은 root 권한이 필요 (아래 안내 참고)
# ─────────────────────────────────────────────────────────────
step "STEP 6. 폴더 구조 생성"

mkdir -p $AGENT_HOME/upload_files
mkdir -p $AGENT_HOME/api_keys
mkdir -p $AGENT_HOME/bin

chmod 750 $AGENT_HOME
chmod 770 $AGENT_HOME/upload_files
chmod 750 $AGENT_HOME/api_keys
chmod 750 $AGENT_HOME/bin
log "폴더 생성 및 기본 권한 설정 완료"

echo ""
echo "  ⚠️  소유 그룹을 agent-core로 변경해야 합니다 (root 권한 필요)."
echo "      아래 명령어를 root에서 실행한 뒤, 다시 이 스크립트를 이어서 진행하세요:"
echo "        su -"
echo "        chown -R agent-admin:agent-core /home/agent-admin/agent-app"
echo "        exit"
echo ""
read -p "  위 chown을 완료했으면 Enter를 눌러 계속... " _

# ACL 설정 (chown으로 소유 그룹이 agent-core가 된 후에 적용)
setfacl -m  g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -dm g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -m  g:agent-core:rwx   $AGENT_HOME/api_keys
setfacl -dm g:agent-core:rwx   $AGENT_HOME/api_keys
log "ACL 설정 완료"


# ─────────────────────────────────────────────────────────────
# STEP 7. 환경변수 / 키 파일 설정
# ─────────────────────────────────────────────────────────────
step "STEP 7. 환경변수 / 키 파일 설정"

# 중복 추가 방지: 이미 있으면 건너뜀
# (~/.bashrc 가 없는 경우도 안전하게 처리)
if ! grep -q "AGENT_HOME" ~/.bashrc 2>/dev/null; then
    {
        echo 'export AGENT_HOME=/home/agent-admin/agent-app'
        echo 'export AGENT_PORT=15034'
        echo 'export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files'
        echo 'export AGENT_KEY_PATH=$AGENT_HOME/api_keys'
        echo 'export AGENT_LOG_DIR=/var/log/agent-app'
    } >> ~/.bashrc
    log "환경변수를 ~/.bashrc에 추가"
else
    log "환경변수가 이미 등록되어 있음 (건너뜀)"
fi

# 키 파일 생성 (파일명: secret.key, 줄바꿈 없이 -n)
echo -n 'agent_api_key_test' > $AGENT_HOME/api_keys/secret.key
chmod 640 $AGENT_HOME/api_keys/secret.key
log "키 파일 생성 완료"


# ─────────────────────────────────────────────────────────────
# STEP 8. 앱 파일 배포
# ─────────────────────────────────────────────────────────────
step "STEP 8. 앱 파일 배포"

if [ -f /tmp/agent-app ]; then
    cp /tmp/agent-app $AGENT_HOME/agent-app
    chmod +x $AGENT_HOME/agent-app
    log "agent-app 배포 완료"
else
    echo "  ⚠️  /tmp/agent-app 파일이 없습니다. 먼저 복사하세요:"
    echo "       cp /mnt/mac/Users/맥이름/Downloads/agent-app-linux-x86 /tmp/agent-app"
fi


# ─────────────────────────────────────────────────────────────
# STEP 9. monitor.sh 배포
# ─────────────────────────────────────────────────────────────
step "STEP 9. monitor.sh 배포"

if [ -f /tmp/monitor.sh ]; then
    cp /tmp/monitor.sh $AGENT_HOME/bin/monitor.sh
    log "monitor.sh 복사 완료"
    echo "  ⚠️  소유자/권한 변경은 root 권한이 필요합니다."
    echo "       아래 명령어를 root에서 실행하세요:"
    echo "       su -"
    echo "       chown agent-dev:agent-core $AGENT_HOME/bin/monitor.sh"
    echo "       chmod 750 $AGENT_HOME/bin/monitor.sh"
    echo "       exit"
else
    echo "  ⚠️  /tmp/monitor.sh 파일이 없습니다."
fi


# ─────────────────────────────────────────────────────────────
# STEP 10. crontab 등록
# ─────────────────────────────────────────────────────────────
step "STEP 10. crontab 등록"

CRON_JOB="* * * * * /home/agent-admin/agent-app/bin/monitor.sh"

# 이미 등록되어 있으면 건너뜀
if crontab -l 2>/dev/null | grep -qF "$CRON_JOB"; then
    log "crontab이 이미 등록되어 있음 (건너뜀)"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log "crontab 매분 실행 등록 완료"
fi


# ─────────────────────────────────────────────────────────────
# 완료 안내
# ─────────────────────────────────────────────────────────────
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN} agent-admin 작업 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "남은 작업 (수동):"
echo "  1. monitor.sh 소유자 변경 (위 STEP 9 안내 참고)"
echo "  2. 환경변수 적용: source ~/.bashrc"
echo "  3. 앱 실행: \$AGENT_HOME/agent-app"
echo "  4. 1~2분 후 로그 확인: tail /var/log/agent-app/monitor.log"
