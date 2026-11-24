# Warracker for Railway: the official image, pinned by version and digest.
# Upstream: https://github.com/sassanix/Warracker (AGPL-3.0)
FROM ghcr.io/sassanix/warracker/main:1.0.7@sha256:72fba72a19ac2f6710068010d3ff3dafcf47d52a4ddc7e8db3e35847fa8bb01c

COPY --chown=root:root railway-start.sh railway-run.sh /app/
COPY --chown=root:root railway_init.py /app/railway_init.py
RUN chmod 755 /app/railway-start.sh /app/railway-run.sh

# Railway routes the public domain to $PORT; /data is the Railway volume.
ENV PORT=8080 \
    UPLOAD_FOLDER=/data/uploads

ENTRYPOINT ["/app/railway-start.sh"]
CMD []
