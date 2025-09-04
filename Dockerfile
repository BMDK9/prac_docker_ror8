# syntax=docker/dockerfile:1
# check=error=true
# -----메타 지시어(directive), 빌드 전처리 지시어 주석이 아닌 영향있는 코드----
# 순서대로
# 최신 안정 버전의 문법을 쓰겠다
# Dockerfile에서 에러가 나는 구문이 있으면 무조건 빌드 중단

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t docker_prac .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name docker_prac docker_prac

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
# libjemalloc2: Ruby 속도 개선용 메모리 관리 도구
# libvips: 이미지 처리용 라이브러리 (Rails의 이미지 업로드/리사이즈에 필요)
# 마지막 줄은 설치 후 필요 없는 캐시를 지워서 이미지 용량을 줄임
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="development" \
    BUNDLE_PATH="/usr/local/bundle"
# ENV RAILS_ENV="production" \
#     BUNDLE_DEPLOYMENT="1" \
#     BUNDLE_PATH="/usr/local/bundle"
#     BUNDLE_WITHOUT="development"
# -------------베이스 이미지 정의------------------------------

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
# -----------------베이스 이미지를 바탕으로 실행 파일들 빌드, 최종 이미지에서는 제외됨.--------------



# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0"]
# ---------------실행 파일 빌드 결과물만 사용하여 이미지를 생성------------------