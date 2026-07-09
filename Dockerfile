# ===========================================================================
# Dockerfile  ->  image: alerts-app
#
# Single-stage image: R + system libraries, then the app's R packages, then
# the app code itself. Built fresh per app rather than layered on a shared
# base image, since future apps are expected sporadically rather than
# sharing a common base.
#
# Build:
#   docker build -t alerts-app:1.0 -t alerts-app:latest .
#
# Run locally to test (browse http://localhost:3838):
#   docker run --rm -p 3838:3838 alerts-app:latest
# ===========================================================================

# Pin the R version we developed and tested against (Ubuntu 22.04 "jammy").
FROM rocker/r-ver:4.3.3

# --- System libraries required by the app's R packages --------------------
# xml2 (kableExtra) -> libxml2-dev; curl/ssl -> web + package installs;
# the font/graphics libs are needed to render ggplot2 / patchwork plots;
# libuv1-dev -> fs (a shiny/httpuv dependency), needed since packages
# currently compile from source rather than installing as binaries (see
# note below).
RUN apt-get update && apt-get install -y --no-install-recommends \
      pandoc \
      libcurl4-openssl-dev \
      libssl-dev \
      libxml2-dev \
      libfontconfig1-dev \
      libfreetype6-dev \
      libharfbuzz-dev \
      libfribidi-dev \
      libpng-dev \
      libtiff5-dev \
      libjpeg-dev \
      libcairo2-dev \
      libuv1-dev \
      locales \
 && rm -rf /var/lib/apt/lists/*

# --- UTF-8 locale ----------------------------------------------------------
# The alert-definition labels contain the ">=" glyph; a UTF-8 locale ensures
# it renders (the app also sets this defensively at startup).
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# --- Reproducible package versions ----------------------------------------
# Freeze on a dated Posit Public Package Manager snapshot so rebuilds get the
# same versions, regardless of when the image is rebuilt. Note: this endpoint
# currently serves source packages rather than precompiled binaries (verified
# on both amd64 and arm64), so builds compile everything from source and take
# a while. Bump the date to re-pin against a newer snapshot; keep "jammy" in
# sync with the base image's Ubuntu codename.
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/2026-07-08"))' \
      >> /usr/local/lib/R/etc/Rprofile.site

# --- App's R packages --------------------------------------------------
## `arrow` (for Parquet I/O) fetches a prebuilt Arrow C++ binary internally
## during its own configure step; if that lookup ever fails for the build
## architecture it falls back to a full source build of Arrow C++, which
## additionally needs cmake >= 3.26 (not installed here, since the fallback
## hasn't been hit in practice).
RUN R -q -e "install.packages(c('shiny','dplyr','tidyr','ggplot2','arrow','kableExtra','patchwork'))"

# --- App code + data -------------------------------------------------------
# .dockerignore keeps Dockerfiles, the guide, and dev cruft out of the image.
RUN mkdir -p /srv/alerts_app
COPY . /srv/alerts_app

# ShinyProxy expects the app to listen on port 3838.
EXPOSE 3838

# Launch on 0.0.0.0:3838 so ShinyProxy can reach it. (application.yml may
# override this via container-cmd, but keeping it here lets the image run
# standalone too.)
CMD ["R", "-e", "shiny::runApp('/srv/alerts_app', host = '0.0.0.0', port = 3838)"]
