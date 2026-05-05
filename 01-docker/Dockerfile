# Dockerfile
# - Multi-stage build: builder aşamasında bağımlılıkları kur
# - Final aşamada yalnızca çalışma zamanı dosyalarını kopyala
# - Non-root kullanıcı oluştur ve ona geç
# - EXPOSE ile uygulama portunu belirt
# - HEALTHCHECK talimatı ekle
# - CMD ile uygulamayı başlat
# Template 3.8 kullanıyordu fakat EOL olduğu için 3.12'ye yükseltmeyi dusunuyorum (yapildi)

FROM python:3.12-slim AS builder 
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim

#LABEL`lar opsiyonel ama uygulama hakkında bilgi vermek için kullanışlı olabilir
LABEL maintainer="DevOps Engineer Candidate: Deniz YALDIZ <denizyaldiz2003@gmail.com>" \
      org.opencontainers.image.title="streamlit-case-app" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/DenizYald3iz/devops-case-study" \
      org.opencontainers.image.description="A simple Streamlit app for DevOps case study" 

RUN groupadd -r appuser && useradd -r -g appuser -m appuser

WORKDIR /app
# builder'dan paketleri al
COPY --chown=appuser:appuser --from=builder /root/.local /home/appuser/.local
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONPATH=/home/appuser/.local/lib/python3.12/site-packages

USER appuser

# Dosyaları kopyalarken sahipliğini appuser'a verdim cunku permission roota kalabilir
COPY --chown=appuser:appuser . /app

EXPOSE ${STREAMLIT_SERVER_PORT:-8501}

ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh"]