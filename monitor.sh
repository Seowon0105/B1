#!/bin/bash
# =============================================================================
# monitor.sh - Agent App 시스템 관제 스크립트
#
# 파일 위치 : $AGENT_HOME/bin/monitor.sh
# 소유자    : agent-dev
# 그룹      : agent-core
# 권한      : 750 (rwxr-x---)
# 실행 계정 : agent-admin (cron으로 매분 자동 실행)
#
# 실행 환경 : Ubuntu 24.04 LTS (Docker 컨테이너)
# =============================================================================


# ─────────────────────────────────────────────────────────────
# [0단계] 변수 설정
# ─────────────────────────────────────────────────────────────

APP_NAME="agent-app"
APP_PORT=15034
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_DIR}/monitor.log"
LOG_MAX_SIZE=$((10 * 1024 * 1024))   # 10MB
LOG_MAX_FILES=10
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"


# ─────────────────────────────────────────────────────────────
# [1단계] 프로세스 확인 (Health Check)
#   - agent-app 프로세스가 실행 중인지 확인
#   - 없으면 에러 로그를 남기고 즉시 종료 (exit 1)
# ─────────────────────────────────────────────────────────────

APP_PID="$(pgrep -f "${APP_NAME}" | head -1)"

if [ -z "${APP_PID}" ]; then
    echo "[${TIMESTAMP}] [ERROR] 프로세스 '${APP_NAME}' 가 실행 중이 아닙니다." \
        | tee -a "${LOG_FILE}"
    exit 1
fi


# ─────────────────────────────────────────────────────────────
# [2단계] 포트 확인 (Health Check)
#   - TCP 15034 포트가 LISTEN 상태인지 확인
#   - Ubuntu 24.04 도커 환경: ss 명령어 사용 (iproute2 패키지)
#   - ss 없을 경우 /proc/net/tcp 로 대체
# ─────────────────────────────────────────────────────────────

PORT_CHECK=""

if command -v ss &>/dev/null; then
    # ss 명령어가 있는 경우 (iproute2 설치됨)
    PORT_CHECK="$(ss -tulnp 2>/dev/null | grep ":${APP_PORT} ")"
else
    # ss 없을 경우 /proc/net/tcp 로 확인
    # 포트를 16진수로 변환 (15034 → 3ABA)
    PORT_HEX="$(printf '%04X' "${APP_PORT}")"
    PORT_CHECK="$(grep -i "${PORT_HEX}" /proc/net/tcp 2>/dev/null | awk '$4=="0A"')"
fi

if [ -z "${PORT_CHECK}" ]; then
    echo "[${TIMESTAMP}] [ERROR] TCP ${APP_PORT} 포트가 LISTEN 상태가 아닙니다." \
        | tee -a "${LOG_FILE}"
    exit 1
fi


# ─────────────────────────────────────────────────────────────
# [3단계] 방화벽 상태 확인
#   - UFW 또는 firewalld 활성화 여부 확인
#   - 도커 환경에서는 UFW가 비활성일 수 있어 WARNING만 출력
#   - 스크립트는 종료하지 않고 계속 진행
# ─────────────────────────────────────────────────────────────

if command -v ufw &>/dev/null; then
    UFW_STATE="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}')"
    if [ "${UFW_STATE}" != "active" ]; then
        echo "[${TIMESTAMP}] [WARNING] UFW 방화벽이 비활성 상태입니다."
    fi
elif command -v firewall-cmd &>/dev/null; then
    FW_STATE="$(firewall-cmd --state 2>/dev/null)"
    if [ "${FW_STATE}" != "running" ]; then
        echo "[${TIMESTAMP}] [WARNING] firewalld 가 실행 중이 아닙니다."
    fi
else
    echo "[${TIMESTAMP}] [WARNING] 지원하는 방화벽(UFW/firewalld)을 찾을 수 없습니다."
fi


# ─────────────────────────────────────────────────────────────
# [4단계] 시스템 자원 수집
#   - Ubuntu 24.04: top/free/df 명령어 동일하게 사용 가능
# ─────────────────────────────────────────────────────────────

# --- CPU 사용률 ---
# top -bn1 실행 후 '%Cpu' 줄에서 idle(id) 값 추출
# idle 값을 100에서 빼면 사용률
CPU_IDLE="$(top -bn1 2>/dev/null \
    | grep '%Cpu' \
    | sed 's/.*,\s*\([0-9.]*\)\s*id.*/\1/')"
CPU_IDLE="${CPU_IDLE:-0}"
CPU_USAGE="$(awk "BEGIN {printf \"%.1f\", 100 - ${CPU_IDLE}}")"

# --- 메모리 사용률 ---
# free -k : KB 단위로 통일 (Ubuntu 24.04는 기본 단위가 KiB)
# $2=전체, $3=사용중
MEM_TOTAL="$(free -k | awk '/^Mem:/{print $2}')"
MEM_USED="$(free -k  | awk '/^Mem:/{print $3}')"
if [ "${MEM_TOTAL:-0}" -gt 0 ]; then
    MEM_USAGE="$(awk "BEGIN {printf \"%.1f\", (${MEM_USED} / ${MEM_TOTAL}) * 100}")"
else
    MEM_USAGE="0.0"
fi

# --- 디스크 사용률 ---
# df / 의 5번째 컬럼(Use%)에서 % 제거 후 숫자만 추출
DISK_USED="$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"


# ─────────────────────────────────────────────────────────────
# [5단계] 임계값 초과 경고
#   - 기준 초과 시 WARNING 출력, 스크립트는 계속 진행
# ─────────────────────────────────────────────────────────────

# bash는 소수점 비교 불가 → 정수로 변환 후 비교
CPU_INT="$(echo "${CPU_USAGE}" | awk -F'.' '{print $1}')"
MEM_INT="$(echo "${MEM_USAGE}" | awk -F'.' '{print $1}')"

if [ "${CPU_INT:-0}" -gt 20 ]; then
    echo "[${TIMESTAMP}] [WARNING] CPU 사용률 높음: ${CPU_USAGE}% (기준: 20%)"
fi

if [ "${MEM_INT:-0}" -gt 10 ]; then
    echo "[${TIMESTAMP}] [WARNING] 메모리 사용률 높음: ${MEM_USAGE}% (기준: 10%)"
fi

if [ "${DISK_USED:-0}" -gt 80 ]; then
    echo "[${TIMESTAMP}] [WARNING] 디스크 사용률 높음: ${DISK_USED}% (기준: 80%)"
fi


# ─────────────────────────────────────────────────────────────
# [6단계] 로그 기록
#   - /var/log/agent-app/monitor.log 에 한 줄 추가
# ─────────────────────────────────────────────────────────────

if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null
fi

echo "[${TIMESTAMP}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%" \
    >> "${LOG_FILE}"


# ─────────────────────────────────────────────────────────────
# [7단계] 로그 파일 용량 관리
#   - 10MB 초과 시 자동 rotate
#   - monitor.log.1 ~ .10 최대 10개 보관
#   - 초과분은 gzip 압축 후 삭제
# ─────────────────────────────────────────────────────────────

if [ -f "${LOG_FILE}" ]; then
    CURRENT_SIZE="$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)"

    if [ "${CURRENT_SIZE}" -ge "${LOG_MAX_SIZE}" ]; then
        # 번호가 큰 것부터 밀어내기 (.9 → .10, .8 → .9 ...)
        for i in $(seq $((LOG_MAX_FILES - 1)) -1 1); do
            SRC="${LOG_FILE}.${i}"
            DST="${LOG_FILE}.$((i + 1))"
            if [ -f "${SRC}" ]; then
                if [ "$((i + 1))" -ge "${LOG_MAX_FILES}" ]; then
                    gzip -f "${SRC}" 2>/dev/null || rm -f "${SRC}"
                else
                    mv -f "${SRC}" "${DST}"
                fi
            fi
        done
        # 현재 로그 → .1 로 이동, 새 파일 생성
        mv -f "${LOG_FILE}" "${LOG_FILE}.1"
        touch "${LOG_FILE}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 로그 파일 rotate 완료." >> "${LOG_FILE}"
    fi
fi

exit 0
