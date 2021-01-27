# Start from ubuntu
FROM ubuntu:16.04

# Update repos and install dependencies
RUN apt-get update \
  && apt-get -y upgrade \
  && apt-get -y install git build-essential \
    libsqlite3-dev zlib1g-dev libssl-dev \
    python3-dev python3-pip gzip curl wget \
    libspatialindex-dev unzip locales

# Set locale for UTF 8 encoding in shell
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create a directory and copy in all files
RUN mkdir -p /tmp/tippecanoe-src
RUN git clone -b 1.32.9 https://github.com/mapbox/tippecanoe.git /tmp/tippecanoe-src
WORKDIR /tmp/tippecanoe-src

# Build tippecanoe
RUN git checkout -b master && \
  make && \
  make install

# Remove the temp directory
WORKDIR /
RUN rm -rf /tmp/tippecanoe-src

# Symlink NodeJS and install NPM packages
RUN curl -sL https://deb.nodesource.com/setup_7.x | bash - && \
  ln -s /usr/bin/nodejs /usr/bin/node && \
  apt-get -y install nodejs && \
  npm install -g mapshaper@0.4.106 geojson-polygon-labels@1.2.1 csv2geojson algolia-csv csv-parse

# Install rust, cargo, and xsv
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
RUN /bin/bash -c "source $HOME/.cargo/env \
  && cargo install xsv"

COPY . /app
WORKDIR /app/

# Install packages
RUN npm install
RUN npm install csv-parse

# FIX: newer versions of setuptools does not support python 3.5, use older version 
ENV PYTHONWARNINGS=ignore:DEPRECATION
RUN pip3 install --upgrade 'pip<21' 'setuptools<51'

# Install Python packages
RUN pip3 install pipenv
RUN pipenv install --system

# make entrypoint executable
RUN chmod +x run-task.sh
RUN chmod +x build.sh

# Add cargo to path
ENV PATH="/root/.cargo/bin:$PATH"

ENTRYPOINT ["./build.sh"]
