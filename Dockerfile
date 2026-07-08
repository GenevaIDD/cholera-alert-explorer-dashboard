# ===========================================================================
# Dockerfile  ->  image: alerts-app
#
# The "specific" layer, analogous to the cholera-mapping-pipeline build that
# sits on top of the base: it starts FROM alerts-base, adds the app-specific
# R packages, copies the app, and launches it on port 3838 for ShinyProxy.
#
# Build (after building alerts-base):
#   docker build -t alerts-app:1.0 -t alerts-app:latest .
#
# Run locally to test (browse http://localhost:3838):
#   docker run --rm -p 3838:3838 alerts-app:latest
# ===========================================================================

FROM alerts-base:latest

# --- App-specific R packages ----------------------------------------------
RUN R -q -e "install.packages(c('kableExtra','patchwork'))"

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
