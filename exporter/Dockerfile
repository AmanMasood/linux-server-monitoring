FROM python:3.12-slim
RUN pip install --no-cache-dir psutil==6.0.0 && useradd --system exporter
WORKDIR /app
COPY exporter.py .
USER exporter
EXPOSE 9200
CMD ["python", "exporter.py"]
