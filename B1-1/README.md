# Linux 시스템 보안 및 관제 자동화 과제

> **Ubuntu 24.04 LTS (OrbStack VM)** 환경에서  
> Agent App을 안전하게 설치하고 시스템 상태를 자동으로 감시하는 환경을 구성한 과제입니다.

---

## 📁 제출 산출물

```
📄 README.md          ← 요구사항 수행 내역서 (이 파일)
📜 monitor.sh         ← 시스템 관제 자동화 스크립트
```

---

## 📋 목차

1. [전체 구성 개요](#1-전체-구성-개요)
2. [패키지 설치](#2-패키지-설치)
3. [SSH 보안 설정](#3-ssh-보안-설정)
4. [방화벽UFW-설정](#4-방화벽ufw-설정)
5. [계정--그룹-구성](#5-계정--그룹-구성)
6. [디렉토리-구조-및-권한](#6-디렉토리-구조-및-권한)
7. [환경-변수-및-키-파일](#7-환경-변수-및-키-파일)
8. [애플리케이션-실행](#8-애플리케이션-실행)
9. [monitorsh-구현](#9-monitorsh-구현)
10. [crontab-자동-실행-등록](#10-crontab-자동-실행-등록)
11. [로그-파일-관리](#11-로그-파일-관리)
12. [증거-자료-체크리스트](#12-증거-자료-체크리스트)
13. [트러블슈팅](#13-트러블슈팅)

---

## 1. 전체 구성 개요

### 이 과제가 하는 일

> "리눅스 서버 환경을 안전하게 설정하고, 앱을 실행한 뒤, 앱이 잘 돌아가는지 자동으로 감시하는 시스템을 만드는 것"

```
[보안 기반]          [실행 환경]            [자동 감시]
SSH 포트 변경   →   계정/폴더 구성    →   monitor.sh 작성
방화벽 설정     →   환경 변수 등록    →   cron 자동 실행
Root 접속 차단  →   앱 실행 확인      →   로그 누적 확인
```

### 계정 전략 — sudo 없이 작업하는 방법

> `sudo` 는 "일반 계정이 root 권한을 잠깐 빌리는 것"입니다.  
> root로 직접 전환(`su -`)하면 처음부터 root이기 때문에 `sudo` 가 필요 없습니다.

```
VM 로그인 (ubuntu 계정)
    │
    su -   ← root로 전환
    │      (이 아래는 전부 sudo 없이 실행 가능)
    │
    ├── STEP 1. 패키지 설치
    ├── STEP 2. SSH 설정
    ├── STEP 3. UFW 방화벽 설정
    ├── STEP 4. 계정/그룹 생성
    └── STEP 5. /var/log/agent-app 생성 및 권한 설정
         │
         su - agent-admin   ← agent-admin으로 전환
         │   (이 아래는 agent-admin 권한으로 실행)
         │
         ├── STEP 6.  폴더 구조 생성
         ├── STEP 7.  환경변수 / 키 파일 설정
         ├── STEP 8.  앱 실행        ← 터미널 1 유지
         │
         새 터미널 열기 (orb shell agent-lab → su - agent-admin)
         │
         ├── STEP 9.  monitor.sh 배포 및 권한 설정
         ├── STEP 10. monitor.sh 수동 실행 테스트
         ├── STEP 11. crontab 등록
         └── STEP 12. 자동 실행 확인
```

---

## 2. 패키지 설치

### 개념 — 패키지란?

> 리눅스에서 프로그램을 설치하는 단위입니다.  
> `apt-get install` 은 마트에서 장을 보는 것과 같습니다.  
> `apt-get update` 는 마트의 상품 목록을 최신화하는 것입니다.  
> update를 먼저 하지 않으면 오래된 목록으로 설치해서 실패할 수 있습니다.

### 설치 명령어

```bash
# root로 전환
su -

# 패키지 목록 최신화
apt-get update

# 필수 패키지 설치
apt-get install -y \
  openssh-server \
  ufw \
  cron \
  acl \
  iproute2 \
  procps \
  vim
```

### 설치하는 패키지 설명

| 패키지 | 용도 |
|--------|------|
| `openssh-server` | SSH 서버 (원격 접속) |
| `ufw` | 방화벽 |
| `cron` | 자동 실행 스케줄러 |
| `acl` | 세밀한 파일 권한 설정 (setfacl) |
| `iproute2` | 포트 확인 명령어 (ss) |
| `procps` | 프로세스 확인 명령어 (top, free, ps) |
| `vim` | 텍스트 편집기 |

### 확인

```bash
which sshd ufw crontab setfacl ss top
# 각 명령어의 경로가 출력되면 설치 성공
```

---

## 3. SSH 보안 설정

### 개념 — SSH란?

> SSH(Secure Shell)는 인터넷을 통해 서버에 **원격으로 접속하는 방법**입니다.  
> 집 현관문에 비유할 수 있습니다.

### 개념 — 왜 포트를 바꾸나?

> 서버를 인터넷에 연결하면 전 세계 해킹 프로그램들이 기본 포트인 **22번**으로  
> 24시간 자동 침입 시도를 합니다.  
> 포트를 **20022**로 바꾸면 이 자동화 공격 대부분을 피할 수 있습니다.
>
> ```
> 포트 22    → 봇이 매일 수천 번 자동 시도
> 포트 20022 → 봇이 스캔 안 함 → 공격 시도 자체가 줄어듦
> ```

### 개념 — 왜 root 로그인을 막나?

> root는 서버의 **모든 권한을 가진 최고 관리자 계정**입니다.  
> root로 직접 로그인이 가능하면 비밀번호 하나만 뚫리면 서버 전체가 장악됩니다.
>
> ```
> root 허용 시: 비밀번호 1개 → 서버 전체 장악
> root 차단 시: 일반 계정 비밀번호 + root 권한 획득 방법 → 2단계 필요
> ```

### 개념 — 설정 방법 (sed vs 별도 파일)

> SSH 설정을 바꾸는 방법은 두 가지가 있습니다.
>
> **방법 A — sed로 기존 파일 수정**
> ```bash
> sed -i 's/^#Port 22/Port 20022/' /etc/ssh/sshd_config
> # 문제점: sshd_config에 'Port' 라인 자체가 없으면 아무것도 안 바뀜
> ```
>
> **방법 B — 별도 설정 파일 추가 (권장)**
> ```
> Ubuntu 24.04는 /etc/ssh/sshd_config.d/ 폴더 안의 설정이
> 기본 sshd_config보다 우선 적용됩니다.
> 여기에 새 파일을 만들면 기존 파일 상태와 무관하게 확실히 적용됩니다.
> ```
>
> 이 과제에서는 **방법 B**를 사용합니다. (가장 안정적)

### 설정 명령어

```bash
# root에서 실행

# /etc/ssh/sshd_config.d/ 에 보안 설정 파일 추가
# (기본 sshd_config보다 우선 적용되므로 가장 확실)
cat > /etc/ssh/sshd_config.d/99-agent-security.conf << 'CONF'
Port 20022
PermitRootLogin no
CONF
chmod 644 /etc/ssh/sshd_config.d/99-agent-security.conf

# 설정 문법 검사 (문제 있으면 에러 출력)
sshd -t

# 설정 적용 (재시작해야 반영됨)
systemctl restart ssh

# 부팅 시 자동 시작 등록
systemctl enable ssh
```

### 확인 방법 및 결과

```bash
# 적용된 설정 확인 (실제 적용값을 보여줌)
$ sshd -T | grep -E '^port|^permitrootlogin'
port 20022
permitrootlogin no

# 포트 리슨 상태 확인
$ ss -tulnp | grep sshd
tcp  LISTEN  0.0.0.0:20022   ← 20022가 보이면 성공
tcp  LISTEN     [::]:20022

# 서비스 상태 확인
$ systemctl status ssh
Active: active (running)   ← 실행 중
```

> 💡 `sshd -T` 는 주석이든 별도 파일이든 상관없이  
> **실제로 적용되는 최종 설정값**을 보여줍니다. 확인에 가장 확실한 명령어입니다.

---

## 4. 방화벽(UFW) 설정

### 개념 — 방화벽이란?

> 방화벽은 서버 앞에 서있는 **경비원**입니다.  
> 허가된 문(포트)으로만 들어올 수 있습니다.
>
> ```
> 방화벽 없을 때          방화벽 있을 때
> ────────────────        ────────────────
> 모든 포트 → 누구나      20022번 → SSH만
> 접근 가능               15034번 → 앱만
>                         나머지  → 전부 차단
> ```

### 개념 — UFW란?

> UFW(Uncomplicated Firewall)는 리눅스 방화벽을 **쉽게 설정하는 도구**입니다.  
> 원래 리눅스 방화벽(iptables)은 명령어가 복잡한데, UFW가 이를 단순하게 만들어줍니다.

### 개념 — 기본 정책이란?

> `default deny incoming` 은 "아무도 들어오지 마" 라는 기본 규칙입니다.  
> 그 다음 `allow` 로 예외를 추가하는 방식입니다.  
> 허용 목록(whitelist) 방식이라서 명시적으로 허용하지 않은 건 전부 차단됩니다.

### 설정 명령어

```bash
# root에서 실행

# 기본 정책: 들어오는 건 전부 거부, 나가는 건 허용
ufw default deny incoming
ufw default allow outgoing

# 필요한 포트만 열기
ufw allow 20022/tcp   # SSH
ufw allow 15034/tcp   # Agent App

# 방화벽 활성화
# ⚠️ 반드시 위에서 20022를 허용한 뒤 활성화
#    순서가 바뀌면 SSH 접속이 차단됨
ufw --force enable
```

### 확인 방법 및 결과

```bash
$ ufw status
Status: active

To              Action    From
──              ──────    ────
20022/tcp       ALLOW IN  Anywhere
15034/tcp       ALLOW IN  Anywhere
```

---

## 5. 계정 / 그룹 구성

### 개념 — 왜 계정을 여러 개 만드나?

> 모든 작업을 하나의 계정으로 하면, 그 계정이 탈취됐을 때 모든 게 노출됩니다.  
> 역할마다 계정을 분리하면 하나가 털려도 피해 범위가 제한됩니다.  
> 이걸 **최소 권한 원칙**이라고 합니다.
>
> ```
> 권한이 넓을수록 → 사고 났을 때 피해 범위가 넓어짐
> 권한이 좁을수록 → 사고 났을 때 피해 범위가 좁아짐
> ```

### 개념 — 그룹이란?

> 그룹은 여러 계정을 묶어서 **같은 권한을 한 번에 부여**하는 방법입니다.  
> 회사의 부서 개념과 같습니다.
>
> ```
> agent-common 그룹 → admin, dev, test 모두 소속 → 공용 폴더 접근 가능
> agent-core 그룹   → admin, dev만 소속           → 비밀 폴더 접근 가능
>                      (test는 제외!)
> ```

### 구성표

| 계정 | 소속 그룹 | 역할 |
|------|-----------|------|
| `agent-admin` | agent-common, **agent-core** | 운영/관리, cron 실행 |
| `agent-dev`   | agent-common, **agent-core** | 개발, monitor.sh 작성 |
| `agent-test`  | agent-common (**core 없음**) | QA/테스트, api_keys 접근 불가 |

### 설정 명령어

```bash
# root에서 실행

# 그룹 생성
groupadd agent-common
groupadd agent-core

# 계정 생성
# -m : 홈 디렉토리 자동 생성
# -s : 기본 쉘 설정 (bash 사용)
# -G : 소속 그룹 지정
useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
useradd -m -s /bin/bash -G agent-common            agent-test

# 비밀번호 설정
passwd agent-admin
passwd agent-dev
passwd agent-test
```

### 확인 방법 및 결과

```bash
$ id agent-admin
uid=1001(agent-admin) groups=1001(agent-admin),1002(agent-common),1003(agent-core)

$ id agent-dev
uid=1002(agent-dev) groups=1002(agent-dev),1002(agent-common),1003(agent-core)

$ id agent-test
uid=1003(agent-test) groups=1003(agent-test),1002(agent-common)
# agent-core 없음 → api_keys 접근 불가
```

---

## 6. 디렉토리 구조 및 권한

### 개념 — 리눅스 권한이란?

> 리눅스의 모든 파일/폴더는 **소유자, 그룹, 나머지** 세 가지에 대해  
> **읽기(r), 쓰기(w), 실행(x)** 권한을 각각 설정할 수 있습니다.
>
> ```
> drwxr-x---
> │├┤├┤├┤
> │ │  │  └── 나머지(others): --- = 접근 불가
> │ │  └───── 그룹(group)   : r-x = 읽기+실행만
> │ └──────── 소유자(owner) : rwx = 읽기+쓰기+실행
> └────────── d = 디렉토리
>
> 750 = rwxr-x--- (숫자로 표현)
>   7 = rwx (소유자)
>   5 = r-x (그룹)
>   0 = --- (나머지)
> ```

### 개념 — ACL이란?

> 기본 권한은 소유자/그룹/나머지 세 가지만 설정 가능합니다.  
> ACL(Access Control List)은 **더 세밀하게** "이 그룹은 읽기만, 저 그룹은 읽기+쓰기" 처럼  
> 특정 그룹/계정에 개별 권한을 부여할 수 있는 기능입니다.
>
> ```bash
> setfacl -m g:agent-common:rwx 폴더
> # g:그룹명:권한 = 이 그룹에게 이 권한을 줌
> # -d = 기본(default) ACL = 이 폴더 안에 새로 만든 파일에도 자동 적용
> ```
>
> ACL이 적용된 폴더는 `ls -la` 에서 권한 뒤에 `+` 가 붙습니다.
> ```
> drwxr-x---+   ← + 가 있으면 ACL 적용됨
> ```

### 폴더 구조

```
$AGENT_HOME  (/home/agent-admin/agent-app)
├── upload_files/   ← 공용 폴더: agent-common 그룹 읽기/쓰기
├── api_keys/       ← 보안 폴더: agent-core 그룹만 접근
├── bin/            ← 스크립트 보관 (monitor.sh)
└── agent-app       ← 실행 파일

/var/log/agent-app/ ← 로그 폴더: agent-core 그룹만 접근
```

### STEP A — agent-admin으로 폴더 생성

```bash
# agent-admin으로 전환
su - agent-admin

# 환경변수 임시 설정 (나중에 영구 등록)
export AGENT_HOME=/home/agent-admin/agent-app

# 폴더 생성 (내 홈 디렉토리 안 → root 불필요)
mkdir -p $AGENT_HOME/upload_files
mkdir -p $AGENT_HOME/api_keys
mkdir -p $AGENT_HOME/bin

# 권한 설정 (내 소유 폴더 → root 불필요)
chmod 750 $AGENT_HOME
chmod 770 $AGENT_HOME/upload_files
chmod 750 $AGENT_HOME/api_keys
chmod 750 $AGENT_HOME/bin
```

### STEP B — root에서 소유 그룹 변경 + 로그 폴더 설정

> ⚠️ 폴더를 만들면 소유 그룹이 자동으로 `agent-admin`(개인 그룹)이 됩니다.  
> 요구사항대로 `agent-core` 로 바꾸려면 **root 권한의 chown** 이 필요합니다.  
> (일반 계정은 다른 그룹으로 소유권을 넘길 수 없음)

> 💡 `su -` 로 root 전환이 안 되면(비밀번호 없음 등) 처음 만든 계정으로 나가서  
> `sudo` 를 쓰거나, 아래처럼 한 번에 실행할 수 있습니다.
> ```bash
> # agent-admin 셸에서 빠져나오지 않고 sudo로 실행하는 방법
> # (단, agent-admin에 sudo 권한이 있어야 함. 보통은 처음 만든 계정에 있음)
> ```

```bash
# root로 전환 (OrbStack은 보통 비밀번호 없이 su - 가능,
#  안 되면 exit로 처음 계정에 나가서 sudo 사용)
su -

# ① $AGENT_HOME 전체의 소유 그룹을 agent-core 로 변경 (가장 중요!)
chown -R agent-admin:agent-core /home/agent-admin/agent-app

# ② 로그 폴더 생성 (/var/log 는 시스템 폴더 → root만 가능)
mkdir -p /var/log/agent-app
chown agent-admin:agent-core /var/log/agent-app
chmod 770 /var/log/agent-app

# ③ 로그 폴더 ACL (agent-core 그룹만 접근)
setfacl -m  g:agent-core:rwx /var/log/agent-app
setfacl -dm g:agent-core:rwx /var/log/agent-app

# root에서 나오기 (agent-admin 셸로 복귀)
exit
```

### STEP C — agent-admin으로 ACL 설정

```bash
# agent-admin 셸로 돌아온 상태
# 혹시 AGENT_HOME 이 비어있을 수 있으니 다시 설정 (안전장치)
export AGENT_HOME=/home/agent-admin/agent-app

# chown으로 소유 그룹이 agent-core가 됐으므로 이제 ACL 설정

# upload_files: agent-common 그룹 읽기/쓰기 허용
setfacl -m  g:agent-common:rwx $AGENT_HOME/upload_files
setfacl -dm g:agent-common:rwx $AGENT_HOME/upload_files

# api_keys: agent-core 그룹만 접근
setfacl -m  g:agent-core:rwx $AGENT_HOME/api_keys
setfacl -dm g:agent-core:rwx $AGENT_HOME/api_keys
```

### 확인 방법 및 결과

```bash
$ ls -la $AGENT_HOME
drwxr-x---+ agent-admin agent-core  upload_files/   ← ACL 적용(+)
drwxr-x---+ agent-admin agent-core  api_keys/
drwxr-x---  agent-admin agent-core  bin/

$ getfacl $AGENT_HOME/upload_files
# owner: agent-admin
# group: agent-core
group:agent-common:rwx    ← common 그룹 접근 가능

$ getfacl $AGENT_HOME/api_keys
# owner: agent-admin
group:agent-core:rwx      ← core 그룹만 접근, agent-test 불가
```

---

## 7. 환경 변수 및 키 파일

### 개념 — 환경 변수란?

> 프로그램이 실행될 때 참고하는 **설정값 모음**입니다.  
> 전화번호를 이름으로 저장해두는 것처럼, 자주 쓰는 경로를 이름으로 저장합니다.
>
> ```bash
> # 하드코딩 (나쁜 방식)
> python3 /home/agent-admin/agent-app/agent_app.py
> # 경로가 바뀌면 모든 코드를 수정해야 함
>
> # 환경변수 사용 (좋은 방식)
> python3 $AGENT_HOME/agent_app.py
> # AGENT_HOME 값만 바꾸면 모든 곳에 반영됨
> ```

### 개념 — ~/.bashrc란?

> 터미널에 로그인할 때마다 **자동으로 실행되는 설정 파일**입니다.  
> 여기에 환경변수를 추가하면 로그인할 때마다 자동으로 적용됩니다.  
> `source ~/.bashrc` 는 로그아웃/로그인 없이 지금 바로 적용하는 명령어입니다.

### 설정 명령어

```bash
# agent-admin 계정에서 실행

# ~/.bashrc 에 환경변수 추가
# >> : 파일 끝에 추가 (덮어쓰지 않음)
# ⚠️ AGENT_KEY_PATH 는 파일이 아니라 "폴더(api_keys)까지만" 지정해야 함
#    (앱이 그 폴더 안에서 secret.key 파일을 찾는 구조)
echo 'export AGENT_HOME=/home/agent-admin/agent-app'                >> ~/.bashrc
echo 'export AGENT_PORT=15034'                                      >> ~/.bashrc
echo 'export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files'             >> ~/.bashrc
echo 'export AGENT_KEY_PATH=$AGENT_HOME/api_keys'                   >> ~/.bashrc
echo 'export AGENT_LOG_DIR=/var/log/agent-app'                     >> ~/.bashrc

# 즉시 적용
source ~/.bashrc

# 키 파일 생성 (내 소유 폴더 안 → root 불필요)
# ⚠️ 파일 이름은 secret.key (t_ 없음), 내용은 정확히 "agent_api_key_test"
echo -n 'agent_api_key_test' > $AGENT_HOME/api_keys/secret.key
chmod 640 $AGENT_HOME/api_keys/secret.key
```

### 확인 방법 및 결과

```bash
$ printenv | grep AGENT
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app

$ cat $AGENT_HOME/api_keys/secret.key
agent_api_key_test   ← 정확히 이 내용만 있어야 함

$ ls -la $AGENT_HOME/api_keys/
-rw-r----- agent-admin agent-core  secret.key
```

---

## 8. 애플리케이션 실행

### 개념 — Boot Sequence란?

> 앱이 시작할 때 필요한 조건들을 순서대로 체크하는 과정입니다.  
> 하나라도 실패하면 그 아래는 전부 건너뜁니다.  
> 마치 자동차 시동 시 엔진, 연료, 배터리를 순서대로 점검하는 것과 같습니다.

### 실행 전 체크리스트

| 단계 | 확인 내용 | 실패 원인 |
|------|-----------|-----------|
| 1/5 | root가 아닌 일반 계정으로 실행 | root로 실행했을 때 |
| 2/5 | 환경 변수 5개 모두 설정됨 | `source ~/.bashrc` 안 했을 때 |
| 3/5 | `secret.key` 내용이 정확함 | 오타 또는 파일 없을 때 |
| 4/5 | 15034 포트가 비어있음 | 포트가 이미 사용 중일 때 |
| 5/5 | `/var/log/agent-app` 쓰기 가능 | 권한이 없을 때 |

### 개념 — 제공된 앱 파일이 2개인 이유

> 제공된 앱은 CPU 종류에 따라 두 가지 버전이 있습니다.
> ```
> agent-app-linux-x86      ← Intel/AMD CPU (인텔 맥) ✅ 우리 환경
> agent-app-linux-arm64    ← Apple Silicon (M칩 맥)
> ```
> 이 환경은 **인텔 맥 + amd64 VM** 이므로 **x86** 버전을 사용합니다.
>
> 내 VM의 아키텍처 확인:
> ```bash
> uname -m
> # x86_64 (= amd64)  → agent-app-linux-x86 사용 ✅
> # aarch64 (= arm64) → agent-app-linux-arm64 사용
> ```

### 개념 — OrbStack의 파일 공유 방식

> OrbStack은 VM 안에서 **Mac의 모든 폴더를 `/mnt/mac` 경로로 볼 수 있습니다.**
> ```
> Mac의 /Users/내이름/Downloads
>          ↓ (자동 연결)
> VM의 /mnt/mac/Users/내이름/Downloads
> ```
> 그래서 별도 전송 명령어 없이 VM 안에서 Mac 파일을 직접 복사할 수 있습니다.  
> (`orb push` 는 환경에 따라 동작하지 않을 수 있어 이 방식을 권장합니다.)

### 파일 전송 방법 (Mac → VM)

```bash
# ── VM 안에서 실행 (orb shell agent-lab 로 접속한 상태) ──

# 1. Mac 사용자 이름 확인 (Mac 폴더 경로에 필요)
ls /mnt/mac/Users/
# 본인 Mac 계정 폴더가 보임 (예: john)

# 2. 파일이 있는 위치 확인 (예: Downloads 폴더)
ls /mnt/mac/Users/본인맥이름/Downloads/
# agent-app-linux-x86  monitor.sh  가 보여야 함

# 3. /tmp 로 복사 (x86 버전을 agent-app 이름으로 저장)
cp /mnt/mac/Users/본인맥이름/Downloads/agent-app-linux-x86 /tmp/agent-app
cp /mnt/mac/Users/본인맥이름/Downloads/monitor.sh          /tmp/monitor.sh

# 4. 복사 확인
ls -la /tmp/agent-app /tmp/monitor.sh
```

> 💡 `agent-app-linux-x86` 를 `/tmp/agent-app` 으로 복사하면  
> VM 안에서는 `agent-app` 이라는 이름으로 저장됩니다.

> ⚠️ `/tmp` 에 두는 이유: 누구나 쓸 수 있는 임시 폴더이기 때문입니다.  
> `/agent-app` 처럼 루트(/) 바로 아래는 root 전용이라 복사가 안 됩니다.

### 실행 명령어

```bash
# agent-admin 계정에서 실행
# (환경변수가 적용됐는지 먼저 확인)
echo $AGENT_HOME
# /home/agent-admin/agent-app 가 나와야 함
# 비어있으면: source ~/.bashrc

# 파일 복사 및 실행 권한 부여
cp /tmp/agent-app $AGENT_HOME/agent-app
chmod +x $AGENT_HOME/agent-app

# 앱 실행 (루트 실행 금지!)
$AGENT_HOME/agent-app
```

### 성공 시 출력

```
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
[2/5] Verifying Environment Variables     [OK]
[3/5] Checking Required Files             [OK]
[4/5] Checking Port Availability          [OK]
[5/5] Verifying Log Permission            [OK]
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
```

> 앱을 켜둔 채로 **새 터미널을 열어** 다음 단계를 진행합니다.
> ```bash
> # Mac 터미널에서 새 탭/창을 열고 (agent-lab은 본인 VM 이름)
> orb shell agent-lab
> su - agent-admin
> source ~/.bashrc
> ```

### 포트 확인

```bash
$ ss -tulnp | grep 15034
tcp  LISTEN  0.0.0.0:15034  users:(("agent-app",pid=597,fd=4))
```

---

## 9. monitor.sh 구현

### 개념 — 왜 monitor.sh가 필요한가?

> 앱이 갑자기 꺼지거나 CPU가 치솟아도, 사람이 직접 보고 있지 않으면 모릅니다.  
> monitor.sh는 매분마다 자동으로 상태를 확인하고 기록해서  
> 나중에 "언제 문제가 생겼는지" 추적할 수 있게 합니다.

### 파일 정보

| 항목 | 값 |
|------|----|
| 경로 | `$AGENT_HOME/bin/monitor.sh` |
| 소유자 | `agent-dev` |
| 그룹 | `agent-core` |
| 권한 | `750` (rwxr-x---) |
| 실행 계정 | `agent-admin` (agent-core 소속 → 그룹 실행권한 보유) |

> 권한 750의 의미:
> ```
> 7(rwx) → agent-dev   : 읽기+쓰기+실행 가능
> 5(r-x) → agent-core  : 읽기+실행만 가능 (쓰기 불가)
> 0(---) → 나머지       : 아무것도 못 함
> agent-admin은 agent-core 소속이므로 실행(x) 가능
> ```

### 배포 명령어

```bash
# agent-admin에서 파일 복사
cp /tmp/monitor.sh $AGENT_HOME/bin/monitor.sh

# root로 전환해서 소유자/권한 변경
# (다른 계정 소유로 변경은 root만 가능)
su -
chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
chmod 750 /home/agent-admin/agent-app/bin/monitor.sh

# root에서 나오기
exit

# 확인
$ ls -la $AGENT_HOME/bin/monitor.sh
-rwxr-x--- agent-dev agent-core monitor.sh
```

### 동작 흐름

```
monitor.sh 실행
    │
    ├─ [1단계] 프로세스 확인
    │   pgrep -x 로 agent-app 프로세스 찾기
    │   (-x: 이름 정확히 일치 → monitor.sh 자기 자신 오인 방지)
    │   없으면 → [ERROR] 로그 + exit 1 (즉시 종료)
    │
    ├─ [2단계] 포트 확인
    │   ss 또는 /proc/net/tcp 로 15034 포트 확인
    │   없으면 → [ERROR] 로그 + exit 1 (즉시 종료)
    │
    ├─ [3단계] 방화벽 확인
    │   ufw status 로 활성화 여부 확인
    │   꺼져있으면 → [WARNING] 출력 (종료 안 함)
    │
    ├─ [4단계] 자원 수집
    │   CPU  : top -bn1 → idle 값 추출 → 100 - idle = 사용률
    │   MEM  : free -k  → used/total × 100
    │   DISK : df /     → Use% 컬럼 추출
    │
    ├─ [5단계] 임계값 경고
    │   CPU  > 20% → [WARNING] (종료 안 함)
    │   MEM  > 10% → [WARNING] (종료 안 함)
    │   DISK > 80% → [WARNING] (종료 안 함)
    │
    ├─ [6단계] 로그 기록
    │   /var/log/agent-app/monitor.log 에 한 줄 추가 (>>)
    │
    └─ [7단계] 로그 파일 관리
        10MB 초과 시 자동 rotate (최대 10개 보관)
```

### 개념 — exit 1 vs WARNING만 출력하는 이유

> 프로세스가 없거나 포트가 안 열린 건 **서비스가 완전히 중단**된 상황입니다.  
> 이 경우 CPU나 메모리를 측정해도 의미가 없어서 즉시 종료(exit 1)합니다.
>
> 방화벽이 꺼진 건 **보안 문제**지만 앱 자체는 돌아가고 있습니다.  
> 경고만 남기고 계속 측정해서 로그를 쌓습니다.

### 로그 형식

```
[YYYY-MM-DD HH:MM:SS] PID:숫자 CPU:숫자% MEM:숫자% DISK_USED:숫자%
```

**실제 출력 예시:**

```
[2025-06-01 14:23:00] PID:597 CPU:10.0% MEM:6.3% DISK_USED:47%
[2025-06-01 14:24:00] [WARNING] CPU 사용률 높음: 35.2% (기준: 20%)
[2025-06-01 14:24:00] PID:597 CPU:35.2% MEM:6.4% DISK_USED:47%
[2025-06-01 14:25:00] PID:597 CPU:8.1%  MEM:6.3% DISK_USED:47%
```

### 수동 실행 확인

```bash
# agent-admin에서 실행
$AGENT_HOME/bin/monitor.sh

# 로그 확인
cat /var/log/agent-app/monitor.log
tail -f /var/log/agent-app/monitor.log
```

---

## 10. crontab 자동 실행 등록

### 개념 — crontab이란?

> 리눅스의 **자동 실행 스케줄러**입니다.  
> "이 명령어를 매분마다 실행해줘" 라고 등록해두면 서버가 알아서 실행합니다.

### 개념 — cron 표현식이란?

> ```
> * * * * * 실행할명령어
> │ │ │ │ └── 요일 (0=일, 1=월 ... 6=토)
> │ │ │ └──── 월   (1~12)
> │ │ └────── 일   (1~31)
> │ └──────── 시   (0~23)
> └────────── 분   (0~59)
>
> * = "모든" 이라는 뜻
> * * * * * = 매분 매시 매일 = 매분 실행
> ```

### 개념 — crontab에 절대경로를 써야 하는 이유

> cron은 실행할 때 현재 디렉토리가 어딘지 모릅니다.  
> 그래서 `./monitor.sh` 같은 상대경로는 찾지 못합니다.  
> 반드시 `/home/agent-admin/...` 처럼 전체 경로를 써야 합니다.

### cron 서비스 상태 확인

```bash
# VM은 cron이 자동으로 실행됨
$ systemctl status cron
Active: active (running)   ← 이미 실행 중
```

### crontab 등록

```bash
# agent-admin 계정에서 실행

# 본인 crontab 편집 (본인 것이므로 root 불필요)
crontab -e
# 처음 실행 시 편집기 선택 → 1번(nano) 권장

# 아래 한 줄 추가 후 저장
# nano 저장: Ctrl+X → Y → Enter
* * * * * /home/agent-admin/agent-app/bin/monitor.sh
```

### 확인 방법 및 결과

```bash
# 등록 확인
$ crontab -l
* * * * * /home/agent-admin/agent-app/bin/monitor.sh

# 1~2분 후 로그 자동 누적 확인
$ tail -5 /var/log/agent-app/monitor.log
[2025-06-01 14:27:00] PID:597 CPU:9.8%  MEM:8.3% DISK_USED:47%
[2025-06-01 14:28:00] PID:597 CPU:10.2% MEM:8.5% DISK_USED:47%
[2025-06-01 14:29:00] PID:597 CPU:11.1% MEM:8.4% DISK_USED:47%
# 매분 한 줄씩 자동으로 추가됨
```

> ⚠️ **중요 전제: 앱(agent-app)이 켜져 있어야 정상 로그가 쌓입니다.**  
> monitor.sh는 앱이 꺼져 있으면 1단계에서 ERROR를 남기고 종료(exit 1)하므로,  
> 로그 누적을 확인하려면 8번 단계에서 실행한 앱이 계속 떠 있어야 합니다.
>
> 만약 로그에 `[ERROR] 프로세스 'agent-app' 가 실행 중이 아닙니다` 만 보이면  
> → 앱이 꺼진 것이니 다른 터미널에서 앱을 다시 실행하세요.
> ```bash
> su - agent-admin
> source ~/.bashrc
> $AGENT_HOME/agent-app
> ```

---

## 11. 로그 파일 관리

### 개념 — 왜 로그 관리가 필요한가?

> 매분 한 줄씩 쌓이면 하루 1440줄, 한 달이면 43200줄이 됩니다.  
> 관리 안 하면 디스크가 가득 차서 서버가 멈출 수 있습니다.  
> 일정 크기가 넘으면 파일을 나눠서 보관하는 것을 **log rotate**라고 합니다.

### 개념 — `>` 와 `>>` 의 차이

> ```bash
> echo "내용" >  파일   # 덮어쓰기: 기존 내용 전부 사라짐
> echo "내용" >> 파일   # 추가하기: 기존 내용 끝에 붙임
> ```
> 로그는 반드시 `>>` 를 사용해야 합니다.  
> `>` 를 쓰면 매분 덮어써서 마지막 기록만 남습니다.

### rotate 방식

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
─────────────────        ──────────────────────────
monitor.log (11MB)  →   monitor.log       ← 새 빈 파일
monitor.log.1       →   monitor.log.1     ← 방금 전 로그
monitor.log.2       →   monitor.log.2
...
monitor.log.9       →   monitor.log.9.gz  ← 압축됨
```

---

## 12. 증거 자료 체크리스트

| # | 확인 항목 | 상태 | 확인 명령어 |
|---|-----------|:----:|-------------|
| 1 | SSH 포트 20022 변경 | ✅ | `grep '^Port' /etc/ssh/sshd_config` |
| 2 | Root 원격 로그인 차단 | ✅ | `grep 'PermitRootLogin' /etc/ssh/sshd_config` |
| 3 | UFW 활성화 확인 | ✅ | `ufw status` |
| 4 | 20022/tcp, 15034/tcp만 허용 | ✅ | `ufw status` |
| 5 | 계정 3개 생성 확인 | ✅ | `id agent-admin && id agent-dev && id agent-test` |
| 6 | 그룹 2개 생성 확인 | ✅ | `cat /etc/group \| grep agent` |
| 7 | 디렉토리 구조 확인 | ✅ | `ls -la $AGENT_HOME` |
| 8 | ACL 권한 확인 | ✅ | `getfacl $AGENT_HOME/upload_files` |
| 9 | 환경 변수 설정 확인 | ✅ | `printenv \| grep AGENT` |
| 10 | 키 파일 내용 확인 | ✅ | `cat $AGENT_HOME/api_keys/secret.key` |
| 11 | Boot Sequence 5단계 [OK] | ✅ | `$AGENT_HOME/agent-app` 실행 출력 |
| 12 | Agent READY 출력 확인 | ✅ | 앱 실행 로그 |
| 13 | 15034 포트 LISTEN 확인 | ✅ | `ss -tulnp \| grep 15034` |
| 14 | monitor.sh 권한 확인 | ✅ | `ls -la $AGENT_HOME/bin/monitor.sh` |
| 15 | monitor.sh 수동 실행 확인 | ✅ | `$AGENT_HOME/bin/monitor.sh` |
| 16 | monitor.log 기록 확인 | ✅ | `tail /var/log/agent-app/monitor.log` |
| 17 | crontab 매분 등록 확인 | ✅ | `crontab -l` |
| 18 | 1분 후 로그 자동 누적 확인 | ✅ | `watch -n 30 tail /var/log/agent-app/monitor.log` |

---

## 13. 트러블슈팅

### 파일 전송이 안 될 때 (orb push 에러)

```bash
# orb push 가 cp 에러를 내면 → /mnt/mac 직접 복사 방식 사용

# VM 안에서 Mac 파일에 직접 접근
ls /mnt/mac/Users/                        # Mac 계정 폴더 확인
ls /mnt/mac/Users/본인맥이름/Downloads/   # 파일 위치 확인

# 직접 복사 (인텔 맥 + amd64 VM = x86 버전)
cp /mnt/mac/Users/본인맥이름/Downloads/agent-app-linux-x86 /tmp/agent-app

# 파일 이름이 agent-app-linux-x86 / arm64 두 개로 나뉨
# → 인텔 맥(amd64)은 x86 사용
```

### SSH 포트 변경 후 적용이 안 될 때

```bash
# 설정 파일 변경 후 반드시 재시작 필요
systemctl restart ssh

# 재시작 후 포트 확인
ss -tulnp | grep sshd
# 20022가 보이면 성공
```

### 앱 실행 시 `[FAIL]` 이 날 때

```bash
# 1단계 FAIL: root로 실행했을 때
su - agent-admin
$AGENT_HOME/agent-app

# 2단계 FAIL: 환경변수 없을 때
source ~/.bashrc
printenv | grep AGENT

# 3단계 FAIL: 키 파일 내용이 다를 때
cat $AGENT_HOME/api_keys/secret.key
# 정확히 "agent_api_key_test" 한 줄만 있어야 함

# 5단계 FAIL: 로그 폴더 권한 없을 때
su -
chmod 770 /var/log/agent-app
chown agent-admin:agent-core /var/log/agent-app
exit
```

### cron이 실행이 안 될 때

```bash
# cron 서비스 상태 확인
systemctl status cron

# cron 로그 확인
grep CRON /var/log/syslog | tail -10

# cron 서비스 재시작
su -
systemctl restart cron
exit
```

### VM 재시작 후 확인사항

```bash
# VM은 서비스가 자동 시작됨
systemctl status ssh    # SSH 자동 시작 확인
systemctl status cron   # cron 자동 시작 확인
ufw status              # UFW 자동 활성화 확인

# 앱만 다시 실행
su - agent-admin
source ~/.bashrc
$AGENT_HOME/agent-app &
```

---

*Ubuntu 24.04 LTS OrbStack VM 환경 기준으로 작성되었습니다.*
