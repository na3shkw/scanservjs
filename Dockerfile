# Builder image
#
# Builds the JavaScript app and installs production-only node dependencies.
# ==============================================================================
FROM node:18-bookworm-slim AS scanservjs-build
ENV APP_DIR=/app
WORKDIR "$APP_DIR"

COPY package*.json build.js "$APP_DIR/"
COPY app-server/package*.json "$APP_DIR/app-server/"
COPY app-ui/package*.json "$APP_DIR/app-ui/"

RUN npm clean-install .

COPY app-server/ "$APP_DIR/app-server/"
COPY app-ui/ "$APP_DIR/app-ui/"

RUN npm run build \
  && npm clean-install --omit=dev --prefix dist \
  && find dist -name "*.map" -type f -delete

# Base image
#
# Installs OS-level dependencies shared across all targets.
# ==============================================================================
FROM debian:bookworm-slim AS scanservjs-base
RUN apt-get update \
  && apt-get install -yq \
    nodejs \
    gosu \
    imagemagick \
    sane-airscan \
    sane-utils \
    tesseract-ocr \
    tesseract-ocr-jpn \
  && rm -rf /var/lib/apt/lists/* \
  && echo "airscan" >> /etc/sane.d/dll.conf \
  && sed -i 's/^#discovery = enable/discovery = disable/' /etc/sane.d/airscan.conf

# Core image
#
# Minimum image required to run scanservjs. The executing user is root.
# If you want to build your own image with additional drivers, start from here.
# ==============================================================================
FROM scanservjs-base AS scanservjs-core
ENV \
  # This goes into /etc/sane.d/net.conf
  SANED_NET_HOSTS="" \
  # This gets added to /etc/sane.d/airscan.conf
  AIRSCAN_DEVICES="" \
  # This gets added to /etc/sane.d/pixma.conf
  PIXMA_HOSTS="" \
  # This directs scanserv not to bother querying `scanimage -L`
  SCANIMAGE_LIST_IGNORE="" \
  # This gets added to scanservjs/server/config.js:devices
  DEVICES="" \
  # Override OCR language
  OCR_LANG="" \
  # Runtime user/group (0 = run as root)
  PUID=0 \
  PGID=0

# Create runtime directories and configure ImageMagick policies
RUN mkdir -p \
      /var/lib/scanservjs/output \
      /var/lib/scanservjs/preview \
      /var/lib/scanservjs/temp \
      /var/lib/scanservjs/thumbnail \
      /etc/scanservjs \
  && if [ -d /etc/ImageMagick-6 ]; then \
       sed -i 's/rights="none" pattern="PDF"/rights="read | write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml; \
       sed -i 's/name="disk" value="1GiB"/name="disk" value="8GiB"/' /etc/ImageMagick-6/policy.xml; \
     fi \
  && if [ -d /etc/ImageMagick-7 ]; then \
       sed -i 's/rights="none" pattern="PDF"/rights="read | write" pattern="PDF"/' /etc/ImageMagick-7/policy.xml; \
       sed -i 's/name="disk" value="2GiB"/name="disk" value="8GiB"/' /etc/ImageMagick-7/policy.xml; \
       sed -i 's/domain="path" rights="none" pattern="@/domain="path" rights="read" pattern="@/' /etc/ImageMagick-7/policy.xml; \
     fi

# Copy app files from builder
COPY --from=scanservjs-build /app/dist/client            /usr/lib/scanservjs/client
COPY --from=scanservjs-build /app/dist/server            /usr/lib/scanservjs/server
COPY --from=scanservjs-build /app/dist/node_modules      /usr/lib/scanservjs/node_modules
COPY --from=scanservjs-build /app/dist/package.json      /usr/lib/scanservjs/
COPY --from=scanservjs-build /app/dist/package-lock.json /usr/lib/scanservjs/
COPY --from=scanservjs-build /app/dist/data/preview/     /var/lib/scanservjs/preview/
COPY --from=scanservjs-build /app/dist/config/           /etc/scanservjs/

# Create symlinks the app uses to locate data and config at runtime
RUN ln -s /var/lib/scanservjs /usr/lib/scanservjs/data \
  && ln -s /etc/scanservjs /usr/lib/scanservjs/config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /usr/lib/scanservjs

EXPOSE 8080

# default build
FROM scanservjs-core

# hplip image
#
# Adds HP scanner libs. Not built by default — specify --target scanservjs-hplip.
# ==============================================================================
FROM scanservjs-core AS scanservjs-hplip
RUN apt-get update \
  && apt-get install -yq libsane-hpaio \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && echo hpaio >> /etc/sane.d/dll.conf

# brscan4 image
#
# Adds Brother scanner driver. Not built by default — specify --target scanservjs-brscan4.
# ==============================================================================
FROM scanservjs-core AS scanservjs-brscan4
RUN apt-get update \
  && apt-get install -yq curl \
  && curl -fSsL "https://download.brother.com/welcome/dlf105200/brscan4-0.4.11-1.amd64.deb" -o /tmp/brscan4.deb \
  && apt-get remove curl -yq \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && dpkg -i /tmp/brscan4.deb \
  && rm /tmp/brscan4.deb \
  && echo brscan4 >> /etc/sane.d/dll.conf
