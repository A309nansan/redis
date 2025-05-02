#!/bin/bash

# 명령어 실패 시 스크립트 종료
set -euo pipefail

# 로그 출력 함수
log() {
echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 에러 발생 시 로그와 함께 종료하는 함수
error() {
log "Error on line $1"
exit 1
}

trap 'error $LINENO' ERR

log "스크립트 실행 시작."

# docker network 생성
if docker network ls --format '{{.Name}}' | grep -q '^nansan-network$'; then
log "Docker network named 'nansan-network' is already existed."
else
log "Docker network named 'nansan-network' is creating..."
docker network create --driver bridge nansan-network
fi

# 실행중인 redis container 삭제
log "redis container remove."
docker rm -f redis

# 기존 redis 이미지를 삭제하고 새로 빌드
log "redis image remove and build."
docker rmi redis:latest || true
docker build -t redis:latest .

# 필요한 환경변수를 Vault에서 가져오기
log "Get credential data from vault..."

TOKEN_RESPONSES=$(curl -s --request POST \
--data "{\"role_id\":\"${ROLE_ID}\", \"secret_id\":\"${SECRET_ID}\"}" \
https://vault.nansan.site/v1/auth/approle/login)

CLIENT_TOKEN=$(echo "$TOKEN_RESPONSES" | jq -r '.auth.client_token')

SECRET_RESPONSE=$(curl -s --header "X-Vault-Token: ${CLIENT_TOKEN}" \
--request GET https://vault.nansan.site/v1/kv/data/authentication)

REDIS_PASSWORD=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.redis.password')

# Docker로 redis 서비스 실행
log "Execute redis..."
docker run -d \
  --name redis \
  --restart unless-stopped \
  -v /var/redis:/data \
  -p 11201:6379 \
  -e REDIS_ARGS="--requirepass ${REDIS_PASSWORD}" \
  -e REDISEARCH_ARGS="MAXEXPANSIONS 200" \
  -e REDISJSON_ARGS="DEBUG MEMORY" \
  --network nansan-network \
  redis:latest

echo "작업이 완료되었습니다."
