ARG DOCKERHUB_PROXY=docker.io
FROM ${DOCKERHUB_PROXY}/library/node:22-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

RUN npm run build -- --configuration=production


FROM ${DOCKERHUB_PROXY}/library/nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY --from=build /app/dist/frontend/browser/ /usr/share/nginx/html/

COPY nginx.conf /etc/nginx/conf.d/default.conf

CMD ["nginx", "-g", "daemon off;"]