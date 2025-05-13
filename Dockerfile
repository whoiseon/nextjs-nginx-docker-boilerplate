FROM node:18-alpine AS base

FROM base AS deps

# Alpine Linux 호환성 설정
# Alpine Linux는 glibc 대신 musl libc를 사용하는데, 이는 크기가 작고 성능이 좋지만
# glibc로 컴파일된 일부 Node.js 네이티브 모듈이나 바이너리가 실행되지 않을 수 있다.
# 이러한 호환성 문제를 해결하기 위해 libc6-compat 패키지를 설치하여
# glibc 기반 프로그램들이 정상적으로 동작할 수 있도록 한다.
RUN apk add --no-cache libc6-compat

# 작업 디렉토리 설정
# 각 FROM(stage)이 시작되면 이전 stage의 설정이 초기화되므로
# 작업 디렉토리를 다시 설정해야 함
# 이는 각 stage에서 실행되는 명령어들의 컨텍스트를 일관되게 유지하기 위함
WORKDIR /app

# yarn 설치
RUN corepack enable && corepack prepare yarn@stable --activate

# 의존성 설치
# 패키지 설치에 필요한 파일만 복사하고 의존성 패키지 설치
COPY package.json yarn.lock ./
RUN yarn install

# --------- Builder Stage -----------
FROM base AS builder
WORKDIR /app

# 소스 코드 복사 및 빌드
COPY . .
COPY --from=deps /app/node_modules ./node_modules
RUN yarn build

# --------- Runner Stage -----------
FROM base AS runner
WORKDIR /app

# 보안 설정 1: 비특권 사용자/그룹 생성
# 컨테이너 보안을 위한 중요 설정
# 이 설정을 하지 않을 경우:
# 1. 컨테이너가 root 권한으로 실행되어 보안 취약점 발생 가능
# 2. 컨테이너가 해킹당했을 때 공격자가 root 권한을 획득할 수 있음
# 3. 호스트와 컨테이너 간 파일 권한 충돌 발생 가능
# 4. 클라우드 제공업체의 보안 정책 위반 가능성
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# 보안 설정 2: 파일 권한 설정
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# 보안 설정 3: 비루트 사용자 전환
USER nextjs

# 포트 및 환경 설정
EXPOSE 3000
ENV PORT 3000

# 애플리케이션 실행
CMD ["node", "server.js"]