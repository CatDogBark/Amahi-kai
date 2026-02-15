# Amahi Platform - Development Environment
# Updated for Ubuntu 24.04 (was Fedora 29)
# Ruby 3.2.x via system packages, Rails 7.2
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /amahi

# Install system dependencies
RUN apt-get update && apt-get install -y \
  ruby ruby-dev \
  build-essential \
  libmariadb-dev mariadb-client mariadb-server \
  libsqlite3-dev \
  libxml2-dev libxslt-dev \
  zlib1g-dev libffi-dev libssl-dev libreadline-dev libyaml-dev \
  git curl unzip \
  smbclient dnsmasq \
  mlocate \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

# Install bundler
RUN gem install bundler --no-document

# Copy Gemfile and install dependencies
COPY Gemfile /amahi/Gemfile
RUN bundle install --without production

# Copy application code
COPY . /amahi

# Initialize MariaDB data directory
RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld && \
    mysql_install_db --user=mysql && \
    mysqld_safe & sleep 3 && \
    mysql -e "CREATE DATABASE IF NOT EXISTS hda_development;" && \
    mysql -e "CREATE DATABASE IF NOT EXISTS hda_test;" && \
    mysqladmin shutdown

EXPOSE 3000

CMD ["bundle", "exec", "rails", "s", "-b", "0.0.0.0"]
