#!/bin/bash
# =============================================================================
# monitor.sh - Agent App 시스템 관제 스크립트
#
# 파일 위치 : $AGENT_HOME/bin/monitor.sh
# 소유자    : agent-dev
# 그룹      : agent-core
# 권한      : 750 (rwxr-x---)
# 실행 계정 : agent-admin (cron으로 매분 자동 실행)
# =============================================================================


# ─────────────────────────────────────────────────────────────
# [0단계] 변수 설정
#   - 스크립트 전체에서 공통으로 사용하는 값들을 미리 정의
# ─────────────────────────────────────────────────────────────

# 감시할 앱 파일명 (ps 목록에서 이 이름으로 프로세스를 찾음)
APP_NAME="agent-app"

# 앱이 사용하는 포트 번호
APP_PORT=15034

# 로그를 저장할 디렉토리 (환경변수가 없으면 기본값 사용)
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

# 로그 파일 전체 경로
LOG_FILE="${LOG_DIR}/monitor.log"

# 로그 파일 최대 크기: 10MB (단위: bytes)
LOG_MAX_SIZE=$((10 * 1024 * 1024))

# 오래된 로그 파일을 최대 몇 개까지 보관할지
LOG_MAX_FILES=10

# 현재 날짜/시간 (로그에 기록할 때 사용)
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"


# ─────────────────────────────────────────────────────────────
# [1단계] 프로세스 확인 (Health Check)
#   - agent-app 이 실행 중인지 확인
#   - 실행 중이 아니면 에러 로그를 남기고 즉시 종료
# ─────────────────────────────────────────────────────────────

# pgrep -f : 프로세스 목록에서 APP_NAME 이 포함된 항목을 찾아 PID 반환
# head -1  : 여러 개 나와도 첫 번째 PID만 사용
APP_PID="$(pgrep -f "${APP_NAME}" | head -1)"

if [ -z "${APP_PID}" ]; then
    # -z : 변수가 비어있으면(앱이 없으면) 아래 실행
    echo "[${TIMESTAMP}] [ERROR] 프로세스 '${APP_NAME}' 가 실행 중이 아닙니다." \
        | tee -a "${LOG_FILE}"
    exit 1   # 스크립트를 비정상 종료 (exit 1 = 실패)
fi


# ─────────────────────────────────────────────────────────────
# [2단계] 포트 확인 (Health Check)
#   - TCP 15034 포트가 LISTEN 상태인지 확인
#   - ss 명령어가 없는 환경을 대비해 /proc/net/tcp 로 확인
#   - LISTEN 아니면 에러 로그를 남기고 즉시 종료
# ─────────────────────────────────────────────────────────────

# 포트 번호를 16진수로 변환 (예: 15034 → 3ABA)
# /proc/net/tcp 파일은 포트를 16진수로 저장하기 때문
PORT_HEX="$(printf '%04X' "${APP_PORT}")"

# /proc/net/tcp 에서 해당 포트가 LISTEN(상태코드 0A) 인지 확인
# awk '$4=="0A"' : 4번째 컬럼이 0A(LISTEN)인 줄만 필터
PORT_CHECK="$(grep -i "${PORT_HEX}" /proc/net/tcp 2>/dev/null \
    | awk '$4=="0A"')"

if [ -z "${PORT_CHECK}" ]; then
    echo "[${TIMESTAMP}] [ERROR] TCP ${APP_PORT} 포트가 LISTEN 상태가 아닙니다." \
        | tee -a "${LOG_FILE}"
    exit 1
fi


# ─────────────────────────────────────────────────────────────
# [3단계] 방화벽 상태 확인
#   - UFW 또는 firewalld 가 활성화되어 있는지 확인
#   - 비활성 상태면 [WARNING] 출력만 하고 스크립트는 계속 진행
# ─────────────────────────────────────────────────────────────

if command -v ufw &>/dev/null; then
    # UFW 가 설치되어 있는 경우
    # ufw status 출력에서 "Status:" 다음 단어(active/inactive)를 추출
    UFW_STATE="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}')"

    if [ "${UFW_STATE}" != "active" ]; then
        echo "[${TIMESTAMP}] [WARNING] UFW 방화벽이 비활성 상태입니다."
    fi

elif command -v firewall-cmd &>/dev/null; then
    # firewalld 가 설치되어 있는 경우
    FW_STATE="$(firewall-cmd --state 2>/dev/null)"

    if [ "${FW_STATE}" != "running" ]; then
        echo "[${TIMESTAMP}] [WARNING] firewalld 가 실행 중이 아닙니다."
    fi

else
    # UFW, firewalld 둘 다 없는 경우
    echo "[${TIMESTAMP}] [WARNING] 지원하는 방화벽(UFW/firewalld)을 찾을 수 없습니다."
fi


# ─────────────────────────────────────────────────────────────
# [4단계] 시스템 자원 수집
#   - CPU 사용률, 메모리 사용률, 디스크 사용률을 측정
# ─────────────────────────────────────────────────────────────

# --- CPU 사용률 계산 ---
# top -bn1 : 화면 갱신 없이 1번만 실행
# grep '%Cpu' : CPU 정보가 있는 줄만 추출
# sed 's/.*,\s*\([0-9.]*\)\s*id.*/\1/' : "id(idle, 노는 시간)" 숫자만 추출
CPU_IDLE="$(top -bn1 2>/dev/null \
    | grep '%Cpu' \
    | sed 's/.*,\s*\([0-9.]*\)\s*id.*/\1/')"

# idle 값이 비어있으면 0으로 처리 (파싱 실패 방어)
CPU_IDLE="${CPU_IDLE:-0}"

# 사용률 = 100 - idle (소수점 1자리)
# awk의 BEGIN 블록으로 계산 (bash는 소수점 계산 불가)
CPU_USAGE="$(awk "BEGIN {printf \"%.1f\", 100 - ${CPU_IDLE}}")"


# --- 메모리 사용률 계산 ---
# free 명령어: 메모리 현황 출력
# awk '/^Mem:/' : "Mem:" 으로 시작하는 줄만 선택
# {print $2}    : 2번째 컬럼(전체 용량) 추출
# {print $3}    : 3번째 컬럼(사용 중인 용량) 추출
MEM_TOTAL="$(free | awk '/^Mem:/{print $2}')"
MEM_USED="$(free  | awk '/^Mem:/{print $3}')"

if [ "${MEM_TOTAL:-0}" -gt 0 ]; then
    MEM_USAGE="$(awk "BEGIN {printf \"%.1f\", (${MEM_USED} / ${MEM_TOTAL}) * 100}")"
else
    MEM_USAGE="0.0"
fi


# --- 디스크 사용률 수집 ---
# df / : 루트(/) 파티션의 디스크 사용 현황
# NR==2 : 첫 번째 줄(헤더)을 건너뛰고 두 번째 줄(실제 데이터)만 사용
# gsub(/%/,"",$5) : 5번째 컬럼의 % 기호를 제거
# print $5        : 숫자만 남긴 사용률 출력
DISK_USED="$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"


# ─────────────────────────────────────────────────────────────
# [5단계] 임계값 초과 경고
#   - 수집한 자원이 기준을 넘으면 [WARNING] 출력
#   - 경고만 하고 스크립트는 계속 진행 (종료 안 함)
# ─────────────────────────────────────────────────────────────

# 소수점이 있는 값을 정수로 변환 (bash는 정수 비교만 가능)
# awk -F'.' '{print $1}' : 소수점 앞 숫자만 추출 (예: 35.2 → 35)
CPU_INT="$(echo "${CPU_USAGE}" | awk -F'.' '{print $1}')"
MEM_INT="$(echo "${MEM_USAGE}" | awk -F'.' '{print $1}')"

# CPU > 20% 경고
if [ "${CPU_INT:-0}" -gt 20 ]; then
    echo "[${TIMESTAMP}] [WARNING] CPU 사용률 높음: ${CPU_USAGE}% (기준: 20%)"
fi

# 메모리 > 10% 경고
if [ "${MEM_INT:-0}" -gt 10 ]; then
    echo "[${TIMESTAMP}] [WARNING] 메모리 사용률 높음: ${MEM_USAGE}% (기준: 10%)"
fi

# 디스크 > 80% 경고
if [ "${DISK_USED:-0}" -gt 80 ]; then
    echo "[${TIMESTAMP}] [WARNING] 디스크 사용률 높음: ${DISK_USED}% (기준: 80%)"
fi


# ─────────────────────────────────────────────────────────────
# [6단계] 로그 기록
#   - 수집한 정보를 monitor.log 파일에 한 줄 추가
# ─────────────────────────────────────────────────────────────

# 로그 디렉토리가 없으면 새로 만들기
if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null
fi

# 로그 한 줄 작성
# >> : 파일 끝에 추가 (덮어쓰지 않음)
echo "[${TIMESTAMP}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%" \
    >> "${LOG_FILE}"


# ─────────────────────────────────────────────────────────────
# [7단계] 로그 파일 용량 관리 (자동 rotate)
#   - monitor.log 가 10MB 를 넘으면 자동으로 정리
#   - monitor.log.1 ~ .10 까지 최대 10개 보관
#   - 10개 초과분은 gzip 압축 후 삭제
# ─────────────────────────────────────────────────────────────

if [ -f "${LOG_FILE}" ]; then
    # 현재 로그 파일 크기를 bytes 단위로 가져오기
    CURRENT_SIZE="$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)"

    if [ "${CURRENT_SIZE}" -ge "${LOG_MAX_SIZE}" ]; then
        # 파일 번호를 큰 것부터 작은 것 순서로 밀어내기
        # 예: .9 → .10, .8 → .9, ... .1 → .2
        for i in $(seq $((LOG_MAX_FILES - 1)) -1 1); do
            SRC="${LOG_FILE}.${i}"
            DST="${LOG_FILE}.$((i + 1))"

            if [ -f "${SRC}" ]; then
                if [ "$((i + 1))" -ge "${LOG_MAX_FILES}" ]; then
                    # 최대 개수를 넘는 파일은 압축 후 삭제
                    gzip -f "${SRC}" 2>/dev/null || rm -f "${SRC}"
                else
                    mv -f "${SRC}" "${DST}"
                fi
            fi
        done

        # 현재 로그 파일을 .1 로 이동하고 새 파일 시작
        mv -f "${LOG_FILE}" "${LOG_FILE}.1"
        touch "${LOG_FILE}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 로그 파일이 rotate 되었습니다." \
            >> "${LOG_FILE}"
    fi
fi

exit 0
