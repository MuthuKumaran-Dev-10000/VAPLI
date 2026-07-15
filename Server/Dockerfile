FROM python:3.11-slim

WORKDIR /app

# Copy requirements first for Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all server files
COPY . .

# Expose port 8080 (Cloud Run standard port)
EXPOSE 8080

# Set environment variables
ENV SERVER_HOST=0.0.0.0
ENV SERVER_PORT=8080

# Start the server (web server auto-starts inside main())
CMD ["python", "server.py", "--no-interactive"]
