FROM python:3.11-slim

ENV PYTHONUNBUFFERED True

ENV APP_HOME /app
WORKDIR $APP_HOME
COPY . ./

# Install python dependencies
RUN pip install --no-cache-dir -r requirements.txt

CMD ["python", "main.py"]
