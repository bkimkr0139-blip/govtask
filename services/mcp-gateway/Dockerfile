# MCP Gateway - STUB (미구현)
# 실제 구현 전까지 헬스 엔드포인트만 제공하는 자리표시 컨테이너.
# docker-compose 의 'full' 프로파일에서만 빌드/기동된다.
FROM node:20-alpine
WORKDIR /app
COPY server.cjs ./
EXPOSE 8088
CMD ["node", "server.cjs"]
