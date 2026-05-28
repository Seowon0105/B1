# Linux 시스템 보안 및 관제 자동화 과제

> **Ubuntu 24.04 LTS (Docker 컨테이너)** 환경에서 Agent App을 안전하게 설치하고,  
> 시스템 상태를 자동으로 감시하는 환경을 구성한 과제입니다.

---

## 📁 제출 산출물

```
📄 README.md          ← 요구사항 수행 내역서 (이 파일)
📜 monitor.sh         ← 시스템 관제 자동화 스크립트
```

---

## 🐳 Docker 환경 준비

### 컨테이너 실행

```bash
# 호스트 머신에서 실행
# agent-app 파일과 monitor.sh 가 있는 디렉토리에서 실행

docker run -it \
  --name agent-lab \
  --privileged \
  -v $(pwd)/agent-app:/tmp/agent-app \
  -v $(pwd)/monitor.sh:/tmp/monitor.sh \
  ubuntu:24.04 \
  /bin/bash
```

> `--privileged` 옵션은 UFW, cron 등 시스템 기능을 사용하기 위해 필요합니다.

### 컨테이너 재접속 방법

```bash
# 컨테이너가 실행 중일 때 재접속
docker exec -it agent-lab /bin/bash

# 컨테이너가 멈춰있을 때 재시작 후 접속
docker start agent-lab
docker exec -it agent-lab /bin/bash
```

### 필수 패키지 설치 (컨테이너 안에서 실행)

```bash
# 패키지 목록 업데이트
apt-get update

# 필수 패키지 한 번에 설치
apt-get install -y \
  openssh-server \
  ufw \
  cron \
  acl \
  iproute2 \
  procps \
  vim

# 설치 확인
which sshd ufw crontab setfacl ss
```

> 📌 이 설치 단계는 **과제 시작 전 딱 한 번만** 하면 됩니다.

---

## ⚠️ sudo 사용 원칙

> 가능한 **일반 계정으로 진행**하고, 꼭 필요한 경우에만 `sudo`를 사용합니다.

| 구분 | 설명 | 예시 |
|------|------|------|
| ✅ sudo 필요 | 시스템 파일 수정, 다른 계정 소유 파일 변경 | SSH 설정, UFW, 계정 생성, `/var/log` 생성 |
| ❌ sudo 불필요 | 내 홈 디렉토리 작업, 상태 확인 | `$AGENT_HOME` 파일 생성, 환경변수, 앱 실행 |

> 📌 도커 컨테이너는 기본적으로 root로 로그인됩니다.  
> STEP 1~3은 root로 진행하고, STEP 4부터는 `agent-admin` 으로 전환합니다.

---

## ⚠️ 도커 환경의 제약 사항

도커 컨테이너는 일반 VM/서버와 다른 점이 있습니다. 아래 내용을 미리 숙지하세요.

| 항목 | 일반 서버 | 도커 컨테이너 |
|------|-----------|---------------|
| SSH 서비스 시작 | `systemctl start sshd` | `service ssh start` 또는 `/usr/sbin/sshd` |
| cron 서비스 시작 | `systemctl enable cron` | `service cron start` (매번 수동 시작 필요) |
| UFW | 정상 동작 | `--privileged` 옵션 필요 |
| systemctl | 정상 동작 | ❌ 사용 불가 (PID 1이 systemd 아님) |

---

## 📋 목차

1. [전체 구성 개요](#1-전체-구성-개요)
2. [SSH 보안 설정](#2-ssh-보안-설정)
3. [방화벽UFW-설정](#3-방화벽ufw-설정)
4. [계정--그룹-구성](#4-계정--그룹-구성)
5. [디렉토리-구조-및-권한](#5-디렉토리-구조-및-권한)
6. [환경-변수-및-키-파일](#6-환경-변수-및-키-파일)
7. [애플리케이션-실행](#7-애플리케이션-실행)
8. [monitorsh-구현](#8-monitorsh-구현)
9. [crontab-자동-실행-등록](#9-crontab-자동-실행-등록)
10. [로그-파일-관리](#10-로그-파일-관리)
11. [증거-자료-체크리스트](#11-증거-자료-체크리스트)
12. [트러블슈팅](#12-트러블슈팅)

---

## 1. 전체 구성 개요

```
[보안 기반]          [실행 환경]            [자동 감시]
SSH 포트 변경   →   계정/폴더 구성    →   monitor.sh 작성
방화벽 설정     →   환경 변수 등록    →   cron 자동 실행
Root 접속 차단  →   앱 실행 확인      →   로그 누적 확인
```

### 전체 실행 순서 한눈에 보기

```
[컨테이너 안, root 계정]
  STEP 0. 패키지 설치
  STEP 1. SSH 설정 변경
  STEP 2. UFW 방화벽 설정
  STEP 3. 계정/그룹 생성
         ↓
         su - agent-admin  ← 여기서부터 일반 계정으로 전환
         ↓
  STEP 4. 폴더 구조 생성
  STEP 5. 환경변수 / 키 파일 설정
  STEP 6. 앱 실행 확인       ← 터미널 1 유지
         ↓
         새 터미널: docker exec -it agent-lab /bin/bash
         su - agent-admin
         ↓
  STEP 7. monitor.sh 배포
  STEP 8. monitor.sh 수동 실행 테스트
  STEP 9. cron 서비스 시작 + crontab 등록
  STEP 10. 자동 실행 확인
```

---

## 2. SSH 보안 설정

### 왜 하는가
- 기본 포트(22)는 자동화된 해킹 프로그램이 항상 침입 시도를 합니다.
- 포트를 20022로 바꾸면 자동화 공격 대부분을 피할 수 있습니다.
- root 직접 접속을 막아 서버 전체 탈취를 방지합니다.

> `/etc/ssh/sshd_config` 는 시스템 파일 → `sudo` 필요  
> 도커에서는 `systemctl` 대신 `service ssh start` 사용

### 설정 명령어

```bash
# [sudo 필요] sshd_config 수정
sudo sed -i 's/^#Port 22/Port 20022/'                    /etc/ssh/sshd_config
sudo sed -i 's/^Port 22/Port 20022/'                     /etc/ssh/sshd_config
sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/'  /etc/ssh/sshd_config

# [sudo 필요] SSH 서비스 시작
# 도커에서는 systemctl 대신 service 또는 직접 실행
sudo mkdir -p /run/sshd        # sshd 실행에 필요한 디렉토리
sudo service ssh start         # SSH 서비스 시작
```

### 확인 방법 및 결과

```bash
# [일반 계정] 설정 파일 확인
$ grep -E '^Port|^PermitRootLogin' /etc/ssh/sshd_config
Port 20022
PermitRootLogin no

# [일반 계정] 포트 리슨 상태 확인 (ss 명령어)
$ ss -tulnp | grep sshd
tcp  LISTEN  0.0.0.0:20022  users:(("sshd",pid=123,fd=3))

# ss 없을 경우 /proc/net/tcp 로 확인 (4ED6 = 20022의 16진수)
$ grep -i 4ED6 /proc/net/tcp
# 0A = LISTEN 상태
```

---

## 3. 방화벽(UFW) 설정

### 왜 하는가
- 서버의 수천 개 포트 중 필요한 **2개만** 열고 나머지를 전부 차단합니다.
- 허가되지 않은 포트로의 접근을 원천 차단합니다.

| 포트 | 용도 |
|------|------|
| `20022/tcp` | SSH 원격 접속 |
| `15034/tcp` | Agent App |

> UFW 설정은 시스템 방화벽 변경 → `sudo` 필요  
> **상태 확인**은 일반 계정으로 가능  
> 도커에서 UFW를 사용하려면 컨테이너 실행 시 `--privileged` 옵션 필요

### 설정 명령어

```bash
# [sudo 필요] 기본 정책: 들어오는 건 전부 거부
sudo ufw default deny incoming
sudo ufw default allow outgoing

# [sudo 필요] 필요한 포트만 열기
sudo ufw allow 20022/tcp
sudo ufw allow 15034/tcp

# [sudo 필요] 방화벽 활성화
# ⚠️ 반드시 위에서 20022를 허용한 뒤 활성화할 것
sudo ufw --force enable
```

### 확인 방법 및 결과

```bash
# [일반 계정] 상태 확인
$ ufw status
Status: active

To              Action    From
──              ──────    ────
20022/tcp       ALLOW IN  Anywhere
15034/tcp       ALLOW IN  Anywhere
```

---

## 4. 계정 / 그룹 구성

### 왜 하는가
- 역할마다 계정을 분리해 한 계정이 탈취되어도 피해 범위를 제한합니다 (최소 권한 원칙).

### 구성표

| 계정 | 소속 그룹 | 역할 |
|------|-----------|------|
| `agent-admin` | agent-common, **agent-core** | 운영/관리, cron 실행 |
| `agent-dev`   | agent-common, **agent-core** | 개발, monitor.sh 작성 |
| `agent-test`  | agent-common (**core 없음**) | QA/테스트, api_keys 접근 불가 |

> 계정/그룹 생성은 시스템 수준 작업 → `sudo` 필요

### 설정 명령어

```bash
# [sudo 필요] 그룹 생성
sudo groupadd agent-common
sudo groupadd agent-core

# [sudo 필요] 계정 생성
# Ubuntu 24.04: useradd 사용 (-m: 홈 디렉토리 생성, -s: 기본 쉘 설정)
sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
sudo useradd -m -s /bin/bash -G agent-common            agent-test

# [sudo 필요] 비밀번호 설정
sudo passwd agent-admin
sudo passwd agent-dev
sudo passwd agent-test
```

### 확인 방법 및 결과

```bash
# [일반 계정] id 명령어로 확인
$ id agent-admin
uid=1001(agent-admin) groups=1001(agent-admin),1002(agent-common),1003(agent-core)

$ id agent-dev
uid=1002(agent-dev) groups=1002(agent-dev),1002(agent-common),1003(agent-core)

$ id agent-test
uid=1003(agent-test) groups=1003(agent-test),1002(agent-common)
# agent-core 없음 → api_keys 접근 불가 확인
```

---

## 5. 디렉토리 구조 및 권한

### 구조

```
$AGENT_HOME  (/home/agent-admin/agent-app)
├── upload_files/   ← 공용 폴더: agent-common 그룹 읽기/쓰기
├── api_keys/       ← 보안 폴더: agent-core 그룹만 접근
├── bin/            ← 스크립트 보관 (monitor.sh)
└── agent-app       ← 실행 파일

/var/log/agent-app/ ← 로그 폴더: agent-core 그룹만 접근
```

> `$AGENT_HOME` 은 agent-admin 홈 디렉토리 안 → **일반 계정으로 생성 가능**  
> `/var/log/agent-app` 은 시스템 디렉토리 → `sudo` 필요  
> `chown` 으로 다른 계정 소유로 변경 → `sudo` 필요

### 설정 명령어

```bash
# ── agent-admin 계정으로 전환 ──
su - agent-admin

# [일반 계정] AGENT_HOME 임시 설정
export AGENT_HOME=/home/agent-admin/agent-app

# [일반 계정] $AGENT_HOME 안 폴더 생성 (내 홈 디렉토리 → sudo 불필요)
mkdir -p $AGENT_HOME/upload_files
mkdir -p $AGENT_HOME/api_keys
mkdir -p $AGENT_HOME/bin

# [sudo 필요] /var/log 는 시스템 디렉토리
sudo mkdir -p /var/log/agent-app

# [sudo 필요] 소유자/그룹 변경
sudo chown -R agent-admin:agent-core $AGENT_HOME
sudo chown    agent-admin:agent-core /var/log/agent-app

# [일반 계정] 내 소유 디렉토리 권한 변경
chmod 750 $AGENT_HOME
chmod 770 $AGENT_HOME/upload_files
chmod 750 $AGENT_HOME/api_keys

# [sudo 필요] /var/log/agent-app 권한 변경
sudo chmod 770 /var/log/agent-app

# ACL 설정
# [일반 계정] 내 소유 디렉토리
setfacl -m  g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -dm g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -m  g:agent-core:rwx   $AGENT_HOME/api_keys
setfacl -dm g:agent-core:rwx   $AGENT_HOME/api_keys

# [sudo 필요] 시스템 디렉토리
sudo setfacl -m  g:agent-core:rwx /var/log/agent-app
sudo setfacl -dm g:agent-core:rwx /var/log/agent-app
```

### 확인 방법 및 결과

```bash
# [일반 계정]
$ ls -la $AGENT_HOME
drwxr-x---+ agent-admin agent-core  upload_files/   ← ACL 적용(+)
drwxr-x---+ agent-admin agent-core  api_keys/
drwxr-x---  agent-admin agent-core  bin/

$ getfacl $AGENT_HOME/upload_files
# owner: agent-admin
group:agent-common:rwx    ← common 그룹 접근 가능

$ getfacl $AGENT_HOME/api_keys
# owner: agent-admin
group:agent-core:rwx      ← core 그룹만 접근, agent-test 불가
```

---

## 6. 환경 변수 및 키 파일

### 왜 하는가
- 경로를 코드에 직접 쓰면(하드코딩) 경로 변경 시 모든 코드를 수정해야 합니다.
- 환경 변수로 관리하면 한 곳만 수정하면 됩니다.

> `~/.bashrc` 는 내 파일 → **일반 계정으로 수정 가능**  
> 키 파일은 `$AGENT_HOME/api_keys` 안 → **일반 계정으로 생성 가능**

### 설정 명령어

```bash
# ── agent-admin 계정에서 실행 ──

# [일반 계정] ~/.bashrc 에 환경변수 추가
echo 'export AGENT_HOME=/home/agent-admin/agent-app'                >> ~/.bashrc
echo 'export AGENT_PORT=15034'                                      >> ~/.bashrc
echo 'export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files'             >> ~/.bashrc
echo 'export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key'     >> ~/.bashrc
echo 'export AGENT_LOG_DIR=/var/log/agent-app'                     >> ~/.bashrc

# [일반 계정] 즉시 적용
source ~/.bashrc

# [일반 계정] 키 파일 생성 (내 소유 디렉토리 안)
echo 'agent_api_key_test' > $AGENT_HOME/api_keys/t_secret.key
chmod 640 $AGENT_HOME/api_keys/t_secret.key
```

### 확인 방법 및 결과

```bash
# [일반 계정]
$ printenv | grep AGENT
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app

$ cat $AGENT_HOME/api_keys/t_secret.key
agent_api_key_test
```

---

## 7. 애플리케이션 실행

### 실행 전 체크리스트

| 단계 | 확인 내용 | 실패 원인 |
|------|-----------|-----------|
| 1/5 | root가 아닌 일반 계정으로 실행 | root로 실행했을 때 |
| 2/5 | 환경 변수 5개 모두 설정됨 | `source ~/.bashrc` 안 했을 때 |
| 3/5 | `t_secret.key` 내용이 정확함 | 오타 또는 파일 없을 때 |
| 4/5 | 15034 포트가 비어있음 | 포트가 이미 사용 중일 때 |
| 5/5 | `/var/log/agent-app` 쓰기 가능 | 권한이 없을 때 |

### 실행 명령어

```bash
# ── agent-admin 계정에서 실행 ──

# [일반 계정] agent-app 파일 복사 및 실행 권한 부여
cp /tmp/agent-app $AGENT_HOME/agent-app
chmod +x $AGENT_HOME/agent-app

# [일반 계정] 앱 실행 (루트 실행 금지!)
$AGENT_HOME/agent-app
```

### 성공 시 출력

```
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
 ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
 ... All required Envs correct
[3/5] Checking Required Files             [OK]
 ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
 ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
 ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
```

> 앱을 켜둔 채로 **새 터미널을 열어** 다음 단계를 진행합니다.
> ```bash
> docker exec -it agent-lab /bin/bash
> su - agent-admin
> ```

### 포트 LISTEN 상태 확인

```bash
# [일반 계정] ss 명령어로 확인
$ ss -tulnp | grep 15034
tcp  LISTEN  0.0.0.0:15034  users:(("agent-app",pid=597,fd=4))

# ss 없을 경우 /proc/net/tcp 로 확인 (3ABA = 15034의 16진수)
$ grep 3ABA /proc/net/tcp
# 0A = LISTEN 상태 확인됨
```

---

## 8. monitor.sh 구현

### 파일 정보

| 항목 | 값 |
|------|----|
| 경로 | `$AGENT_HOME/bin/monitor.sh` |
| 소유자 | `agent-dev` |
| 그룹 | `agent-core` |
| 권한 | `750` (rwxr-x---) |
| 실행 계정 | `agent-admin` (agent-core 소속 → 그룹 실행권한 보유) |

### 배포 명령어

```bash
# ── agent-admin 계정에서 실행 ──

# [일반 계정] 파일 복사
cp /tmp/monitor.sh $AGENT_HOME/bin/monitor.sh

# [sudo 필요] 소유자를 agent-dev 로 변경 (다른 계정 소유 변경)
sudo chown agent-dev:agent-core $AGENT_HOME/bin/monitor.sh

# [sudo 필요] 소유자 변경 후 권한 설정
sudo chmod 750 $AGENT_HOME/bin/monitor.sh

# [일반 계정] 확인
$ ls -la $AGENT_HOME/bin/monitor.sh
-rwxr-x--- agent-dev agent-core monitor.sh
```

### 동작 흐름

```
monitor.sh 실행
    │
    ├─ [1단계] 프로세스 확인 ── 없으면 → [ERROR] + exit 1 (종료)
    │
    ├─ [2단계] 포트 확인 ────── 없으면 → [ERROR] + exit 1 (종료)
    │           ss 있으면 ss 사용, 없으면 /proc/net/tcp 사용
    │
    ├─ [3단계] 방화벽 확인 ──── 꺼져있으면 → [WARNING] (종료 안 함)
    │
    ├─ [4단계] 자원 수집
    │           ├─ CPU  : top -bn1 → idle 추출 → 100 - idle
    │           ├─ MEM  : free -k → used/total × 100
    │           └─ DISK : df / → 5번째 컬럼
    │
    ├─ [5단계] 임계값 경고 (종료 안 함)
    │           ├─ CPU  > 20% → [WARNING]
    │           ├─ MEM  > 10% → [WARNING]
    │           └─ DISK > 80% → [WARNING]
    │
    ├─ [6단계] 로그 기록
    │           └─ /var/log/agent-app/monitor.log 에 한 줄 추가
    │
    └─ [7단계] 로그 파일 관리
                └─ 10MB 초과 시 자동 rotate (최대 10개 보관)
```

### 로그 형식

```
[YYYY-MM-DD HH:MM:SS] PID:숫자 CPU:숫자% MEM:숫자% DISK_USED:숫자%
```

**실제 출력 예시:**

```
[2025-06-01 14:23:00] PID:597 CPU:10.0% MEM:6.3% DISK_USED:47%
[2025-06-01 14:24:00] [WARNING] CPU 사용률 높음: 35.2% (기준: 20%)
[2025-06-01 14:24:00] PID:597 CPU:35.2% MEM:6.4% DISK_USED:47%
```

### 수동 실행 확인

```bash
# [일반 계정] agent-admin 으로 직접 실행
$AGENT_HOME/bin/monitor.sh

# [일반 계정] 로그 확인
cat /var/log/agent-app/monitor.log
tail -f /var/log/agent-app/monitor.log
```

---

## 9. crontab 자동 실행 등록

### 왜 하는가
- crontab으로 등록하면 서버가 알아서 매분마다 자동 실행합니다.

> 도커에서는 **cron 서비스를 먼저 수동으로 시작**해야 합니다.  
> (도커는 systemd가 없어서 자동 시작이 안 됨)  
> crontab은 각 계정이 자신의 것을 직접 편집 → **일반 계정으로 가능**

### cron 서비스 시작 (도커 전용)

```bash
# [sudo 필요] 도커에서 cron 서비스 수동 시작
sudo service cron start

# 시작 확인
service cron status
```

### crontab 등록

```bash
# ── agent-admin 계정에서 실행 ──

# [일반 계정] 본인 crontab 편집
crontab -e
# 편집기가 열리면 아래 한 줄 추가 후 저장 (Ctrl+X → Y → Enter)

* * * * * /home/agent-admin/agent-app/bin/monitor.sh
```

**cron 표현식 설명:**

```
* * * * *
│ │ │ │ └── 요일
│ │ │ └──── 월
│ │ └────── 일
│ └──────── 시
└────────── 분
* = "모든" → 매분 실행
```

> ⚠️ crontab 안에는 반드시 **절대 경로**를 써야 합니다.  
> cron은 실행 시 현재 디렉토리를 모르기 때문입니다.

### 확인 방법 및 결과

```bash
# [일반 계정] 등록 확인
$ crontab -l
* * * * * /home/agent-admin/agent-app/bin/monitor.sh

# 1~2분 후 로그 자동 누적 확인
$ tail -5 /var/log/agent-app/monitor.log
[2025-06-01 14:27:00] PID:597 CPU:9.8%  MEM:8.3% DISK_USED:47%
[2025-06-01 14:28:00] PID:597 CPU:10.2% MEM:8.5% DISK_USED:47%
[2025-06-01 14:29:00] PID:597 CPU:11.1% MEM:8.4% DISK_USED:47%
```

---

## 10. 로그 파일 관리

### 방식: monitor.sh 내부 rotate 로직

| 항목 | 설정값 |
|------|--------|
| 최대 파일 크기 | 10MB |
| 보관 파일 수 | 최대 10개 |
| 파일 이름 | `monitor.log` → `monitor.log.1` ~ `.10` |
| 초과분 처리 | gzip 압축 후 삭제 |

### rotate 동작

```
[10MB 초과 감지]

rotate 전                rotate 후
─────────────────        ─────────────────────────
monitor.log (11MB)  →   monitor.log       ← 새 빈 파일
monitor.log.1       →   monitor.log.1     ← 방금 전 로그
monitor.log.2       →   monitor.log.2
...
monitor.log.9       →   monitor.log.9.gz  ← 압축됨
```

---

## 11. 증거 자료 체크리스트

| # | 확인 항목 | 상태 | 확인 명령어 | sudo |
|---|-----------|:----:|-------------|:----:|
| 1 | SSH 포트 20022 변경 | ✅ | `grep '^Port' /etc/ssh/sshd_config` | ❌ |
| 2 | Root 원격 로그인 차단 | ✅ | `grep 'PermitRootLogin' /etc/ssh/sshd_config` | ❌ |
| 3 | UFW 활성화 확인 | ✅ | `ufw status` | ❌ |
| 4 | 20022/tcp, 15034/tcp만 허용 | ✅ | `ufw status` | ❌ |
| 5 | 계정 3개 생성 확인 | ✅ | `id agent-admin && id agent-dev && id agent-test` | ❌ |
| 6 | 그룹 2개 생성 확인 | ✅ | `cat /etc/group \| grep agent` | ❌ |
| 7 | 디렉토리 구조 확인 | ✅ | `ls -la $AGENT_HOME` | ❌ |
| 8 | ACL 권한 확인 | ✅ | `getfacl $AGENT_HOME/upload_files` | ❌ |
| 9 | 환경 변수 설정 확인 | ✅ | `printenv \| grep AGENT` | ❌ |
| 10 | 키 파일 내용 확인 | ✅ | `cat $AGENT_HOME/api_keys/t_secret.key` | ❌ |
| 11 | Boot Sequence 5단계 [OK] | ✅ | `$AGENT_HOME/agent-app` 실행 출력 | ❌ |
| 12 | Agent READY 출력 확인 | ✅ | 앱 실행 로그 | ❌ |
| 13 | 15034 포트 LISTEN 확인 | ✅ | `ss -tulnp \| grep 15034` | ❌ |
| 14 | monitor.sh 권한 확인 | ✅ | `ls -la $AGENT_HOME/bin/monitor.sh` | ❌ |
| 15 | monitor.sh 수동 실행 확인 | ✅ | `$AGENT_HOME/bin/monitor.sh` | ❌ |
| 16 | monitor.log 기록 확인 | ✅ | `tail /var/log/agent-app/monitor.log` | ❌ |
| 17 | crontab 매분 등록 확인 | ✅ | `crontab -l` | ❌ |
| 18 | 1분 후 로그 자동 누적 확인 | ✅ | `watch -n 30 tail /var/log/agent-app/monitor.log` | ❌ |

> 📌 확인 명령어는 전부 **일반 계정**으로 실행 가능합니다.

---

## 12. 트러블슈팅

### 패키지 설치가 안 될 때

```bash
# apt update 먼저 실행
apt-get update
apt-get install -y openssh-server ufw cron acl iproute2 procps
```

### 앱 실행 시 `[FAIL]` 이 날 때

```bash
# 1단계 FAIL: root로 실행했을 때
# → agent-admin 으로 전환 후 실행
su - agent-admin
$AGENT_HOME/agent-app

# 2단계 FAIL: 환경변수 없을 때
# → bashrc 다시 로드
source ~/.bashrc
printenv | grep AGENT   # 확인

# 3단계 FAIL: 키 파일 내용이 다를 때
# → 파일 내용 확인 (공백, 줄바꿈 주의)
cat $AGENT_HOME/api_keys/t_secret.key
# 정확히 "agent_api_key_test" 한 줄만 있어야 함

# 5단계 FAIL: 로그 폴더 권한 없을 때
sudo chmod 770 /var/log/agent-app
sudo chown agent-admin:agent-core /var/log/agent-app
```

### cron이 실행이 안 될 때

```bash
# 도커에서는 cron 서비스를 직접 시작해야 함
sudo service cron start

# cron 실행 중인지 확인
service cron status

# 로그가 쌓이는지 확인 (1~2분 대기)
watch -n 10 wc -l /var/log/agent-app/monitor.log
```

### UFW 설정이 안 될 때

```bash
# 도커 컨테이너를 --privileged 없이 실행했을 때 발생
# → 컨테이너를 새로 만들어야 함 (호스트에서 실행)
docker stop agent-lab
docker rm agent-lab

docker run -it \
  --name agent-lab \
  --privileged \
  -v $(pwd)/agent-app:/tmp/agent-app \
  -v $(pwd)/monitor.sh:/tmp/monitor.sh \
  ubuntu:24.04 \
  /bin/bash
```

### 컨테이너 재시작 후 서비스가 꺼져있을 때

```bash
# 도커는 재시작 시 서비스가 초기화됨
# 아래 명령어로 필요한 서비스 다시 시작
sudo mkdir -p /run/sshd && sudo service ssh start
sudo service cron start
```

---

*Ubuntu 24.04 LTS Docker 환경 기준으로 작성되었습니다.*
