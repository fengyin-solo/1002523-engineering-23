FROM node:20-alpine
WORKDIR /srv/web
COPY package.json ./
RUN npm install
COPY . .
EXPOSE 5173
# 监听地址/端口/代理目标全部由 docker-compose 注入（来源是统一的 .env）
CMD ["sh", "-c", "npm run dev -- --host ${FRONTEND_HOST:-0.0.0.0} --port ${FRONTEND_PORT:-5173}"]
