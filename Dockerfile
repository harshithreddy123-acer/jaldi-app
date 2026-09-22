# Stage 1: Build Flutter Web app
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

# Fetch dependencies and compile web release
RUN flutter pub get
RUN flutter build web --release \
    --dart-define=SUPABASE_URL=https://inbcxvslbcfqdclufhdj.supabase.co \
    --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_ZrUvJlyWbQKHuYcNti-Ruw_V0BNKnXp

# Stage 2: Serve using Nginx
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
