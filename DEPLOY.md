# Deploying the Cholera Alert Explorer on ShinyProxy

This mirrors the cholera-mapping-pipeline's **two-image** pattern:

| cholera-mapping-pipeline | alerts app            | contents                                        |
|--------------------------|-----------------------|-------------------------------------------------|
| base image               | `alerts-base`         | R + system libraries + common/heavy R packages  |
| build on top of base     | `alerts-app`          | app-specific packages + the app code + launch   |

ShinyProxy runs one Docker container per user session; each app is a Docker
image whose Shiny process listens on **port 3838**. ShinyProxy is told which
image to run in its `application.yml`.

---

## 1. Decide on the base image

Two options:

- **A. Dedicated `alerts-base` (recommended, mirrors the pipeline).** Build
  `Dockerfile.base` as-is. Self-contained and independent of the pipeline.
- **B. Reuse the cholera-mapping-pipeline base.** If that base already ships a
  suitable R + system-library layer, point `Dockerfile`'s first line at it
  instead (`FROM <cholera-base-image>:<tag>`) and drop `Dockerfile.base`. Ask
  whoever maintains the pipeline images for the exact registry path/tag, and
  confirm it has R 4.3.x and the system libs listed in `Dockerfile.base`.

The rest of this guide assumes option A.

---

## 2. Build the images

From the `alerts_app/` directory (which contains both Dockerfiles):

```bash
# base layer
docker build -f Dockerfile.base -t alerts-base:1.0 -t alerts-base:latest .

# app layer (starts FROM alerts-base:latest)
docker build -f Dockerfile -t alerts-app:1.0 -t alerts-app:latest .
```

The app's runtime R dependencies are `shiny, dplyr, tidyr, ggplot2,
kableExtra, patchwork` (everything else is base R). `alerts-base` installs the
first four; `alerts-app` adds `kableExtra` and `patchwork`.

---

## 3. Test the app image standalone

```bash
docker run --rm -p 3838:3838 alerts-app:latest
# then open http://localhost:3838
```

You should see both tabs (View 1 utility table + Figure-2 panel, View 2
anonymised explorer). Check the ">=" glyph renders in the alert labels — if
it shows as boxes, the locale step in `Dockerfile.base` didn't take.

---

## 4. Make the image available to ShinyProxy

- **Same host as ShinyProxy:** nothing to do — a locally built image is
  immediately usable.
- **Separate host / production:** push to your registry and reference the full
  path in `application.yml`:

```bash
docker tag alerts-app:1.0 registry.example.org/alerts-app:1.0
docker push registry.example.org/alerts-app:1.0
```

---

## 5. Register the app in `application.yml`

Add a spec under `proxy.specs` (ShinyProxy 3.x syntax):

```yaml
proxy:
  specs:
    - id: alerts
      display-name: Cholera Alert Explorer
      description: Alert utility scores and an anonymised time-series explorer
      container-image: alerts-app:latest        # or registry.example.org/alerts-app:1.0
      container-cmd: ["R", "-e", "shiny::runApp('/srv/alerts_app', host = '0.0.0.0', port = 3838)"]
      # port: 3838                # default; only needed if you change the port
      # access-groups: [ researchers ]   # restrict access; omit = all authenticated users
```

Notes:
- `container-cmd` here is optional because the image already sets the same
  `CMD`; include it if you prefer the launch command to live in config.
- If ShinyProxy runs containers on a user-defined Docker network, add
  `container-network: "${proxy.docker.container-network}"` to the spec.
- Restart ShinyProxy after editing `application.yml` (e.g.
  `sudo systemctl restart shinyproxy`, or rebuild/restart its container; the
  ShinyProxy Operator picks up changes automatically).

---

## 6. Resource sizing (optional)

Each session loads a few small tables plus the two ~1.3 MB distribution files
and the 7.4 MB alert-groups file — memory use per container is modest (a few
hundred MB). If you want to cap it, set container CPU/memory limits per the
ShinyProxy configuration docs for your version.

---

## 7. Reproducibility

- The R version is pinned via `rocker/r-ver:4.3.3`.
- Package versions are pinned via the dated Posit Package Manager snapshot in
  `Dockerfile.base` (`.../jammy/2025-01-31`). Bump that date deliberately when
  you want to move packages forward, and keep the `jammy` codename in sync
  with the base image's Ubuntu release.
- For exact lockfile-level reproducibility instead, commit an `renv.lock` and
  `RUN R -e "renv::restore()"` in place of the `install.packages(...)` lines.

---

## Data files baked into the image

`data/` is copied into the image, so the app is self-contained:

- `complete_utility_data_mean_sd.csv` — View 1 utility table
- `compare_significant_impact_testmeans_epidemic.parquet`,
  `compare_significant_efficiency_testmeans_epidemic.parquet`,
  `compare_significant_delay_testmeans_epidemic.parquet` — View 1 boxplots
- `alert_groups_nweeks8.parquet`, `time_series_preoutbreak_extraction.parquet` — View 2

To refresh any of these, replace the file and rebuild `alerts-app` (the base
image doesn't need rebuilding). If the data becomes large or sensitive, mount
it at runtime with `container-volumes` instead of baking it in.
